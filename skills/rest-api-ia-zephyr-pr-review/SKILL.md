---
name: rest-api-ia-zephyr-pr-review
description: Review celigo/rest-api-ia Shopify-NetSuite IA testcase PRs against Zephyr Scale requirements, connector settings, item fixtures, payload format, and expected-response validation. Use when the user asks to review rest-api-ia PRs, AI generated testcases, E2E Native Exchanges, Zephyr testcase IDs like PRE-T24669, or Shopify-NetSuite IA settings.
---

# rest-api-ia Zephyr PR Review

Use this skill for reviewing `celigo/rest-api-ia` PRs that add or update Shopify-NetSuite IA JSON testcases.

## Guardrails

- Do not post GitHub comments, approve, or request changes unless the user explicitly asks.
- Prefer `gh` CLI for PR metadata, changed files, diffs, checks, and reviews.
- Before calling Zephyr MCP tools, read the tool descriptors for `getTestCase` and `getTestCaseTestSteps`.
- Treat testcase names as Zephyr keys using `PRE-<filename>`, for example `T24669.json` -> `PRE-T24669`.
- Review only active files referenced by the testcase JSON first. Then separately flag orphaned payload/response files if the user asks for unused file review.
- If the user asks to post comments, use inline comments on changed lines and the requested review event (`COMMENT`, `REQUEST_CHANGES`, or `APPROVE`).

## Quick Workflow

1. Fetch PR context:
   - `gh pr view <n> --repo celigo/rest-api-ia --json title,body,files,commits,headRefOid,headRefName,baseRefName,mergeStateStatus`
   - `gh pr diff <n> --repo celigo/rest-api-ia --name-only`
   - `gh pr checks <n> --repo celigo/rest-api-ia`
2. Identify testcase files under `testcases/**/<ID>.json`.
3. Fetch Zephyr:
   - `getTestCase({ "testCaseKey": "PRE-<ID>" })`
   - `getTestCaseTestSteps({ "testCaseKey": "PRE-<ID>", "maxResults": 200, "startAt": 0 })`
4. Read the testcase JSON and every referenced payload/response file.
5. Run the Format Checker (see below) against the `T24668.json` reference, then compare settings, item type, flow direction, validation coverage, and expected-response fields.
6. Return findings grouped by PR/testcase. Include suggested Slack/PR-comment wording when useful.

## Format Checker (Reference: T24668.json)

Use `rest-api-ia/testcases/E2E_Native_Exchanges/T24668.json` as the canonical format reference.
Most testcases follow this exact shape, with the same functions/methods used in setup and
validation. When reviewing a PR, compare the testcase JSON structure against this reference and
flag deviations. Read the reference file when in doubt instead of guessing.

### Top-level structure

```jsonc
{
  "testData": [
    {
      "suite": "<ID> | Verify E2E with ...",        // human-readable scenario
      "suite_title": "<same as suite>",              // usually identical to suite
      "storeName": "store8",                          // store-level default (see Store / Tax Mode Checks)
      "interactions": [ /* one object per flow step */ ]
    }
  ]
}
```

- `testData` must be an array with exactly one suite object (unless the PR documents otherwise).
- `suite` and `suite_title` should be present and start with the testcase ID (`T<ID> | ...`).
- `storeName` must match the tax mode convention (`store8` = tax-inclusive, `store7` = tax-exclusive).
- Flag missing `suite`, `suite_title`, `storeName`, or `interactions` keys.

### Interaction shape

Each entry in `interactions` follows this shape:

```jsonc
{
  "test": "T<ID><InteractionName>",            // e.g. T24668OrderImport
  "test_title": "test1T<ID><InteractionName>",  // e.g. test1T24668OrderImport
  "pre_request": [ /* setup requests, in order */ ],
  "request": { "method": "POST", "path": "..." },  // the asserting call
  "response": { /* validation block */ }
}
```

- `test` should be `T<ID>` + a PascalCase interaction name; `test_title` should be `test1` + `test`.
- Every interaction must have a `request` and a `response`.
- `pre_request` is an array of `{ "request": {...} }` (and optionally `{ "request": {...}, "response": {...} }`) objects, ordered as the flow executes.

### Standard pre_request pattern

The reference uses this repeatable sequence inside `pre_request` for most interactions:

