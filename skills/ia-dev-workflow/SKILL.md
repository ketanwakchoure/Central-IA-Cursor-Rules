---
name: ia-dev-workflow
description: Develop, debug, deploy, and live-verify Celigo Integration App (IA) flows against integrator.io staging plus a backend (NetSuite, Shopify, etc.). Covers local connector server + ngrok bring-up, running/polling flows via the integrator.io API, saving IA settings (persistSettings), editing platform script records, applying installer-config changes via add-on reinstall, inspecting backend records (SuiteQL / REST proxy), rebuilding and deploying SuiteScript bundles, diagnosing governance timeouts and silent data loss, and building a live verification harness. Use when developing or debugging any IA epic on staging, or when the user mentions "run the flow", "check NetSuite records", "SuiteQL", "ngrok"/"tunnel", "persistSettings", "reinstall the add-on", "platform script", "rebuild the closure/bundle", "script execution time exceeded", "invalid hook function", or asks to verify a flow end-to-end.
---

# IA Flow Development & Live Verification

Operational playbook for any epic spanning integrator.io (staging), a local connector server,
and a backend (NetSuite/Shopify/etc). Battle-tested across a full payout-migration epic.

## Session variables & credentials

Never hardcode tokens, account IDs, or any credential value in this skill, in `reference.md`,
in `troubleshooting.md`, or in any file meant to be committed — these are shared/repo-tracked.
All real values live **only** in the repo-root `.env` (gitignored) and are read at runtime.

Repo epics typically develop against one long-lived shared staging integration + NetSuite
sandbox. `.env` uses this naming convention — populate it once, reuse across epics:

| `.env` key | What it holds |
|---|---|
| `CELIGO_IO_BASE_URL` | integrator.io API base (e.g. iaqa staging) |
| `CELIGO_IO_TOKEN` | user bearer token — use for almost everything (§ Step 2-4) |
| `CELIGO_IO_CONNECTOR_TOKEN` | connector-scoped bearer — rarely usable directly, most writes 401 |
| `CELIGO_IO_INTEGRATION_ID` | the staging integration under test |
| `CELIGO_IO_NS_SUITETALK_CONNECTION_ID` | standalone SuiteTalk HTTP connection — required for SuiteQL/REST proxy calls |
| `CELIGO_IO_NS_DEFAULT_ACCOUNT` | NetSuite account id (e.g. `tstdrv1288246`) — used to build UI deep-links |
| `CELIGO_IO_SH_STORE{N}_CONNECTION_ID` | Shopify (or other backend) store connections |
| `CELIGO_IO_STACK_ID` | stack fronting the local server — PUT `server.hostURI` here on ngrok rotation |
| `CELIGO_IO_CONNECTOR_ID` | IA/connector id — required as `_connectorId` in `exports/preview` payloads |
| `CELIGO_IO_SHOP_ID` | primary staging store section id (the `shopid_` prefix on settings fields) |
| `CELIGO_IO_NS_BUNDLE_FOLDER` / `_CLOSURE_FILE_ID` | bundle folder + deployed closure file id (upload target) |
| `CELIGO_IO_POST_RESPONSE_MAP_SCRIPT_ID` | platform script carrying flow-level postResponseMap hooks |
| `CELIGO_IO_NS_TBA_ICLIENT_ID` | reusable NetSuite TBA iClient (consumer pair) for Step 8 fresh installs |
| `CELIGO_NS_TBA_ENV_PATH` | pointer to the ONE file holding NetSuite TBA values (test-runner `.env`) — never duplicate token values across files |
| `CELIGO_IO_SH_STORE3_E2E_*` | optional ids for a DIY-installed `backward-auto-store3-e2e` tile (`INTEGRATION_ID`, `CONNECTION_ID`, `SHOP_ID`, `STORE_NAME`) — tokens stay in `rest-api-ia/env/E2E_*.env` (`STORE_8`) |

**Customer/production credentials are never persisted** — use them session-scoped (headers,
not URLs), delete any script that held them before ending the session, and keep usage
read-only (see Step 7b). If root `.env` isn't gitignored in your clone, add it to
`.git/info/exclude` (local-only, no repo commit) before anything else.

If a new epic needs a NetSuite login (direct UI access, not just the proxy), get it from the
team's shared secrets manager / 1Password — never paste it into a skill, doc, or code file.
If `.env` doesn't exist yet, copy it from a teammate or the shared vault; check
`git check-ignore -v .env` returns a match before ever running `git add .` in this repo.

