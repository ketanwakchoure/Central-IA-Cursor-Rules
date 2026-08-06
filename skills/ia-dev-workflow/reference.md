# IA Dev Workflow — Full Command Reference

Detailed commands for [SKILL.md](SKILL.md). Session variables (`BASE`, `TOK`, `NS_CONN`,
`INTEGRATION_ID`, `CONNECTOR_ID`, `SHOP_ID`, `NS_ACCOUNT`, `BUNDLE_FOLDER`) are assumed set.

## 1. Environment bring-up

The local dev loop is: **integrator.io → ngrok tunnel → local connector server (port 80)**.
Both local pieces die between sessions. Symptoms of a dead link:
- dead tunnel/server → first flow bubble fails `invalid_extension_response` with an ngrok HTML
  502 page in the error body; settings saves 404 with the same HTML.
- server down behind a live tunnel → ngrok log shows `failed to open private leg ... connection refused`.

### 1.1 Connector server

```bash
lsof -ti :80 -sTCP:LISTEN | xargs kill        # clear stale process (else EADDRINUSE)
NODE_ENV=development aws_access_key_id=local-dev aws_secret_access_key=local-dev \
  aws_region=us-east-1 npm start
# wait for: logName=serverStarted ... port=80
curl -s -o /dev/null -w "%{http_code}" http://localhost:80/     # expect 200
```

Run it in a persistent terminal — processes backgrounded from throwaway shells get reaped.

### 1.2 ngrok tunnel + stack registration

Free-plan ngrok URLs rotate on restart; integrator.io reaches the connector through a
**stack** record whose `server.hostURI` must match the current tunnel.

```bash
ngrok http 80 --log stdout        # grab the new https://....ngrok-free.app URL
curl -s -o /dev/null -w "%{http_code}" "https://<NEW>.ngrok-free.app/" \
  -H "ngrok-skip-browser-warning: 1"           # must be 200 end-to-end

# find the stack: GET $BASE/connectors/$CONNECTOR_ID -> _stackId
# system token: env/development.json INTEGRATOR_EXTENSION_SYSTEM_TOKEN
curl -s -X PUT -H "Authorization: $TOK" -H "Content-Type: application/json" \
  -d '{"name":"<stack name>","type":"server","server":{"systemToken":"<SYSTEM_TOKEN>","hostURI":"https://<NEW>.ngrok-free.app","ipRanges":[]}}' \
  "$BASE/stacks/<STACK_ID>"
```

### 1.3 Scripted bring-up, health check, and stack-drift detection

Server and tunnel **will** die between sessions (machine sleep, session cleanup, ngrok free-plan
limits) — treat every session start as "assume dead, verify, restore". Run this triple check
FIRST, before debugging anything that traverses the extension path:

```bash
# 1. server alive?              2. tunnel alive + current URL (scripted, no log-scraping)?
curl -s -o /dev/null -w "server:%{http_code}\n" --max-time 4 http://localhost:80/
curl -s --max-time 4 http://localhost:4040/api/tunnels \
  | python3 -c "import sys,json; print(json.load(sys.stdin)['tunnels'][0]['public_url'])"
# 3. stack pointing at THAT url? (drift check - the piece people forget)
curl -s -H "Authorization: $TOK" "$BASE/stacks/<STACK_ID>" \
  | python3 -c "import sys,json; print(json.load(sys.stdin)['server']['hostURI'])"
```

If (2) and (3) disagree, re-register (§1.2) — a stale hostURI produces the same
`invalid_extension_response` symptoms as a dead tunnel. `localhost:4040/api/tunnels` is
ngrok's local API and the only reliable scripted way to read the current URL; free-plan URLs
rotate on every restart, so never cache one across restarts.

To launch both from a script/agent shell (survives the invoking shell; logs captured):