1. **Resolve integration** (first interaction only):
   `GET /integrations` with `"filterKey": "name : Shopify - NetSuite"` and `"store_T<ID>integrationID": "_id"`.
2. **Resolve flow id**:
   `GET /flows` with `"filterKey": "name : <exact flow name>"`, `"storeName"`, `"store_T<ID>flowId<n>": "_id"`, and `"getFlowsByIntegrationId": true`.
3. **Set flow status**:
   `PUT /integrations/{{T<ID>integrationID}}/settings/persistSettings` with `"settingsMethod": "updateflowStatusThroughAPI"` and a `_flowStatusJSON.json` payload.
4. **Apply settings** (0..n):
   `PUT .../persistSettings` with `"settingsMethod": "updateSettings"` and an `_updateSettingsN.json` payload.
5. **Create data** (when needed):
   `POST /connections/process.env[CONNECTIONS.<X>]/import` (or `/export`) with a `dataCreationMethod` and a payload.
6. **Run / trigger flow**:
   `POST /flows/{{T<ID>flowId<n>}}/run`, OR for Shopify-triggered imports the data-creation call itself triggers it.
7. **Poll flow job**:
   `GET /flows/{{T<ID>flowId<n>}}/jobs/latest` with `"waitUntil": "completed"`, `"maxWait": 6`, and a `_flow_responseN.json` body with `"partialValidation": true`.

Flag interactions that skip the flow-status set, skip the job poll, or run a flow without first resolving its id.

### Interaction sequence (E2E order of operations)

E2E Native Exchange testcases run their `interactions` in a fixed business order. Each interaction
is one flow step: create/trigger data, run the flow, poll the job, then assert the record. Use this
to check that a PR's interactions are present and ordered correctly.

**Canonical E2E Native Exchange — Downsell variant** (reference: `T24693.json`, `T24671.json`,
`T24708.json`, `T24710.json`). 8 interactions in this order:

1. `OrderImport` — Shopify order → NetSuite sales order.
   - flow: `Sync Shopify order on-demand to NetSuite (add)`
   - setup: `adjustNSInventory` (stock), then `createSHPFDraftOrderthoughAPI` (`uniqueValue: PAID`)
   - assert: `validateSalesOrderWithDiscountItem` (GST scenarios use `verifyGSTSalesOrderDataFromNetSuite`)
2. `FulfillmentExport` — NetSuite fulfillment → Shopify fulfillment.
   - flow: `NetSuite fulfillment to Shopify fulfillment (add)`
   - setup: `createFulfillment`; assert: `verifyShopifyFulfillment`
3. `VerifyAutobilling` — NetSuite sales order → NetSuite invoice.
   - flow: `NetSuite sales order to NetSuite invoice (add)`
   - setup: `createNScustomerPayment`; assert: `validateInvoiceWithDiscountItem` (GST: `verifyInvoiceDataFromNetSuite`)
4. `CreateReturnWithDownsell` — create the Shopify return with a downsell (lower-priced exchange).
   - setup: `createReturn` (`uniqueValue: OPEN`); assert: `verifyShopifyReturn`
5. `ReturnImport` — Shopify return → NetSuite return authorization.
   - flow: `Shopify returns to NetSuite return authorization`
   - assert: `verifyReturnAuthorization` (captures `store_T<ID>returnAuthorizationId`)
6. `ItemReceiptAndRefund` — receive the RA, process the Shopify return, and import the refund.
   - flows: `NetSuite received RA to Shopify return process` + `Shopify refund to NetSuite refund (add)`
   - setup: `createItemReceipt`
   - inner asserts: `verifyShopifyReturn`, `validateCreditMemoWithDiscountItem`
   - final assert: `verifyCustRefundDataFromNetsuite`
7. `ExchangeOrderImport` — the downsell/exchange order → NetSuite sales order.
   - flow: `Shopify order to NetSuite order (cash sale or sales order)`
   - setup: `createShipmentforSHPFOrder`; assert: `validateSalesOrderWithDiscountItem` (GST variant as in step 1)
8. `ExchangeFulfillmentImport` — Shopify fulfillment of the exchange → NetSuite fulfillment.
   - flow: `Shopify fulfillment to NetSuite fulfillment (add)`
   - assert: `verifyFulfillmentImportDataFromNetsuite`

