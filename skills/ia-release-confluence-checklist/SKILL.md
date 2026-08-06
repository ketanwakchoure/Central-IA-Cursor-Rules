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

- **Do not invent Critical/High = 0.**
  - npm audit: use end-of-log dashboard curl fields `auditCritical` / `auditHigh` only.
  - Container Qualys: console usually does **not** print severity totals. Gate SUCCESS ≠ documented count of 0. Prefer reading Qualys report / `qualys_images_summary.json` when available; otherwise say "unverifiable" and link the report.
- Jenkins HTML publisher paths (`/Audit_20Report/`, `/qualys_report_for_*.html/`) often need VPN/login. Prefer citing **console log** evidence for metrics when HTML is inaccessible.
- S3 presigned report zips expire (~36h). Do not treat expired presigns as the durable link.
- Preserve intentional N/A automation comments (ebay/square/hightech) when marking QA WIP.
- Uncheck **all** DevOps "Accepted" boxes including **OVERALL DEVOPS SIGN-OFF** when preparing a new release page (do not leave May/prior release Accepted state).
- Prefer `contentFormat: "html"` for `updateConfluencePage` so task-list checkboxes round-trip. Markdown often escapes checkbox HTML.

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
3. From console (`searchBuildLog`), extract:
   - Release tag: `ml-*.*.*.N.0` (docker tag / GitHub releases create)
   - Container Qualys short hash: `qualys_scan_target:<12hex>` → report path `.../<N>/qualys_report_for_<12hex>.html/`
   - Dashboard metrics JSON near end of log:
     - `statementsCoverage`, `auditCritical`, `auditHigh`, `sonarDuplicatedLines`, `sonarBugs`, `sonarCodeSmells`, `sonarVulnerabilities`, `sonarSecurityHotspots`
4. GitHub release URL: `https://github.com/celigo/<service>/releases/tag/<tag>`

### 3. Resolve base image Qualys scan

1. Read service `Dockerfile` `FROM public.ecr.aws/...` (prefer **build log** `FROM` over stale local clones if they disagree).
2. Common IA image (as of 2026.8): `public.ecr.aws/c4g3p9t9/node-bookworm-slim:22.11.0-10.9.0`
3. Find latest SUCCESS build on `SECURITY/SCANS/BASE_IMAGE_SCAN/base-image-scan` whose `displayName` matches the image (e.g. `node-bookworm-slim_22.11.0-10.9.0_#8035`).
4. From that build log, get published report name:
   - Newer: `Qualys_20Report_20For_20<12hex>/`
   - Older: `qualys_report_for_<12hex>.html/`
5. Also capture SEV-4 / SEV-5 counts if logged (`No vulnerabilities found`, policy check lines).

### 4. Update page content

Rewrite the checklist table (HTML) with:

| Row | Scrum status | DevOps Accepted | Comments |
|---|---|---|---|
| Base Images | Completed Successfully | unchecked | image name + latest base-image-scan Qualys URL |
| Container Scan | Critical/High from Qualys if known; else keep text but do not fake zeros | unchecked | POST-COMMIT Qualys URL for build N |
| npm audit | `Critical = X, High = Y` from dashboard | unchecked | Audit report URL **and/or** console deep-link note |
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

Re-fetch HTML and confirm:

- Release tag / Jenkins build N present
- Base scan URL is not a prior-release leftover (e.g. `#6571` from May)
- No `checked> Accepted` remains under DevOps column
- QA Functional has WIP checked
- Magento (and any other non-zero audit) shows accurate High/Critical counts

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