```bash
( NODE_ENV=development aws_access_key_id=local-dev aws_secret_access_key=local-dev \
  aws_region=us-east-1 npm start > /tmp/connector-server.log 2>&1 & )
( ngrok http 80 --log stdout > /tmp/ngrok.log 2>&1 & )
sleep 12   # then run the triple check above; end-to-end tunnel 200 needs
           # -H "ngrok-skip-browser-warning: 1"
```

The subshell-`&` wrapping detaches them from the launching shell; they still die with the
machine/session, which is why the triple check — not the launch — is the invariant.

---

## 2. integrator.io API operations

### 2.0 Token facts

| Token | Use it for |
|---|---|
| user token (`CELIGO_IO_TOKEN`) | flows/jobs/integrations/scripts/stacks reads & writes, persistSettings, backend proxy calls |
| connector token | rarely useful directly — most writes return 401/`access_restricted`; connector identity only applies to code running server-side |

The `.env` values already include the `Bearer ` prefix — pass them verbatim as the
`Authorization` header. Doubling the prefix produces `400 Bearer Authentication Failed`.

### 2.1 Run a flow and wait

```bash
curl -s -X POST -H "Authorization: $TOK" -H "Content-Type: application/json" -d '{}' \
  "$BASE/flows/<FLOW_ID>/run"                                   # -> {_jobId}
curl -s -H "Authorization: $TOK" "$BASE/flows/<FLOW_ID>/jobs/latest"
```

Terminal states: `completed`, or `failed` carrying `numError`. Poll every ~5s, discard jobs
whose `createdAt` predates your run.

Gotchas:
- Running a **disabled** flow returns `422 invalid_flow` — enable it first (persistSettings
  `{flowId, disabled:false}`, § 2.3), which also sets connector storemap flags a direct
  `PUT /flows/<id>` skips.
- **Delta/batch exports advance `lastExportDateTime` on every run** — even a run that matched
  nothing. Records created *before* the previous run's end date are never picked up again;
  seed test data *after* the last run, or expect `ok:0` with no error anywhere.

### 2.2 Per-bubble results and errors

```bash
curl -s -H "Authorization: $TOK" "$BASE/jobs?_parentJobId=<JOB_ID>"      # one child per bubble
curl -s -H "Authorization: $TOK" "$BASE/flows/<FLOW_ID>/<RESOURCE_ID>/errors"
```

Filter errors client-side by `occurredAt >= run start` — the endpoint returns historical open
errors too. On newer tiles the legacy `GET /jobs/<id>/joberrors` returns 404 — the
flow/resource `errors` endpoint above is the errors-2.0 replacement. Retry failed records in
place (no new export needed, works even when the delta window has moved on):

```bash
# each error carries retryDataKey; batch them:
curl -s -X POST -H "Authorization: $TOK" -H "Content-Type: application/json" \
  -d '{"retryDataKeys":["<key1>","<key2>"]}' \
  "$BASE/flows/<FLOW_ID>/<RESOURCE_ID>/retry"
```

### 2.3 Saving IA settings programmatically (persistSettings)

IA settings can NOT be changed by PUTting the integration document (silently ignored). They go
through the connector's settings pipeline, and for multistore integrations the `pending` body
**must be keyed by shopId** or the handler silently no-ops:

```bash
curl -s -X PUT -H "Authorization: $TOK" -H "Content-Type: application/json" -d '{
  "pending": { "'$SHOP_ID'": {
      "<full_setting_field_name>": "<value>",
      "<staticMapWidget_field_name>": { "map": { "<key>": "<value>" } },
      "flowId": "<FLOW_ID>", "disabled": false
  } }
}' "$BASE/integrations/$INTEGRATION_ID/settings/persistSettings"
```

Verification is mandatory: `200 {"success":true}` only means the connector was reached. Re-GET
the integration and walk `settings.sections` for the field; also watch the local server log
for `callFunctionInvoked ... function=persistSettings` and the specific handler's log line.
Setting field names embed resource ids (`imports_<id>_settingName`,
`shopid_<id>_widgetName_...`) — they change after a reinstall (§ 2.5).