**Non-downsell Native Exchange variant** (reference: `T24668.json`) keeps the same business spine
but splits/renames a few interactions: `OrderImport` → `FulfillmentExport` → `AutoBilling` →
`ReturnImport` → `ItemReceiptAndReturnProcess` → `RefundImport` (asserts credit memo + customer
refund) → `SyncExchangeOrder` → `FulfillExchangeOrder`.

Sequence findings to raise:

- Order creation not first, or fulfillment/auto-billing happening before the order is imported.
- Return steps appearing before fulfillment/auto-billing.
- Exchange order/fulfillment steps appearing before the return + refund are processed.
- A downsell test missing the `CreateReturnWithDownsell` interaction (or the downsell exchange order).
- Missing the final `ExchangeFulfillmentImport`/`FulfillExchangeOrder` assertion.
- Interaction names that don't follow `T<ID><Step>` PascalCase (breaks the readable sequence).

### Known method vocabulary

Validation methods (`dataValidationMethod`) seen in the reference — prefer these over ad-hoc names:

- `validateSalesOrderWithDiscountItem` — sales order / exchange order assertion
- `verifyGSTSalesOrderDataFromNetSuite` — sales order assertion for GST scenarios
- `validateInvoiceWithDiscountItem` — invoice (auto-billing)
- `verifyInvoiceDataFromNetSuite` — invoice assertion for GST scenarios
- `validateCreditMemoWithDiscountItem` — credit memo
- `verifyReturnAuthorization` — NetSuite return authorization
- `verifyCustRefundDataFromNetsuite` — customer refund
- `verifyFulfillmentImportDataFromNetsuite` — NetSuite fulfillment (exchange fulfill)
- `verifyShopifyFulfillment` — Shopify fulfillment export
- `verifyShopifyReturn` — Shopify return process export

Data creation methods (`dataCreationMethod`):

- `createSHPFDraftOrderthoughAPI` (with `"uniqueValue": "PAID"`)
- `adjustNSInventory` (stock setup before order import)
- `createFulfillment`, `createItemReceipt` (NetSuite imports)
- `createNScustomerPayment` (customer payment before auto-billing)
- `createReturn` (Shopify import, with `"uniqueValue": "OPEN"`)
- `createShipmentforSHPFOrder` (Shopify fulfillment for exchange order)

Settings methods (`settingsMethod`): `updateflowStatusThroughAPI`, `updateSettings`.

If a PR introduces a validation/creation/settings method name not in this list, flag it and ask
whether the framework actually implements it (common AI-generated hallucination).

### Response / validation block format

```jsonc
"response": {
  "status": 200,
  "time": 10000,
  "dataValidationMethod": "<known method>",
  "body": "/test-data/E2E_Native_Exchanges/responses/T<ID>/T<ID><Interaction>_expectedResponseN.json",
  "uniqueValue": "{{T<ID>shopifyOrderId}}",   // or composite like {{...}}-{{...}}
  "dontStopExecutionOnFailure": true
}
```

- The final asserting `request` for NetSuite record validations is `POST /connections/process.env[CONNECTIONS.NETSUITE]/proxy`.
- Flow-poll responses use `"partialValidation": true` + a `_flow_response` body; real-record responses use a `dataValidationMethod` + an `_expectedResponse` body.
- `uniqueValue` should reference a captured variable (e.g. `{{T<ID>shopifyOrderId}}`); exchange-related interactions often use composite keys (`{{...orderId}}-{{...returnId}}`).
- Optional keys seen in the reference: `secondaryValue`, `lookupBy`, `store_T<ID><name>` (to capture an id from the response such as `internalId`).

### Path & env conventions

- Connections: `process.env[CONNECTIONS.SHOPIFY_STORE_8]` (tax-inclusive) / `..._STORE_7` (tax-exclusive) / `CONNECTIONS.NETSUITE`.
- Payload/response paths: `/test-data/E2E_Native_Exchanges/payloads/T<ID>/...` and `/test-data/E2E_Native_Exchanges/responses/T<ID>/...`.
- File naming: `T<ID><Interaction>_<purpose>.json` where purpose is one of
  `flowStatusJSON`, `updateSettingsN`, `createOrder` / `create<Thing>`, `flow_responseN`, `expectedResponseN`.
- Variable templating uses `{{T<ID><name>}}` and capture uses `"store_T<ID><name>": "<jsonField>"`.

