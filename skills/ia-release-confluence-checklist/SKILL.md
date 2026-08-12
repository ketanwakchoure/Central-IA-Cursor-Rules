---
name: ia-release-confluence-checklist
description: Prepare/update Celigo IA connector Confluence production-ready checklists for a release (e.g. 2026.8.1). Use when the user asks to update IA release checklists, Confluence PE checklist pages, master tag/Jenkins links, base image Qualys scan, QA WIP, or DevOps sign-off for shopify/amazon/walmart/etc connectors.
disable-model-invocation: false
---

# IA Release Confluence Checklist

Use this skill to refresh Celigo **IA connector** production-ready checklist pages in Confluence for a given release (example: `2026.8.1`).

## Trigger phrases

- "update IA release checklist"
- "prepare Confluence checklist for 2026.X.1"
- "pick latest master tag and Jenkins link for IA connectors"
- "mark QA WIP / uncheck DevOps sign-off on release checklists"

## Scope (IA connectors only)

Default set under PE space (parent folder may vary by release):

| Service | Jenkins job |
|---|---|
| shopify-netsuite-connector | `IA/POST-COMMIT/shopify-netsuite-connector` |
| amazon-netsuite-connector | `IA/POST-COMMIT/amazon-netsuite-connector` |
| amazonmcf-netsuite-connector | `IA/POST-COMMIT/amazonmcf-netsuite-connector` |
| bigcommerce-netsuite-connector | `IA/POST-COMMIT/bigcommerce-netsuite-connector` |
| ebay-netsuite-connector | `IA/POST-COMMIT/ebay-netsuite-connector` |
| hightech-connectors | `IA/POST-COMMIT/hightech-connectors` |
| magento-netsuite-connector | `IA/POST-COMMIT/magento-netsuite-connector` |
| square-netsuite-ia | `IA/POST-COMMIT/square-netsuite-ia` |
| walmart-netsuite-connector | `IA/POST-COMMIT/walmart-netsuite-connector` |

Skip non-IA pages (file-adaptor, MS checklists, IO overview) unless the user asks.

## Prerequisites (MCPs / tools)

1. **Atlassian MCP** (`user-Atlassian-MCP-Server`)
   - `searchConfluenceUsingCql`, `getConfluencePage`, `updateConfluencePage`
   - Celigo cloudId (known working): `76584c60-1daa-4b79-9004-2dc7ead76c05`
   - Always `GetMcpTools` before calling
2. **Jenkins QA MCP** (`user-jenkins-qa`)
   - `getBuild`, `getJob`, `searchBuildLog`
3. Optional: local clone under `/Users/<you>/projects/<service>` for `Dockerfile` `FROM` line

## Guardrails

- **Links only. No prose.** Comments cells hold the image name and bare URLs, nothing else. Do
  not add explanatory sentences, scan dates, severity summaries, or ticket references — no other
  IA checklist has them. The only non-link text in the table is the existing
  `Jenkins:` / `Release tag:` / `Test Cycle:` / `Test Report:` labels. **Open a sibling
  connector's page for the same release and match it before writing.**
- Keep the Scrum status cells to the gated numbers only (`Critical = 0, High = 0`). Do not append
  moderate/low counts.
- **Do not invent Critical/High = 0.**
  - npm audit: use end-of-log dashboard curl fields `auditCritical` / `auditHigh` only.
  - Container Qualys: console does **not** print severity totals. Gate SUCCESS ≠ a documented 0.
    Leave the existing status cell untouched and **report the gap to the user** — do not write a
    caveat onto the page, it breaks house style.
- **Ignore intermediate `npm audit` console lines** such as
  `79 vulnerabilities (3 low, 67 moderate, 7 high, 2 critical)`. Those are dev-inclusive runs from
  an earlier stage, not the gate. Only the dashboard JSON counts.
- Jenkins HTML publisher paths (`/Audit_20Report/`, `/qualys_report_for_*.html/`) need session
  login; they return **404 under API/Basic auth even when valid**. Never treat a 404 as proof the
  report is missing — reuse the established URL pattern with the new build number.