Load these into shell variables at the start of a session (never echo the values):

```bash
BASE=$(grep '^CELIGO_IO_BASE_URL=' .env | cut -d= -f2-)
TOK=$(grep '^CELIGO_IO_TOKEN=' .env | cut -d= -f2-)              # already includes "Bearer "
NS_CONN=$(grep '^CELIGO_IO_NS_SUITETALK_CONNECTION_ID=' .env | cut -d= -f2)
INTEGRATION_ID=$(grep '^CELIGO_IO_INTEGRATION_ID=' .env | cut -d= -f2)
NS_ACCOUNT=$(grep '^CELIGO_IO_NS_DEFAULT_ACCOUNT=' .env | cut -d= -f2)
CONNECTOR_ID=...   SHOP_ID=...   BUNDLE_FOLDER=... # e.g. "SuiteBundles/Bundle 75328" — per epic, not secret
```

## Workflow

### Step 1 — Bring up the environment

1. Kill anything on port 80, start the connector server (`NODE_ENV=development
   aws_access_key_id=local-dev aws_secret_access_key=local-dev aws_region=us-east-1 npm
   start`), confirm `curl localhost:80/` → `200`.
2. Start `ngrok http 80 --log stdout`, confirm the tunnel is reachable end-to-end (not just
   ngrok's own 200 — send `ngrok-skip-browser-warning: 1`).
3. Re-point the connector's **stack** `server.hostURI` at the new tunnel URL (`GET
   $BASE/connectors/$CONNECTOR_ID` → `_stackId`, then `PUT $BASE/stacks/<id>`).

First-bubble `invalid_extension_response` with an ngrok HTML body in the error, or
`persistSettings` returning 200/404 with no real effect, both mean this step is stale —
redo it before debugging anything else. Start every session with the **triple health check**
(server 200 → tunnel URL from `localhost:4040/api/tunnels` → stack `hostURI` matches that
URL); server and tunnel die between sessions, and a stale stack hostURI mimics a dead tunnel.
Scripted launch + drift check: [reference.md](reference.md#13-scripted-bring-up-health-check-and-stack-drift-detection).

### Step 2 — Run and poll a flow

```bash
curl -s -X POST -H "Authorization: $TOK" -H "Content-Type: application/json" -d '{}' \
  "$BASE/flows/<FLOW_ID>/run"                              # -> {_jobId}
# poll every ~5s; ignore jobs whose createdAt < your start time
curl -s -H "Authorization: $TOK" "$BASE/flows/<FLOW_ID>/jobs/latest"
```

Read `numError/numSuccess/numIgnore` on the terminal job. For a **per-bubble** breakdown (which
step actually failed/received nothing), use `$BASE/jobs?_parentJobId=<JOB_ID>` — a bubble with
`ok:0 err:0 ign:0` received zero records silently (see Step 5). Per-record errors live at
`GET $BASE/flows/<fid>/<resourceId>/errors` (legacy `/jobs/<id>/joberrors` 404s on newer
tiles); failed records can be re-driven in place via the `/retry` endpoint — important because
**delta exports advance their window every run**, so a fresh run won't re-pick old records.
Open errors can be bulk-marked resolved (clean dashboard without re-running):
`PUT $BASE/flows/<fid>/<resourceId>/resolved` with `{"errors": ["<errorId>", ...]}`.
A disabled flow run returns `422 invalid_flow` — enable via persistSettings `{flowId,
disabled:false}`. Details: [reference.md](reference.md#2-integratorio-api-operations).

### Step 3 — Change settings or config

- **Setting values** (`persistSettings`): body must be `{"pending": {"<SHOP_ID>": {...}}}` —
  unkeyed bodies silently no-op on multistore integrations. A `200 {"success":true}` does NOT
  confirm the value changed; always re-GET the integration and check
  `settings.sections[...].fields[...].value`. Handlers run **only on save**: re-saving a
  setting with its current value legitimately rebuilds derived artifacts (per-store
  saved-search filters, export filters) that a fresh install leaves out of sync. Handler `422`s
  like "enable X flow first" are cross-flow dependencies — enable the dependency via
  `{flowId, disabled:false}` and retry.
- **Platform script records** (flow `postResponseMap`/etc hooks): back up the record, PUT the
  full `{name, content, sandbox}` body, verify with a fresh GET (the PUT response doesn't echo
  content). These records are often shared across flows — edit surgically, restore the backup
  when done experimenting.
- **IA-locked resource fields** (hooks, `oneToMany`, mappings on flows/imports/exports): PATCH
  returns `422 field_locked_by_integration_app`; PUT returns 200 but is silently ignored. Use
  the **add-on/store reinstall pattern** instead — uninstall then reinstall the add-on, which
  recreates every resource from your local configs. All resource ids change on reinstall;
  never hardcode them, resolve by `externalId` instead.
- **Handlebars-in-JSON bodies** (export/paging templates): a `{{/if}}` (or any `}}`-closing tag)
  immediately followed by JSON `}` braces parses as a triple-stache and fails with
  `handlebars_template_parse_error`. Put a space between the closing tag and the JSON braces
  (`{{/if}} }}` — see the shipped paging exports for the canonical pattern), and build the
  template by `json.dumps`-ing the query string then splicing the `{{...}}` parts in — never
  hand-escape.

Full command forms: [reference.md](reference.md#2-integratorio-api-operations).

### Step 4 — Inspect the backend

Everything goes through the IO connection proxy — no direct backend credentials needed.

```bash
python3 io_proxy.py suiteql "SELECT id, memo FROM transaction WHERE type='Deposit' AND memo='<id>'"
python3 io_proxy.py raw "$NS_CONN" GET "/services/rest/record/v1/<type>/<id>/<sublist>?expandSubResources=true"
CELIGO_IO_CONNECTOR_TOKEN="" python3 io_proxy.py raw "$NS_CONN" DELETE "/services/rest/record/v1/<type>/<id>"
```

**Never** expand a whole record or fetch a "selection" sublist (e.g. a deposit's `payment`
sublist enumerates every undeposited transaction in the account) — it times out in any
non-trivial account. Fetch the header (has server-computed totals) + only the small sublists
you actually wrote. Writes need the **user** token. Full schema quirks and UI-link construction:
[reference.md](reference.md#3-inspecting-the-backend).

When an export returns 0 records against seemingly eligible data, don't guess the saved
search's criteria: run the search standalone through the generic RESTlet, or dump its real
filter expression with a throwaway ns-test TestCase (assertion messages don't print payloads;
`[ERROR]` log lines do). RESTlet search exports also return **grouped records** (each record =
array of rows) — hooks must unwrap `record[0]`; the mapping layer does it implicitly. Both
techniques: [reference.md](reference.md#35-saved-searches-run-standalone-and-read-the-real-definition).

Two more inspection channels and one rule:

- **`POST $BASE/integrations/<id>/exports/preview`** runs an ad-hoc virtual export in IA
  context with only the user token — the way to query a connector-managed backend connection
  when direct `/connections/<id>/proxy` returns `access_restricted`. The payload MUST include
  `_connectorId` alongside `_connectionId`, or it fails `invalid_ref` (the settings-form UI
  has the same requirement — connector-managed virtual resources always carry both).
- **NetSuite identifier probes**: NetSuite returns **zero rows, not an error**, for an invalid
  filter value (wrong `recordType` string, bad field id) — so a wrong identifier looks exactly
  like "no data". Never trust self-authored unit fixtures to validate an identifier (the
  fixture encodes the same assumption as the code); prove every new NetSuite string identifier
  with one live search/SuiteQL count before merging.
Seeding flow-eligible data (backend-valid orders, fulfillment/billing state, error-scenario
patching): [troubleshooting.md](troubleshooting.md#seeding-flow-eligible-test-data-store--backend-pipeline).

### Step 5 — Debug data-loss / timeouts / platform quirks

Before assuming a code bug, check for these known platform behaviors:

- **One-to-many imports** write response mappings onto each *child* object, never the parent —
  a downstream bubble needs its own `postResponseMap` hook to hoist child values up.
  `pathToMany` cannot read nested arrays. Partial-child-failure + retry can wipe already-
  succeeded children's response mappings (acknowledged platform bug).
- **Settings readers**: generic settings helpers often copy only `field.value` for
  additionalFields matches — a widget field carrying `map`/`entities` needs the sections walked
  directly.
- **Governance timeouts** (`sss_time_limit_exceeded`): identical timestamps across failures
  means one batched invocation blew the execution window. Quantify the expensive search's
  candidate set (`SELECT COUNT(*) ...`), then apply the product's designed mitigation (date
  window / batch size settings) and re-measure.
- **Connection debug logs** are the decisive tool for "data disappeared between bubbles": PATCH
  `debugDate` (JSON-Patch format) on the connection, run the flow, GET `/connections/<id>/debug`
  for the full RESTlet request/response bodies.
- **The rerun probe** (finds idempotency bugs that look "random"): run the flow to a clean
  baseline, snapshot per-key record counts (e.g. deposits per payout id), then run again with
  NO cleanup and diff the snapshots plus job stats. Timing-dependent duplicates present as
  *inconsistent per-key counts* (one key duplicated, another timed out) because a governance
  race decides each record's fate — one rerun rarely shows the full picture, so run it more
  than once before concluding. Any import without a dedup/ignore-existing guard will fail
  this probe; fix by searching for the record's identity **before** the expensive work (kills
  the duplicate AND the timeout together), and stamp a deterministic identity on created
  records so future runs can match them.

Full diagnosis patterns: [troubleshooting.md](troubleshooting.md).

### Step 6 — SuiteScript / bundle changes (NetSuite-side hooks)

Source edits do nothing until the closure is rebuilt **and** uploaded to the account's bundle
folder:

```bash
git worktree add /tmp/<epic>-wt <branch>          # isolate the branch
node --check <hook>.js                             # after editing
cd build/<connector> && ant -f build-<Connector>.xml   # expect 0 errors, 0 warnings
# deploy via the test-runner restlet, then verify uploaded size == local file size
```

New hook functions must exist in the **deployed** closure or NetSuite throws `invalid hook
function`. NetSuite may serve a stale compiled copy for ~60s after upload — wait and retry
before concluding the deploy failed. Full steps: [reference.md](reference.md#4-suitescript--bundle-workflow).

### Step 7 — Build a verification harness, then clean up

For any epic, write a standalone script that: resolves resource ids dynamically → cleans prior
artifacts (children before the records they reference) → arranges the scenario via
persistSettings → runs + polls the flow → asserts against the backend (recompute expected
values from the same routing rules the hook uses; compare counts/fields/totals/linkages, not
just "no errors") → reports a PASS/FAIL matrix. Run multiple scenarios (happy path,
fallback/negative config, idempotent rerun). Add cheap unit-test guard rails that pin any
constant to the data file it must match, so drift fails CI instead of demos.

Always end a session with the sandbox clean: delete dependent records before the records they
reference, and restore any script/bundle backups you took. See
[troubleshooting.md](troubleshooting.md#cleanup-checklist).

### Step 7b — Isolated experiments: throwaway standalone flows & live-account validation

When the shared IA integration is in active QA use, don't experiment on it. Build a throwaway
**standalone** pipeline instead: standalone connection(s) → standalone export (paste the IA
export's query/body) → a harmless sink import (POST to the local stack's `/` via the tunnel)
→ a temp flow. Run it, read the export bubble's `numSuccess` as the assertion, then **delete
everything** (flow, export, import, connections — connections last). This proves export
mechanics (pagination, query shape, cursor behavior) under the real flow runtime with zero
risk to QA. Note: IO native token paging works only for single-cursor responses — a response
with per-item cursors (e.g. per-entity connections) cannot be platform-paged; that's what
hook-side pagination is for.

When given **production/live-account credentials** for validation:

- Reads only — GraphQL queries / GETs; never a mutation, never a webhook registration, and
  never store the credential in a file that outlives the session (delete scripts holding it;
  pass tokens via headers, not URLs — urllib rejects inline basic-auth URLs anyway).
- Never deliberately exhaust a rate-limit bucket on production: the bucket is shared per
  app per store, so throttling it throttles the customer's real syncs. Measure the cost
  economics instead (one full-size query, read `extensions.cost` — requestedQueryCost,
  bucket size, restoreRate) and exercise the retry/backoff code **locally** by feeding it
  the documented throttled-response shape with the real numbers.
- Shrink the page size (`first: N`) instead of needing high-volume windows — 5-payout pages
  against a real store prove cursor chains (uniqueness, ordering, termination) in seconds.

### Step 8 — Create a fresh tile and finish install via API

Do **not** reuse an existing integration — create one. Full headless path (Yogi/`ai-eic`
installer + DIY Shopify), proven for `backward-auto-store3-e2e` (rest-api-ia `STORE_8`):

1. **Triple health check** (Step 1) — `POST /integrations/.../install` and every
   `.../installer/<fn>` execute on **your stack**. A dead ngrok returns HTML `404` that looks
   like a platform error.
2. **Ensure a free connector license** for the IO user behind `$TOK`:
   `GET $BASE/connectors/$CONNECTOR_ID/licenses` → need one with no `_integrationId` /
   `isInstalled:false`. If none, create via the UI license API shape (also works on `$BASE`):

   ```
   POST /api/connectors/$CONNECTOR_ID/licenses   # UI host; or $BASE/connectors/.../licenses
   {
     "_connectorId": "<CONNECTOR_ID>",
     "email": "<io-user-email>",          // top-level, not user.email
     "expires": "08/03/2027",             // MM/DD/YYYY (UI format)
     "sandbox": "false",                  // string, not boolean
     "opts": {
       "connectorEdition": "premium",
       "addonLicenses": [
         {"type":"store","licenses":[{"addOnEdition":"premium"},{"addOnEdition":"premium"},{"addOnEdition":"premium"}]},
         {"type":"addon","licenses":[{"addOnId":"payout"},{"addOnId":"payout"}]}
       ]
     }
   }
   ```

   Without a free license → `403 license_required` on install.
3. **Create the tile:**  
   `POST $BASE/integrations/$CONNECTOR_ID/install`  
   `{sandbox:false, tag:'<unique>', newTemplateInstaller:false}` → `200` with
   `integration.info.response._id`, `connection-netsuite…_id`, `connection-shopify…_id`.
   Rename/tag the integration so it is identifiable (`PUT /integrations/<id>`).
4. **NetSuite TBA** on the placeholder NS connection (test-runner `.env` via
   `CELIGO_NS_TBA_ENV_PATH`): PUT `netsuite:{account, authType:'token', tokenId, tokenSecret,
   tokenAccount, _iClientId, wsdlVersion}`, ping `{code:200}`, then
   `PUT .../installer/verifyNetSuiteConnection`.
5. **Shopify DIY `shpat_`** (prefer over browser OAuth). Tokens live in
   `rest-api-ia/env/E2E_*.env` as base64 `CONNECTIONS.SHOPIFY_STORE_{N}_TOKEN`:

   | N | store | myshopify domain |
   |---|---|---|
   | 1 | primary | `auto-qa5` |
   | 2 | secondary | `backward-auto` |
   | 3 | tertiary | `backward-auto-store3` |
   | 8 | **store3 e2e** | `backward-auto-store3-e2e` |

   PUT the installer's Shopify connection with `http.auth.type:'token'`,
   `http.auth.token:{headerName:'X-Shopify-Access-Token', location:'header', token:'<shpat_>'}`,
   `settings.storeName:'<domain>'`, and a **concrete**
   `http.baseURI:'https://<domain>.myshopify.com'` — leaving the install default
   `https://yourstorename.myshopify.com` yields Shopify `401 Invalid API key` even with a
   good token. Ping `{code:200}`, then continue installer steps.