### Format-check findings to raise

- Missing `suite`/`suite_title`/`storeName`/`test`/`test_title`/`request`/`response` keys.
- `test_title` not equal to `test1` + `test`, or `test` not prefixed with the testcase ID.
- `storeName` / `CONNECTIONS.SHOPIFY_STORE_*` mismatched with the tax mode.
- Unknown `dataValidationMethod`, `dataCreationMethod`, or `settingsMethod` (possible hallucination).
- Payload/response path that doesn't follow the `/test-data/E2E_Native_Exchanges/{payloads,responses}/T<ID>/...` convention or whose file is missing.
- Flow run without a preceding flow-id resolve + `updateflowStatusThroughAPI`.
- Real-record validation interaction that only polls `/jobs/latest` and never asserts via a `dataValidationMethod` (see Validation Checks).
- `uniqueValue` that is a literal instead of a captured `{{...}}` variable.

## Correct Settings Mapping

Use this mapping when comparing Zephyr human wording to `*_updateSettings*.json` payloads.

| Zephyr wording | Expected payload setting |
|---|---|
| Add Tax against line item | `"Sync sales tax to NetSuite as": "Add total tax against a single line item on the order"` plus `"NetSuite item to track Shopify order taxes as a line item"` |
| Per-line taxes enabled | `"Per-line taxes on transaction enabled in NetSuite": true` |
| Per-line taxes disabled | `"Per-line taxes on transaction enabled in NetSuite": false` |
| Cart Discount as Separate Line Item | `"Sync Shopify cart level discounts to NetSuite as": "Discount Item (recommended)"` plus discount item |
| Cart Discount as Coupon Code/PromoCode | `"Sync Shopify cart level discounts to NetSuite as": "Coupon Code"` or proven promo option |
| Line Level / As Line Level | `"Sync Shopify line-level discounts to NetSuite as": "New line below the original line (recommended)"` |
| Adjustment line / As Adjustment Line | `"Sync Shopify line-level discounts to NetSuite as": "Adjustments to item list price"` |
| Shipping as line | `"NetSuite item to track Shopify shipping cost as a line item": "Ship001"` or equivalent shipping item |
| Shipping on body | omit shipping item or use a known body-shipping pattern, not a line-item setting |
| Native exchanges as separate SO/CS | `"Sync native exchanges as separate sales orders or cash sales": true` or `"true"` |

## Native Exchange Required Settings (E2E)

For E2E Native Exchange testcases, confirm these settings appear in the relevant `updateSettings`
payloads with valid (non-`"Please select"`) values. Exact key wording matters — flag typos or
hallucinated variants. Settings observed across `T24693`, `T24708`, `T24710`.

### OrderImport / ExchangeOrderImport settings

- `"Sync native exchanges as separate sales orders or cash sales": "true"` (or `true`) — required for native exchange tests.
- `"NetSuite item to track exchange credit as a line item": "automation variance item"` — must be present with a valid item.
- `"Auto-assign inventory detail for NetSuite items": true` — REQUIRED for lot and serialized item testcases (so NetSuite auto-assigns the seeded lot/serial numbers). Flag if missing on a lot/serial test.

These two must be applied **before the exchange order is synced** — i.e. they belong in the
`ExchangeOrderImport_updateSettings` (NOT necessarily the initial OrderImport settings). Only flag
them if they are missing from the exchange-order settings; do NOT flag their absence from the initial
OrderImport settings:

- `"Sync Shopify edited order data to NetSuite": true` — the "sync edited sales order" setting; must be enabled in the ExchangeOrderImport settings.
- `"Sync POS orders into NetSuite as sales orders": true` — must be present/enabled in the ExchangeOrderImport settings.

### ReturnImport settings (exchange adjustments / credit)

In the ReturnImport `updateSettings` (e.g. `T24693ReturnImport_updateSettings1.json`):

- `"NetSuite item to track exchange adjustments"` — must be present with a valid item (e.g. `"Pay001"`).
- `"NetSuite item to track exchange credit as a line item": "automation variance item"` — present with a valid item.
- `"NetSuite item to track exchange fees as a line item"` — present with a valid item when the scenario uses exchange fees.

### Refund settings (RefundImport)

In the refund settings (e.g. `T24693RefundImport_updateSettings1.json` / `*RefundImport_updateSettings1.json`):