Two behaviors worth exploiting:

- **Setting handlers only run on save.** Derived artifacts (per-store saved-search status
  filters, export filter expressions, mappings the handler injects) can be out of sync on a
  fresh install until the driving setting is saved once. *Re-saving a setting with its current
  value* is a legitimate fix — it re-runs the handler and rebuilds the artifact.
- **Handlers enforce cross-flow dependencies** and return `422` validation errors (e.g. a
  billing-mode switch requiring the transaction flow enabled). Satisfy the dependency first
  via `{flowId:"<dependency_flow_id>", disabled:false}` persistSettings, then retry.

### 2.4 Editing platform script records

Flow-level `postResponseMap` (and similar) hooks execute a **platform script record** on IO —
not connector code. The repo file is only the source of truth; the deployed copy is the script
record's `content` and must be pushed explicitly.

```bash
# 1) ALWAYS back up first
curl -s -H "Authorization: $TOK" "$BASE/scripts/<SCRIPT_ID>" -o /tmp/script_backup.json
# 2) PUT the FULL record (name + content + sandbox); partial bodies -> 422 "Script fields are invalid"
# 3) VERIFY with a fresh GET - the PUT response does NOT echo content
curl -s -H "Authorization: $TOK" "$BASE/scripts/<SCRIPT_ID>" | grep -c "newFunctionName"
```

Shared-script rule: these records are often shared across flows (fulfillment, returns, …).
Append or edit surgically; keep the backup until the epic ships; restore it after throwaway
experiments (e.g. temporarily shrinking a chunk-size constant to test splitting behavior).

### 2.5 Changing IA-locked resource config (the reinstall pattern)

Installer-owned fields on flows/imports/exports (hooks, oneToMany, mappings, …) are locked:
PATCH → `422 field_locked_by_integration_app` / "not a whitelisted property"; PUT → 200 but
silently ignored. To apply local installer-config changes to a staging integration, reinstall
the add-on (or store) — the connector serves configs from your working tree:

```bash
curl -s -X PUT -H "Authorization: $TOK" -H "Content-Type: application/json" \
  -d '{"addOnId":"<ADDON>","storeId":"'$SHOP_ID'"}' \
  "$BASE/integrations/$INTEGRATION_ID/uninstaller/uninstallAddOn"
curl -s -X PUT -H "Authorization: $TOK" -H "Content-Type: application/json" \
  -d '{"addOnId":"<ADDON>","storeId":"'$SHOP_ID'"}' \
  "$BASE/integrations/$INTEGRATION_ID/installer/installAddOn"
```

After reinstall **all resource ids change**: re-apply settings (field names embed the new
ids), re-enable flows, and restart the connector server if any hook keeps per-resource
in-memory state (e.g. demo rotation caches). Any automation you build should resolve resource
ids dynamically by `externalId`, never hardcode them.

Installer manifests to keep in sync when adding/removing resources:
`configs/installer/addOns/verifyAddOnInstall.json` (creation order via `dependson` — a flow
must depend on every resource its jsonpath wires in) and the add-on's `upload-*.json`
(writes ids into `settings.addOnMap`).

### 2.6 Existing-customer changes (update code)

The reinstall pattern is dev-only. Production migrations for existing customers go through
`scripts/updateCodeRepo/<version>.js` running **inside the connector** (that identity may
modify IA-locked resources). Update scripts must be idempotent, save state per step
(`getState`/`saveState`), and are driven by `scriptInputs.json` (integration id lists built
via `buildScriptInputs.js`). Plan this as its own deliverable in any epic that changes
installed resources for existing customers.

### 2.7 Create a new tile + DIY Shopify (skip browser OAuth)

Full create (not reuse). Stack/ngrok must be healthy first (§1.3).