6. **Finish install steps in order** (each
   `PUT $BASE/integrations/<id>/installer/<fn>`):
   `verifyProductConnection` → `verifyIntegratorBundleInstallation` →
   `verifyProductBundleInstallation` (slow, ~1 min) → `configureQuickStartSettings`
   (use `configurelater` formVal — same as `ai-eic` `CONFIGURE_FORMVAL`). Done when
   `storemap[0].shopInstallComplete === 'true'` / `'true'`-ish and all five `install[].completed`.

- **Shopify OAuth fallback (no `shpat_`):** `ai-eic` `POST /api/ia-tool/shopify-auth`
  (Playwright + store GUI creds + IO TOTP). Containers need Chromium + Xvfb (PRs #679/#684/#686).
- **Do not hardcode** `_httpConnectorVersionId` from old DIY snapshots → `422 invalid_ref`.
- **Verify vs create:** connection-verify can pass while `storemap` still points at a bad
  placeholder — failures then show up at resource-creation (401). Check server logs for
  `setting _connectionId as ...`.

### Step 9 — Shopify: minimum settings before the first order sync

`configurelater` leaves Order/Discount/Tax/maps empty. A fresh tile will **not** import an
order until these are saved (match rest-api-ia `updateSettings` / `REFRESH_MAP` patterns).
Details + field shapes: [reference.md §2.8](reference.md#28-shopify--minimum-settings-for-first-order-sync).

Minimum checklist:

1. **Enable** the sales-order (add) flow (`persistSettings` `{flowId, disabled:false}` — or
   direct `PUT /flows/<id>` if the slider no-ops; prefer persistSettings so storemap flags update).
2. **Location map** (General) — at least one NS→Shopify location, or a Shopify default.
3. **Discounts** (rest-api-ia style — do not skip the item):
   - Cart: `DISCOUNT` ("Discount Item") + **DIS00000**
   - Line: `NEW_LINE` + **DIS00000**
   - Selects use `yieldValueAndLabel` → persist `{id:"630", label:"DIS00000"}` (not a bare id
     string alone if the handler ignores it). Refresh metadata before picking if options are empty.
4. **Tax** — if `OVERRIDE_TAX_TOTALS`, set a **taxable** default tax code (not `-7`/`-8`).
   Also set the two checkboxes from live backends (full queries:
   [reference.md §2.8.1](reference.md#281-tax-settings--source-of-truth-netsuite--shopify)):
   - **Per-line** (`isTransactionLineLevelTaxEnabled`) = NetSuite USA “Per-Line Taxes on
     Transactions” — prove via SuiteQL that SO **item** lines carry `taxcode`
     (`taxline='F'`, recent SalesOrd). Match that boolean; do not invent from store country.
   - **Deduct GST/VAT** (`isGstVatTaxHandlingEnabled`) = Shopify `shop.taxes_included` /
     GraphQL `taxesIncluded` (and/or majority of recent `order.taxes_included`). Tax-inclusive
     → **true**; tax-exclusive → **false**. Independent of the per-line flag.
5. **SKU** — `nameinternal`; set missing-SKU fallback to an NI item on the **same NetSuite
   subsidiary** as the customer.
6. **Ship + payment static maps** — e.g. Shopify `Standard Shipping` → an NS ship method valid
   for that subsidiary. **Payment map is billing-path dependent** (see
   [reference.md §2.8.2](reference.md#282-auto-billing-gate-payment-method-required-for-cash-sale-forbidden-for-invoice)):
   - Auto-bill as **cash sale** → map gateway (e.g. `manual`) → NS Payment Method (e.g. Cash).
     `invoiceExportPreSendHook` **requires Payment Method empty** and will silently drop the SO
     if Cash is set.
   - Auto-bill as **invoice** → do **not** put a Payment Method on the SO (leave payment map
     empty / unmapped for that gateway). `cashSaleExportPreSendHook` requires Payment Method
     **set** and drops rows without it.
   Wrong-subsidiary ship methods → `invalid_key_or_ref`.
7. **Shipping as line item** — leave empty unless you have a sub-matched NI item (wrong sub →
   "Please choose an item to add").
8. **On-demand sync** — set `orderImportIds` to the Shopify order id (up to 5) and Save; the
   handler triggers the on-demand flow and clears the field. Or `POST /flows/<ondemand>/run`
   after wiring. Retry open errors via `/retry` after fixing maps.

## Review checklist (owner of an epic)

- [ ] Diffed against the true merge-base, not just the feature branch tip — smallest diffs
      (shared constants/utils) reviewed hardest; they cause cross-feature breakage.
- [ ] Every deviation from the TD/design doc is either reverted or explicitly justified in the
      PR — the TD also *defends* intentional choices a reviewer would otherwise flag.
- [ ] External-API assumptions verified live (introspection/sample query), not by inspection.
- [ ] Every path that can silently drop data (missing pagination guard, empty `pathToMany`,
      unmapped routing) either halts with an actionable error or is provably impossible.
- [ ] Verification harness re-run after fixes; PR description + QA notes updated from real
      results, not from the plan.
- [ ] Out-of-scope deliverables (migrations/update code, DB scripts, record customizations,
      documented platform limitations) listed explicitly for release planning.

## Tooling traps

- **ripgrep `-r` is `--replace`, not recursive.** `rg -rn pattern` / `rg -rln` silently rewrite
  every match in the *output* with the next token — results look like corrupted files and
  send you chasing phantom bugs. Recursion is the default; never pass `-r` unless replacing.
- The connector hijacks `console.log` into its logger (values after the label get swallowed
  in some contexts) — use `process.stdout.write` in throwaway node scripts run against
  connector code.

## Additional resources

- [reference.md](reference.md) — full command reference for every step above.
- [troubleshooting.md](troubleshooting.md) — debugging technique write-ups, cleanup checklist,
  and a failure-signature → cause quick-reference table.