- `"NetSuite item to track order refund adjustments as a line item": "automation refund line item"` — present for refund scenarios.
- `"Substitute item for kit, lot numbered, and serialized items"` — must be present with a valid item (e.g. `"automation refund line item"`) whenever the testcase contains a **kit, lot numbered, or serialized item**. A value of `"Please select"` means it is NOT set — flag it for lot/serial/kit tests.

### Exchange order fulfillment prerequisite

In the `ExchangeOrderImport` interaction, the Shopify-side fulfillment of the exchange order must be
created BEFORE the exchange order flow is run. Concretely, the `pre_request` must perform
`createShipmentforSHPFOrder` (Shopify `/import`) before the `POST /flows/{{...exchangeFlowId}}/run`.
Flag exchange order imports that run the flow without first fulfilling the order in Shopify.

## Item Fixture Checks

Read `env/dev.env` (repo root) and compare `DEFAULTS.PRODUCTS.<n>.CLASS` with the Zephyr item type:

- Normal item -> `INVENTORY`
- Lot item -> `LOT NUMBERED INVENTORY`
- Serialized item -> `SERIALIZED INVENTORY`
- Kit item scenarios must use the testcase's established kit/product references, not normal inventory items unless the test intentionally maps kits differently.

If the PR references new env entries not present locally, do not assume mismatch. Report that the local env is missing the entry and ask the owner to confirm it resolves and has the correct class.

## Lot / Serialized Item Handling (Reference: T24693 lot, T24708 serialized)

Lot- and serial-tracked E2E testcases must seed NetSuite stock before the order import and carry
the lot/serial numbers through every NetSuite record payload (fulfillment, item receipt, and the
exchange leg). Reviewers should confirm both the **inventory adjustment** and the **payload
mentions** are present and consistent.

### 1. Inventory adjustment (runs in `pre_request` before order creation)

A `POST /connections/process.env[CONNECTIONS.NETSUITE]/import` with `"dataCreationMethod": "adjustNSInventory"`
seeds stock. The payload shape:

```jsonc
{
  "subsidiary": "3",
  "account": "process.env[NS_DEFAULT.NETSUITE_ACCOUNT_FOR_ALL_PURPOSES]",
  "inventory": [
    { "quantity": "2", "item": "process.env[DEFAULTS.PRODUCTS.<n>.SKU]", "location": "process.env[NS_DEFAULT.LOCATION1]" }
  ],
  "inventoryDetail": [ /* one entry per lot OR per serial unit */ ]
}
```

**Lot items** (e.g. `T24693OrderImport_adjustLotInventory.json`) — ONE `inventoryDetail` entry whose
`assignQuantity` equals the full ordered quantity:

```jsonc
"inventoryDetail": [
  { "inventoryNumber": "LOTT24693", "assignQuantity": 2, "expirationDate": "10/30/2026" }
]
```

**Serialized items** (e.g. `T24708OrderImport_adjustSerializedInventory.json`) — ONE entry PER unit,
each with `"assignQuantity": 1` and a unique `inventoryNumber` (optionally `binnumber`):

```jsonc
"inventoryDetail": [
  { "inventoryNumber": "SER-{{T24708shopifyOrderId}}-001", "assignQuantity": 1, "expirationDate": "12/31/2027", "binnumber": "BIN001" },
  { "inventoryNumber": "SER-{{T24708shopifyOrderId}}-002", "assignQuantity": 1, "expirationDate": "12/31/2027", "binnumber": "BIN002" }
]
```

The exchange/downsell leg seeds its own stock with a second `adjustNSInventory` in the
`ExchangeOrderImport` pre_request (often a different product SKU and an `EXC-...` numbering prefix).

### 2. Mentioning lot/serial numbers in record payloads

The same lot/serial numbers must be referenced in the NetSuite record-creation payloads via an
`inventory_detail` array. Note the key is `serialnumber` even for **lot** numbers:

- **Fulfillment** (`createFulfillment`, e.g. `T24693FulfillmentImport_createOrderViaAPI_payload1.json`):

```jsonc
"line_items": [
  { "itemname": "process.env[DEFAULTS.PRODUCTS.6.SKU]", "location": "...", "quantity": "2",
    "inventory_detail": [ { "serialnumber": "LOTT24693", "qty": "2" } ] }
]
```