- S3 presigned report zips expire (~36h). Do not treat expired presigns as the durable link.
- Preserve intentional N/A automation comments (ebay/square/hightech) when marking QA WIP.
- Uncheck **all** DevOps "Accepted" boxes including **OVERALL DEVOPS SIGN-OFF** when preparing a
  new release page (do not leave a prior release's Accepted state).
- Keep a Test Cycle link that belongs to **this** release; only clear cycles from earlier releases.
- Prefer `contentFormat: "html"` for `updateConfluencePage` so task-list checkboxes round-trip.
  Markdown often escapes checkbox HTML. Preserve every `data-local-id` attribute — apply targeted
  string replacements to the fetched HTML rather than rewriting the table.

## Workflow

### 1. Discover pages

```text
CQL: space = PE AND title ~ "<RELEASE>" AND type = page ORDER BY title ASC
Example: space = PE AND title ~ "2026.8.1" AND type = page
```

Filter to the IA connector titles above. Confirm each page with `getConfluencePage` (markdown first for quick scan, html before rewrite).

### 2. Resolve latest master tag + Jenkins build

For each service:

1. `getBuild` on `IA/POST-COMMIT/<service>` (omit buildNumber → last build).
2. Require `result == SUCCESS` and `displayName` like `master_#N`.
3. One `searchBuildLog` call gets almost everything — the dashboard payload is a single line:

```text
pattern: auditCritical|statementsCoverage|sonarBugs|qualys_scan_target
useRegex: true, contextLines: 2
```

   That one line carries `statementsCoverage`, `auditCritical`, `auditHigh`, `auditModerate`,
   `auditLow`, `sonarBugs`, `sonarVulnerabilities`, `sonarSecurityHotspots`, `sonarCodeSmells`,
   `sonarDuplicatedLines`, plus `prNumber` — use `prNumber` to confirm the build is the change you
   expect. The `qualys_scan_target:<12hex>` match gives the container report path
   `.../<N>/qualys_report_for_<12hex>.html/`.
4. GitHub release URL: `https://github.com/celigo/<service>/releases/tag/<tag>`

### 3. Resolve base image Qualys scan

1. Read service `Dockerfile` `FROM public.ecr.aws/...` (prefer **build log** `FROM` over stale local clones if they disagree).
2. Common IA image (as of 2026.8): `public.ecr.aws/c4g3p9t9/node-bookworm-slim:22.11.0-10.9.0`
3. `base-image-scan` cycles through many images, so its **last build is almost never yours**.
   List builds with `getJob tree: builds[number,displayName,result,timestamp]{0,120}` and pick the
   newest SUCCESS whose `displayName` matches the image.
4. The `<12hex>` in the report name is the **image id**, visible in the scan log's
   `docker inspect`/digest line and in the connector build's `docker image ls` output.
   - Newer: `Qualys_20Report_20For_20<12hex>/`
   - Older: `qualys_report_for_<12hex>.html/`
5. This scan is **shared by every IA connector on the same base image** — one refreshed scan
   number applies to all their pages. Checklists routinely carry a stale one from a prior release.

### 4. Update page content

Rewrite the checklist table (HTML) with:

| Row | Scrum status | DevOps Accepted | Comments (links only) |
|---|---|---|---|
| Base Images | Completed Successfully | unchecked | image name + latest base-image-scan Qualys URL |
| Container Scan | leave as-is; do not fake zeros | unchecked | POST-COMMIT Qualys URL for build N |
| npm audit | `Critical = X, High = Y` from dashboard | unchecked | Audit report URL for build N |
| CI Code Coverage | `statementsCoverage`% | unchecked | Combined coverage URL for build N |
| SonarQube | bugs/vulns/hotspots/smells/dup from dashboard | unchecked | Sonar dashboard link |
| Communication | Not applicable (checked) | unchecked | leave empty |
| Resiliency | **WIP** | unchecked | clear prior NA/Completed |
| QA Functional Sign off | **WIP** | unchecked | Jenkins master_#N + Release tag + Test Cycle/Report = WIP (clear prior release cycles) |
| 100% Automation | **WIP**, unless historically N/A with reason (ebay/square/hightech) | unchecked | keep N/A comment if applicable |
| Endurance Testing | **WIP** | unchecked | |
| OVERALL DEVOPS SIGN-OFF | — | unchecked | |

Version message example:

```text
Update to latest master tag <tag> / Jenkins #<N>; QA WIP; uncheck DevOps; fix base image scan
```

### 5. Verify after write

Re-fetch and confirm:

- Release tag / Jenkins build N present, and **no stale build number survives** anywhere
- Base scan URL is not a prior-release leftover
- No `checked> Accepted` remains under DevOps column
- QA Functional has WIP checked
- Magento (and any other non-zero audit) shows accurate High/Critical counts
- No prose crept into a Comments cell

## Jenkins API gotchas

- URL-encode brackets in `tree=` (`%5B` / `%5D`) or Jenkins returns HTML and JSON parsing fails.
- The MCP `searchBuildLog` parameter is `pattern` (with `useRegex`), not `searchPattern`.
- `htmlpublisher` report actions do not appear in `api/json`, so the report URL cannot be
  discovered programmatically — derive it from the hash in the console log.

### 6. Report to user

Return a table:

| Connector | Tag | Jenkins | npm Crit/High | Qualys Crit/High | Page URL |

Be explicit about what was verified vs linked-only.

## Evidence cheat-sheet

| Claim | Where to verify |
|---|---|
| npm Critical/High | Console: dashboard curl JSON `auditCritical` / `auditHigh` |
| Coverage % | Same dashboard JSON `statementsCoverage` |
| Master tag | Console: `docker ...:<tag>` or GitHub releases create |
| Container Qualys hash | Console: `qualys_scan_target:<hash>` |
| Base image SEV | Base-image-scan console: SEV-4/SEV-5 / "No vulnerabilities found" |
| HTML Audit Report | Jenkins publisher `/Audit_20Report/` (auth) or S3 `npm-audit.zip` (short-lived) |

## Example invoke

```text
Update all IA 2026.8.1 Confluence checklists: latest master tag + Jenkins,
fix base image scan, mark QA WIP, uncheck DevOps sign-off.
Verify npm Critical/High from dashboard metrics; don't fake Qualys zeros.
```

## Known Celigo IDs

- Confluence cloudId: `76584c60-1daa-4b79-9004-2dc7ead76c05`
- Space key: `PE` (Product Engineering)
- Jenkins base: `https://jenkins.qa.staging.integrator.io`
- Sonar base: `https://sonarqube.qa.staging.integrator.io/dashboard?id=<service>`