```bash
# 0) free license? if none, create with the UI payload shape:
# POST https://iaqa.staging.integrator.io/api/connectors/$CONNECTOR_ID/licenses
# (or $BASE/connectors/$CONNECTOR_ID/licenses — same body)
curl -s -H "Authorization: $TOK" "$BASE/connectors/$CONNECTOR_ID/licenses"
curl -s -X POST -H "Authorization: $TOK" -H "Content-Type: application/json" \
  -d '{
    "_connectorId":"'"$CONNECTOR_ID"'",
    "email":"<io-user-email>",
    "expires":"08/03/2027",
    "sandbox":"false",
    "opts":{
      "connectorEdition":"premium",
      "addonLicenses":[
        {"type":"store","licenses":[{"addOnEdition":"premium"},{"addOnEdition":"premium"},{"addOnEdition":"premium"}]},
        {"type":"addon","licenses":[{"addOnId":"payout"},{"addOnId":"payout"}]}
      ]
    }
  }' \
  "$BASE/connectors/$CONNECTOR_ID/licenses"

# 1) create tile (returns integration + NS + Shopify connection ids)
curl -s -X POST -H "Authorization: $TOK" -H "Content-Type: application/json" \
  -d '{"sandbox":false,"tag":"store3-e2e-diy-<ts>","newTemplateInstaller":false}' \
  "$BASE/integrations/$CONNECTOR_ID/install"

# 2) NS TBA on connection-netsuite id, ping, then:
curl -s -X PUT -H "Authorization: $TOK" -H "Content-Type: application/json" -d '{}' \
  "$BASE/integrations/<ID>/installer/verifyNetSuiteConnection"

# 3) DIY Shopify — concrete baseURI required (yourstorename placeholder -> 401)
TOKEN=$(python3 -c "import base64; print(base64.b64decode('<b64 from STORE_N>').decode())")
STORE=backward-auto-store3-e2e   # STORE_8 in rest-api-ia E2E_*.env
# PUT connections/<shopifyId> with auth.type=token + token + settings.storeName
# + http.baseURI=https://$STORE.myshopify.com  (NOT yourstorename / handlebars alone)
curl -s -H "Authorization: $TOK" "$BASE/connections/<SHOPIFY_CONN>/ping"   # {"code":200}

# 4) remaining installer steps in order
for fn in verifyProductConnection verifyIntegratorBundleInstallation \
          verifyProductBundleInstallation configureQuickStartSettings; do
  curl -s -X PUT -H "Authorization: $TOK" -H "Content-Type: application/json" \
    -d '{}' "$BASE/integrations/<ID>/installer/$fn"
done
# configureQuickStartSettings needs formVal.configureopts=configurelater (see ai-eic CONFIGURE_FORMVAL)
```

Store token map: `CONNECTIONS.SHOPIFY_STORE_{N}_TOKEN` (base64) in `rest-api-ia/env/E2E_*.env`.
**store8** = `backward-auto-store3-e2e`. Do not hardcode `_httpConnectorVersionId` from old
`buildDiyShopifyPayload` snapshots (`422 invalid_ref`).

Browser OAuth fallback: `celigo/ai-eic` `POST /api/ia-tool/shopify-auth` (Playwright).

### 2.8 Shopify — minimum settings for first order sync

After Step 8 with `configurelater`, Order/Discount/Tax/static maps are empty. Persist the
minimum below (shopId-keyed `pending`, §2.3) before expecting a sales order in NetSuite.
Field names embed resource ids — resolve from `storemap` / settings (`salesOrderImportId`,
`salesOrderExportId`, `onDemandOrderFlowId`, shop id).

Mirror rest-api-ia order-import fixtures (e.g. `T24658` `updateSettings`): set **both** the
discount *mode* and the discount *item name* (`DIS00000`). Env refs:
`DEFAULT_DISCOUNT.DISCOUNTS.0.NAME=DIS00000` / `.CODE=630` in `rest-api-ia/env/E2E_*.env`.
Refresh discount/item selects first when `options`/`generates` are empty (`REFRESH_MAP` in
those env files lists the UI labels).

