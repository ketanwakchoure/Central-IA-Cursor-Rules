# IA Dev Workflow — Debugging Techniques & Troubleshooting

Supplement to [SKILL.md](SKILL.md).

## Debugging techniques

### Connection debug logs — see the actual wire traffic

The most decisive tool available: captures full request/response bodies (including RESTlet
`_json` payloads and the hooks' own debug lines) for everything crossing a connection.

```bash
# arm 60 min of capture - PATCH uses JSON-Patch format; 204 = success
curl -s -X PATCH -H "Authorization: $TOK" -H "Content-Type: application/json" \
  -d '[{"op":"add","path":"/debugDate","value":"<UTC now+60m ISO>"}]' \
  "$BASE/connections/<CONN_ID>"
# run the flow, then:
curl -s -H "Authorization: $TOK" "$BASE/connections/<CONN_ID>/debug" -o /tmp/conn_debug.log
```

Entries split on `^\d{4}-\d{2}-\d{2}T` timestamps, one per resource invocation. `debugDate`
expires by itself. Use this whenever data "disappears between bubbles" — it tells you exactly
what the backend returned versus what the platform propagated. This is how a variance-data
propagation gap was root-caused in a real epic: the RESTlet response carried the data
correctly, but the platform never forwarded it to the next bubble because of how one-to-many
response mapping placement works (see below).

### Backend governance timeouts (e.g. `sss_time_limit_exceeded`)

Diagnosis pattern:
1. Identical timestamps across all failed records → one batched invocation blew the execution
   window (not per-record).
2. Quantify the expensive operation — e.g. `SELECT COUNT(*)` of a search's candidate set. An
   unindexed custom-field filter over 100k+ rows is a scan per record.
3. Apply the product's designed mitigation (date-window settings, batch sizes) and re-measure.
4. Remember downstream constraints for fixtures: matching records must fall inside whatever
   window you configured, post to the expected account, and be in the expected state.

### Testing scale limits without scale data

Constants that gate splitting/batching (chunk sizes, page sizes) can be tested by temporarily
deploying a lowered value (platform script or bundle — see reference.md §2.4/§4), running the
flow against small data, asserting the split behavior and per-part money/record totals, then
restoring the backup. Watch for second-order effects (more parts per invocation → the
governance ceiling above).

### Platform behaviors that look like your bug but aren't

- **One-to-many imports**: response mappings write onto each *child* object
  (`<pathToMany>[i].field`), never the parent record; `pathToMany` cannot read nested arrays.
  A downstream bubble consuming those values needs a `postResponseMap` hook on the import to
  hoist child values to the parent. Known platform bug: partial child failure + retry wipes
  previously-succeeded children's response mappings.
- **Settings readers**: generic settings-read helpers often copy only `field.value` for
  additionalFields matches — widget fields carrying `map`/`entities` must be read by walking
  `settings.sections` directly.
- **In-memory hook caches** keyed by resource id survive across runs but not restarts, and new
  resource ids (reinstall) get fresh entries — initialize per-key, not per-cache-object, or a
  long-lived server serving a new resource id silently never rotates/updates.

### Seeding flow-eligible test data (store → backend pipeline)

Driving a record through the *product's own flows* beats hand-crafting backend records — a
hand-made record almost never satisfies the export search's criteria (see reference.md § 3.5
for reading those criteria). Lessons that generalize:

- Storefront orders must be **backend-valid** or the order import errors record-by-record:
  real variant/SKU that exists as a backend item, a customer that already exists in the
  backend (or carries first/last name — OneWorld accounts also need a subsidiary, so
  pre-create the customer via REST), a ship method whose title exactly matches a backend
  ship item (`SELECT itemid FROM shipitem`), and a location on line items where required.
- Iterate on the flow's **per-record errors** — each run peels one validation layer
  (customer → ship method → location). Fix data, `retry` the failed records (reference.md
  § 2.2) instead of re-exporting (delta windows move).
- Getting a record into the exportable state usually needs the product's *other* flows plus
  targeted backend writes: e.g. billing eligibility = sales order **fulfilled**
  (`POST /salesOrder/<id>/!transform/itemFulfillment` with line locations) **and invoiced**
  (auto-billing flow) — status `Billed`.