- **Item receipt** (`createItemReceipt`, e.g. `T24693ItemReceiptAndRefund_createItemReceipt.json`):

```jsonc
"items": [
  { "line": "1", "itemreceive": "true", "location": "Location1",
    "inventory_detail": [ { "serialnumber": "LOTT24693", "qty": "2" } ] }
]
```

For serialized items, `inventory_detail` lists one `serialnumber` per unit with `"qty": "1"` each,
matching the unique serials seeded in step 1.

### Lot / serial findings to raise

- Item type in Zephyr is Lot/Serialized but there is no `adjustNSInventory` step before order import.
- Lot test uses multiple `inventoryDetail` entries (should be one entry with full `assignQuantity`),
  or serialized test uses one entry with `assignQuantity > 1` (should be one entry per unit, qty 1).
- Lot/serial numbers seeded in the adjustment don't match the `serialnumber` values referenced in the
  fulfillment / item-receipt payloads.
- `assignQuantity` / `qty` totals don't match the ordered quantity.
- Exchange/downsell leg of a serialized test missing its own `adjustNSInventory` stock seed.
- Product SKU index points at a non-lot/non-serial class in `dev.env` (cross-check Item Fixture Checks).

## Store / Tax Mode Checks

Apply this project convention when reviewing Shopify-NetSuite E2E testcase PRs:

- Tax-exclusive scenarios should use `store7` and `CONNECTIONS.SHOPIFY_STORE_7`.
- Tax-inclusive scenarios should use `store8` and `CONNECTIONS.SHOPIFY_STORE_8`.
- If the PR uses another store for one of these tax modes, flag it as a configuration mismatch unless the PR explicitly documents a validated exception.

## Validation Checks

For each testcase:

- Confirm all referenced payload/response paths exist.
- Confirm all added payload/response files are either referenced or intentionally unused.
- Confirm flow direction matches Zephyr:
  - "Fulfill in Shopify, then run fulfillment import" usually means `Shopify fulfillment to NetSuite fulfillment (add)` with `createShipmentforSHPFOrder`.
  - Some passing Native Exchange cases intentionally use NetSuite fulfillment export. If so, ask for confirmation rather than marking as a hard failure.
- Confirm final interaction validation method. Exchange fulfillment imports usually use `verifyFulfillmentImportDataFromNetsuite` through NetSuite proxy when asserting NetSuite fulfillment.
- Prefer real record validations over only `/jobs/latest` flow checks when Zephyr expects invoice, refund, exchange order, or fulfillment record validation.
- For OrderImport expected responses, check for all four eTail variance fields:
  - `eTail Order Total Variance`
  - `eTail Discount Total Variance`
  - `eTail Tax Total Variance`
  - `eTail Ship Total Variance`
- Check the expected response asserts the scenario's core behavior: item line, cart discount, line discount, shipping line/body, tax substitute/tax handling, store, currency, and relevant totals.
- For lot/serialized tests, check whether lot/serial numbers are asserted where the framework supports it, not only created in setup payloads.

## Common Findings

- PR title advertises one testcase but the diff adds multiple testcase IDs.
- `AI_Generated_testcases` folder remains for Native Exchange E2E tests that should live under `E2E_Native_Exchanges` or `E2E_Native_Exchanges_BodyLevel`.
- Line discount mode is inverted. Remember: `Line Level` -> `New line below...`; `Adjustment line` -> `Adjustments to item list price`.
- `Coupon Code / Promo Code` is suspicious unless proven valid; existing payloads commonly use `Coupon Code`.
- Expected response file exists but testcase only validates flow job status.
- Exchange shipment payload exists but is never wired before exchange fulfillment.
- Return quantity in payload differs from Zephyr expected return quantity.
- OrderImport expected response has only one variance field instead of all four.

## Suggested Output

Use this concise format:

```markdown
## PR #<n> / <testcase>
What matches:
- ...

Concerns:
1. **Severity: finding title.** File: `<path>`. Why it matters. Suggested ping/comment: `...`
2. ...

Commenting recommendation:
- No comments needed / Add inline comments on ... / Request changes for ...
```

When the user asks to post comments, summarize what will be posted, then use `gh api repos/celigo/rest-api-ia/pulls/<n>/reviews` with inline comments on changed lines.