| Area | Setting (UI label) | API value / notes |
|---|---|---|
| Flow | Sales order (add) enabled | `{flowId, disabled:false}` |
| On-demand | Shopify order IDs | `exports_<soExportId>_orderImportIds` = Shopify id; Save triggers on-demand flow then clears the field |
| Status | Sync web orders … status | `capture` (typical) |
| General | Location map | `{map:{"<nsLocId>":"<shopifyLocId>"}, default:"<shopifyLocId>", allowFailures:true}` — required; empty map → validation error |
| Discount | Cart discounts as | `DISCOUNT` + item **DIS00000** |
| Discount | Line discounts as | `NEW_LINE` + item **DIS00000** |
| Discount | Item selects (`yieldValueAndLabel`) | Prefer `{id:"630", label:"DIS00000"}` (see unit tests / settings helpers). Confirm import mapping got `discountitem` hardCodedValue |
| Tax | Sync sales tax as | `OVERRIDE_TAX_TOTALS` → default tax code **must be taxable** (reject `-7`/`-8`) |
| Tax | Per-line + Deduct GST/VAT | See **§2.8.1 Tax settings — source of truth** (do not guess from store country) |
| Item | NetSuite SKU field | `nameinternal` |

#### 2.8.1 Tax settings — source of truth (NetSuite + Shopify)

Do **not** hardcode US/GST from the store name. Derive these two IA checkboxes from live
backends every time you set up a tile:

1. **`isTransactionLineLevelTaxEnabled` (Per-line taxes on transaction enabled in NetSuite)**  
   Must match NetSuite **Setup → Taxes → Set Up Taxes → USA → “Per-Line Taxes on Transactions”**.  
   SuiteQL cannot read that preference page directly; prove it from data instead:

   ```sql
   -- Per-line ON if item lines (not tax lines) carry taxcode on recent SOs
   SELECT COUNT(*) AS cnt
   FROM transaction t
   INNER JOIN transactionLine tl ON tl.transaction = t.id
   WHERE t.type = 'SalesOrd'
     AND tl.mainline = 'F' AND tl.taxline = 'F'
     AND tl.taxcode IS NOT NULL
     AND t.createddate >= SYSDATE - 30
   ```

   - `cnt > 0` (typical on 1288) → set IA per-line **true**  
   - Also sanity-check US tax types exist: `SELECT id, name, country FROM taxType WHERE country = 'US'`  
   - Pick a **US** default tax code (`salesTaxItem.nexuscountry = 'US'`, e.g. `637` New York State).  
     Do **not** use Canada GST codes (e.g. `7436` GST CA_5) just because the Shopify shop is CA.

2. **`isGstVatTaxHandlingEnabled` (Deduct GST/VAT from the order total)**  
   Comes from **Shopify tax-inclusive pricing**, not from NetSuite country:

   ```bash
   # shop-level (authoritative for the store)
   GET /admin/api/.../shop.json  →  shop.taxes_included
   # or GraphQL: { shop { taxesIncluded } }
   # spot-check recent orders: order.taxes_included
   ```

   - `taxes_included` / `taxesIncluded` **true** (most orders tax-inclusive) → Deduct GST/VAT **true**  
   - **false** (tax-exclusive) → Deduct GST/VAT **false**  

   Example (store3-e2e on 1288): shop is CA/CAD with `taxesIncluded: true` → GST deduct **true**,
   while NS USA per-line is still **true** (those two settings are independent).
| Item | Missing SKU fallbacks | Internal id of NI/other-charge on the **customer’s subsidiary** |
| Shipping | Ship method map | e.g. `Standard Shipping` → NS ship method id; **must be valid for customer subsidiary** (Canada Shipping Test / wrong sub → `invalid_key_or_ref`) |
| Payment | Payment method map | **Billing-path dependent** — see **§2.8.2**. `manual` → Cash (`1`) is correct for **cash sale** auto-bill; for **invoice** auto-bill the SO must have **no** Payment Method |
| Shipping cost | Shipping as line item | Leave empty unless NI item is sub-matched; wrong sub → `Please choose an item to add` |