- **Auto-bill cash sale vs invoice is gated on SO Payment Method** (search column
  `Payment Method` in `AutoBillingExport.validateData`): cash sale export keeps only rows
  **with** a Payment Method; invoice export keeps only rows **without** one. Mapping
  `manual`→Cash on order import will make invoice auto-bill return `ok:0` with no errors.
  Prove with SuiteQL `paymentmethod` on the SO — see reference.md §2.8.2.
- Error scenarios are cheapest built by **patching identifiers on a real eligible record**
  (point an etail order id at a deleted/cancelled storefront order) rather than fabricating
  whole records; reset once-flags (`custbody..._exp=false`) to re-drive the same record.
- Shopify dev stores rate-limit order creation (~5/min) and injected authorizations need an
  `authorization` code (`53433` for bogus gateway) or downstream captures fail oddly.

## Cleanup checklist

Live experiments write real records; a dirty sandbox mis-diagnoses later runs (consumed
records cause "invalid sublist operation" errors; stale records show amounts from older
fixture versions).

- [ ] Delete in reference order (dependent/audit records → transactions → master records).
- [ ] Only delete master/reference records when the fixtures that created them changed —
      otherwise reuse-by-lookup (`ignoreExisting`) keeps them consistent across reruns.
- [ ] Enumerate before deleting (SuiteQL), delete individually, then re-verify counts are 0.
- [ ] Restore any temporarily modified deployed artifact (script records, bundle files,
      settings) from the backups you took — end every session in the state a fresh run expects.

## Failure signature → cause

| Symptom | Cause / fix |
|---|---|
| First bubble `invalid_extension_response` with ngrok HTML body | tunnel or server down; stack hostURI stale → reference.md §1 |
| persistSettings 200 but value unchanged | `pending` not shopId-keyed, or connector unreachable → reference.md §2.3 |
| `entry point("fn") is not a function` (flow script hook) | function missing from deployed platform script record → reference.md §2.4 |
| `invalid hook function "fn"` (NetSuite import) | function missing from deployed bundle closure → reference.md §4 |
| PATCH/PUT on flow/import 422 `field_locked_by_integration_app` | IA-locked; reinstall pattern (dev) or update code (prod) → reference.md §2.5/§2.6 |
| Backend script timeout on batched import | governance window exceeded; measure candidate sets, apply window/batch settings → above |
| Record created with zeroed/empty mapped fields | hook received wrong-shaped input (wrapper leaked, settings not readable) — check with connection debug logs |
| "invalid sublist operation" adding to a selection sublist | referenced record already consumed (stale artifacts) or wrong records matched |
| Bubble shows ok:0 err:0 ign:0 | zero records reached it — empty pathToMany / response mapping written onto children → above |
| SuiteQL `429 CONCURRENCY_LIMIT_EXCEEDED` | backend concurrency governance — back off and retry |
| Proxy GET of a record times out | you touched a selection-type sublist in a large account → reference.md §3.2 |
| Change deployed but behavior unchanged | stale compile cache (bundle) or you edited the repo copy of a deployed artifact → reference.md §2.4/§4 |
| Flow run returns 422 `invalid_flow` | flow disabled — enable via persistSettings `{flowId, disabled:false}` → reference.md §2.1 |
| Export `ok:0` though eligible-looking data exists | (a) delta window already passed the records' create time → reference.md §2.1; (b) search criteria differ from assumptions — run the search standalone / dump its definition → reference.md §3.5; (c) fresh-install search filters out of sync — re-save the driving setting → reference.md §2.3; (d) **auto-bill:** SO has Payment Method but you ran **invoice** flow (or lacks it but you ran **cash sale**) → silently filtered in `*ExportPreSendHook` → reference.md §2.8.2 |
| Invoice auto-bill `ok:0` after IF; SO Pending Billing | Check (1) Billing status filter is `SalesOrd:F` (not `B`) when capture is after fulfillment; (2) SO `paymentmethod` is **empty** — Cash/`1` from payment map routes to cash-sale flow only → reference.md §2.8.2 |
| Hook says a field is missing that the mapping extracts fine | grouped RESTlet records: hook got an ARRAY of rows, unwrap `record[0]` → reference.md §3.5 |
| `GET /jobs/<id>/joberrors` 404 | errors-2.0 tile — use `GET /flows/<fid>/<resourceId>/errors` (+ `/retry`) → reference.md §2.2 |
| persistSettings 422 "enable X flow and retry" | settings handler enforces a cross-flow dependency — enable the dependency flow first → reference.md §2.3 |
| Storefront order import errors per record (customer/ship method/location) | order data not backend-valid — seed per the checklist above |