#### 2.8.2 Auto-billing gate: Payment Method required for cash sale, forbidden for invoice

The NetSuite → auto-bill export does **not** use the flow name alone. Both
`cashSaleExportPreSendHook` and `invoiceExportPreSendHook` call the same
`AutoBillingExport.validateData`, which keeps or drops each saved-search row by whether
the search column **`Payment Method`** is truthy:

```javascript
// legacy-suitescript-products/shopify/hooks/Celigo.products.shopify.hooks.AutoBillingExport.js
if ((result["Payment Method"] && that.getFlowType() === "CashSale") ||
    (!result["Payment Method"] && that.getFlowType() === "Invoice")) {
  data.push(result)
}
```

| Auto-bill flow | `Payment Method` on the SO (search column) | Result |
|---|---|---|
| Cash sale (`flowType: "CashSale"`) | **Must be set** (truthy) | Row exported |
| Cash sale | empty / missing | **Silently dropped** → export `ok:0` |
| Invoice (`flowType: "Invoice"`) | **Must be empty** | Row exported |
| Invoice | set (e.g. Cash / `1`) | **Silently dropped** → export `ok:0` |

**Practical check (SuiteQL):**

```sql
SELECT id, otherrefnum, paymentmethod, BUILTIN.DF(paymentmethod) pm, status, BUILTIN.DF(status) st
FROM transaction
WHERE id = <soInternalId>
```

- `paymentmethod` populated → qualifies for **cash sale** auto-bill only.  
- `paymentmethod` null → qualifies for **invoice** auto-bill only.

**How Payment Method gets onto the SO:** Order import’s payment static map
(`paymentmethodLookup`, e.g. Shopify gateway `manual` → NS Cash). Mapping gateway → Cash
is correct when the tile bills as cash sale; it **blocks** `NetSuite sales order to NetSuite
invoice` even when status filters / once-flags are right.

**Fixture evidence:** SuiteScript extension tests use `"Payment Method":"Cash"` for cash-sale
auto-bill import fixtures and `"Payment Method":""` for invoice fixtures
(`AutoBillingImportAsCashSale.js` / `AutoBillingImportAsInvoice.js`).

**Also check** Billing → “Auto-bill orders in NetSuite when the status is” matches the SO’s
real status after fulfillment (e.g. `SalesOrd:F` Pending Billing when capture is after
fulfillment — not `SalesOrd:B` Pending Fulfillment). Wrong status filter and wrong Payment
Method gate both present as export `ok:0` with no import errors.

Common failure signatures after first sync:

| Error | Fix |
|---|---|
| `missing_static_lookup` (ship method) | Map Shopify title → NS ship method; refresh generates |
| `invalid_key_or_ref` shipmethod … for entity | Pick a ship method on the customer’s subsidiary |
| `value_lookup_failed` `nameinternal` isempty | Set missing-SKU fallback; or fix empty SKUs on the Shopify order |
| `Please choose an item to add` | Discount/shipping/variance item missing or wrong subsidiary — set DIS00000; clear or fix shipping NI |
| `duplicate_order_found` … NS Id# | Prior run succeeded — look up that SO; do not treat as setup failure |

Verify: SuiteQL `transaction` where `otherrefnum='#<shopifyOrderName>'` (or
`custbody_celigo_shopify_order_no`), and that line items include `DIS00000` when the order
had cart/line discounts.

---

## 3. Inspecting the backend

All access goes through IO's generic connection proxy — no direct backend credentials needed:

```
POST $BASE/connections/<CONN_ID>/proxy
  Integrator-Method: GET|POST|PUT|DELETE
  Integrator-Relative-URI: <path on the backend>
```

`io_proxy.py` (repo root) wraps this with subcommands (`suiteql`, `raw`, `shopify`, `netsuite`).

### 3.1 SuiteQL (read-only workhorse)

```bash
python3 io_proxy.py suiteql "SELECT id, memo FROM transaction WHERE type = 'Deposit' AND memo IN ('...')" --limit 20
```

Mechanics: user token (standalone SuiteTalk connections reject the connector token with
`access_restricted`), `Prefer: transient` header. Schema quirks that will bite again:
- `transaction` has `trandate`, not `datecreated`/`created`.
- Per-line GL accounts: `transactionline tl JOIN transactionaccountingline tal ON
  tal.transaction = tl.transaction AND tal.transactionline = tl.id`.
- `customrecordtype` uses `internalid`, not `id`.
- Custom record tables are their script ids; "Unknown identifier" on a column usually means
  that custom field doesn't exist in this account yet (record customization pending).
- Burst queries hit `429 CONCURRENCY_LIMIT_EXCEEDED` — back off 30–60s.

### 3.2 REST record API through the proxy (read + targeted writes)

```bash
python3 io_proxy.py raw "$NS_CONN" GET "/services/rest/record/v1/<type>/<id>"
python3 io_proxy.py raw "$NS_CONN" GET "/services/rest/record/v1/<type>/<id>/<sublist>?expandSubResources=true"
CELIGO_IO_CONNECTOR_TOKEN="" python3 io_proxy.py raw "$NS_CONN" DELETE "/services/rest/record/v1/<type>/<id>"
```

Performance rule: never expand a whole record or fetch a "selection" sublist in a big account
(a deposit's `payment` sublist enumerates every undeposited transaction — 100k+ rows →
guaranteed timeout). Fetch the header (has server-computed totals) plus only the small
sublists you actually wrote. For money assertions trust the header `total` over reconstructing
it from sublists.

Writes require the user token (`CELIGO_IO_CONNECTOR_TOKEN=""` forces io_proxy to fall back).
Keep writes single-record and targeted; log ids of everything you create/delete (§ cleanup).

### 3.3 Finding records in the backend UI

Custom records don't appear under Transactions. Build direct list URLs from the record type's
numeric internal id:

```sql
SELECT internalid, name, scriptid FROM customrecordtype WHERE name LIKE '%<Name>%'
```
→ `https://<NS_ACCOUNT>.app.netsuite.com/app/common/custom/custrecordentrylist.nl?rectype=<internalid>`

Standard transactions: normal menus (e.g. deposits at
`/app/accounting/transactions/deposit.nl`), filtered by whatever identifying field the IA
writes (memo, custom body field, account).

### 3.4 Verifying third-party API claims live

Before trusting a design-doc assumption about an external API, verify against the real thing —
e.g. Shopify Admin GraphQL introspection to validate an enum a settings widget exposes:

```bash
curl -s -X POST "https://<shop>.myshopify.com/admin/api/<version>/graphql.json" \
  -H "X-Shopify-Access-Token: $SHOPIFY_TOKEN" -H "Content-Type: application/json" \
  -d '{"query":"{ __type(name: \"<EnumName>\") { enumValues { name } } }"}'
```

Same for shape questions (nullability, pagination `pageInfo`, wrapper objects) — one live
query settles debates that code reading cannot.

### 3.5 Saved searches: run standalone, and read the real definition

Connector exports are usually "run saved search N through the generic RESTlet". Two techniques
turn hours of criteria-guessing into minutes:

**Run the export's saved search standalone** (no flow run, no once-flag side effects on
matched... note: the RESTlet itself does NOT apply the once filter — that's added by IO — so
this is a pure search-eligibility probe):

```bash
CELIGO_IO_NS_CONNECTION_ID=<tile NS connection id> python3 io_proxy.py netsuite POST / \
  --script-id customscript_celigo_rt_import_rest --deploy-id customdeploy_celigo_rt_import_deploy \
  --body '{"integrator":true,"pageSize":25,"recordType":"transaction","searchId":"<SEARCH_ID>","criteria":[],"columns":[]}'
# -> {"data":[[...rows...]], "debugLogs":[...]}  — empty data = your record fails the criteria
```

**Dump the search's actual filter expression** when NetSuite UI access isn't available: saved
search definitions aren't exposed via REST/SuiteQL, but the ns-test runner
(`legacy-suitescript-products/tools/test-runner`) executes arbitrary SuiteScript server-side.
Write a throwaway TestCase that loads the search and leaks the definition through ERROR-level
log lines (assertion-failure messages do NOT print payloads; `[ERROR]` log lines DO appear in
runner output — chunk long JSON into ~300-char pieces):

```javascript
new Celigo.Test.TestCase({
  name: "Dump Search Definition", init: function(){ this.Assert = Celigo.Test.Assert; },
  test_dump: function () {
    var json = JSON.stringify(nlapiLoadSearch(null, <SEARCH_ID>).getFilterExpression());
    for (var i = 0; i < json.length; i += 300) $$.logExecution('ERROR', 'DUMP_' + (i/300), json.substring(i, i+300));
    this.Assert.areSame(1, 1, 'done');
  }
})
// node tools/test-runner/bin/ns-test.js --file testing/<product>/hooks/<File>.js | rg DUMP_
```

This is how "billing export returns 0 records" was solved: the search wanted
`SalesOrd + mainline T + status SalesOrd:G (Billed = fulfilled AND invoiced) + channel + store`
— nothing in configs or docs said so.

**Grouped record shape:** RESTlet search exports return `data: [[row, row], [row], ...]` — each
"record" is an ARRAY of search rows (one per transaction line). IO's mapping layer reads row 0
implicitly, so extracts work — but connector hooks (`preMap` etc.) receive the raw array and
must unwrap `record[0]` themselves (and return the original grouped shape). Failure signature:
a hook reports a field missing that the mapping extracts fine.

---

## 4. SuiteScript / bundle workflow

NetSuite-side hooks ship inside a compiled bundle file (e.g.
`Celigo_ShopifyConnector.closure.js`). Source edits do nothing at runtime until the closure is
rebuilt AND uploaded to the account's bundle folder.

```bash
# 0) isolate the branch in a worktree; keeps the main checkout untouched
git worktree add /tmp/<epic>-wt <branch>

# 1) edit source + tests, syntax check every touched file
node --check <hook>.js

# 2) rebuild the closure (expect: 0 errors, 0 warnings)
cd build/<connector> && ant -f build-<Connector>.xml

# 3) deploy via the test-runner restlet (legacy-suitescript-products/tools/test-runner)
node -e "require('dotenv').config({path:__dirname+'/.env'});
const fs=require('fs'), api=require('./src/api');
(async()=>{ const c=fs.readFileSync('<worktree>/build/.../X.closure.js','utf8');
  console.log(await api.uploadFile('X.closure.js','$BUNDLE_FOLDER', c, '<FILE_ID>'));
})();"

# 4) VERIFY: getFileInfo(<FILE_ID>).size must equal the local file's byte length
```

Rules and gotchas:
- New hook functions referenced by import configs must exist in the **deployed** closure or
  NetSuite throws `invalid hook function "<name>"`.
- New source files need a `build/.../*.properties` entry, and ns-test coverage needs the
  source uploaded to the File Cabinet.
- **Stale compile cache**: NetSuite may serve the previous compiled copy for a minute or two
  after upload. Wait 60s and rerun before concluding a deploy failed; force it by uploading
  under a fresh filename if iterating hard.
- Test files follow the in-account harness conventions — stub NetSuite globals
  (`nlapiCreateRecord` etc.) by save/replace/restore in a `try/finally`, and only use
  assertion helpers already present in the suite (`areSame`, `isTrue`, `isFalse`).
