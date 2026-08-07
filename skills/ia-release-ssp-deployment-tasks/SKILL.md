---
name: ia-release-ssp-deployment-tasks
description: Create and manage Celigo DevOps SSP (Release Management) IA connector deployment_ms canary tasks for a release (e.g. IA-2026.8.1). Use when the user asks to create SSP release tasks, deployment_ms tasks, canary deployments for IA connectors, sync change_owner from DEVOPS Jira checklists, or rename SSP tasks to deployment_ms - service-name.
disable-model-invocation: false
---

# IA Release SSP Deployment Tasks

Use this skill to create (or fix) **IA connector** `deployment_ms` tasks on Celigo DevOps SSP for a release version such as `IA-2026.8.1`.

Companion skill: `ia-release-confluence-checklist` (Confluence PE checklists). Jira DEVOPS Checklist tickets usually already have **Service Tag** + **Checklist Link** filled before SSP task creation.

## Trigger phrases

- "create SSP deployment tasks for IA-2026.X.1"
- "add deployment_ms canary tasks for IA connectors"
- "sync SSP change_owner from Jira Owner"
- "rename SSP tasks to deployment_ms - service"

## Scope (IA connectors)

| Service | Typical repo |
|---|---|
| shopify-netsuite-connector | celigo/shopify-netsuite-connector |
| amazon-netsuite-connector | celigo/amazon-netsuite-connector |
| amazonmcf-netsuite-connector | celigo/amazonmcf-netsuite-connector |
| bigcommerce-netsuite-connector | celigo/bigcommerce-netsuite-connector |
| ebay-netsuite-connector | celigo/ebay-netsuite-connector |
| hightech-connectors | celigo/hightech-connectors |
| magento-netsuite-connector | celigo/magento-netsuite-connector |
| square-netsuite-ia | celigo/square-netsuite-ia |
| walmart-netsuite-connector | celigo/walmart-netsuite-connector |

Skip non-IA MS tasks unless the user asks.

## Prerequisites

1. **SSP access** — host `https://ssp.devops.integrator.io`
   - Auth is **cookie JWT**, not `cel_...` IO tokens.
   - Cookies: `refresh_token` (long-lived) + `access_token` (~15m).
   - Refresh: `POST /api/v1/auth/refresh` with `Cookie: refresh_token=<jwt>` and body `{}`; read `access_token` from `Set-Cookie`.
   - Prefer MCP `ssp-devops` if configured (`SSP_REFRESH_TOKEN` in `~/.cursor/mcp.json`). Current MCP tools are read-oriented (`ssp_get_release_version`, `ssp_list_release_tasks`, `ssp_get_release_task`); **create/patch/status** usually need raw HTTP with the same cookie auth.
2. **Atlassian MCP** — Jira Owner + Service Tag from DEVOPS Checklist tickets.
   - Celigo cloudId: `76584c60-1daa-4b79-9004-2dc7ead76c05`
3. Confirm with the user before creating if release status, deployment method, or approval is unclear.

## Guardrails

- **Do not approve** tasks unless the user explicitly asks. Default status: `draft`.
- Prefer **`deployment_method: "canary"`** for IA connector releases (not `rolling_update`) unless the user specifies otherwise.
- **Never commit** `SSP_REFRESH_TOKEN`, `access_token`, or other secrets.
- Create URL **requires trailing slash**: `POST /api/v1/rms/version/{VERSION}/tasks/` (without `/` → 307).
- PATCH with `fields` may **regenerate** the long auto-name (`deployment_ms - service, https://github.com/...`). After any fields PATCH, restore the short name with a **name-only** PATCH.
- Delete only after cancel: `PATCH .../tasks/{id}/status` → `cancelled`, then DELETE if needed.
- Avoid duplicate tasks for the same service in one release — list first and skip/cancel extras.

## Workflow

### 1. Resolve release + existing tasks

```http
GET /api/v1/rms/version/{VERSION}
GET /api/v1/rms/version/{VERSION}/tasks/
```

Example version: `IA-2026.8.1`. Dashboard:

`https://ssp.devops.integrator.io/release/management/dashboard/{VERSION}/tasks`

### 2. Resolve owners + tags from Jira

Filter pattern (Owner = Swat and Tilak):

```text
project = DEVOPS AND issuetype = Checklist AND fixVersion = <YYYY.M.N>
AND "Owner[User Picker (single user)]" IN (<swatAccountId>, <tilakAccountId>)
```

Known Owner field: `customfield_13910`.

| Person | Email (SSP `change_owner`) | accountId (example) |
|---|---|---|
| Swatantra Rout | `swatantra.rout@celigo.com` | `557058:ccae41cc-114e-4623-99f2-4c2bbc6568ec` |
| Tilak Tirumalanagaram | `tilak.tirumalanagaram@celigo.com` | `712020:197ef354-a5be-40fd-9d86-36cf04e190ef` |

Also read:

| Jira field | Purpose |
|---|---|
| `customfield_15063` | Service Tag (GitHub release URL) |
| `customfield_15065` | Checklist Link (Confluence) |
| summary | Service name (`Checklist for <service>`) |

**Map each SSP task's `change_owner` to that ticket's Owner email** — do not assign everyone to Swat.

### 3. Create each `deployment_ms` task

```http
POST /api/v1/rms/version/{VERSION}/tasks/
Content-Type: application/json
Cookie: access_token=...; refresh_token=...
```

Canonical body (canary):

```json
{
  "task_template_key": "deployment_ms",
  "category": "deployment",
  "fields": {
    "change_owner": "<owner@celigo.com from Jira>",
    "service_name": "<service>",
    "service_tag": "https://github.com/celigo/<service>/releases/tag/<tag>",
    "deployment_method": "canary",
    "update_all_deployments": true,
    "canary_at_top": true,
    "place_before_deployment": {
      "values": {
        "staging": "app",
        "production-eu": "app",
        "production-na": "app"
      }
    },
    "promote_all_deployments": true,
    "canary_version_same_as_ui": false,
    "canary_header": "canary-new-deployment",
    "canary_version": "true",
    "execute_on": {
      "values": {
        "staging": true,
        "production-eu": true,
        "production-na": true
      }
    }
  }
}
```

Notes:

- `service_tag` must be the full GitHub release URL (bare tag like `ml-1.x.y.z.0` fails validation on PATCH).
- On create, SSP often sets `name` to the long form including the URL.

### 4. Rename to short form

```http
PATCH /api/v1/rms/version/{VERSION}/tasks/{taskId}
{"name": "deployment_ms - <service_name>"}
```

**Name-only** PATCH works. Including `fields` in the same PATCH can overwrite the name back to the long form.

Target display name example: `deployment_ms - amazon-netsuite-connector`.

### 5. Fix owner / fields if needed

When changing `change_owner` or other fields:

1. `GET` the task; copy full `fields`.
2. `PATCH` with `{"fields": { ...full required set..., "change_owner": "..." }}`.
3. Immediately name-only PATCH to restore `deployment_ms - <service>`.

Partial `fields` objects often 422.

### 6. Status transitions

```http
PATCH /api/v1/rms/version/{VERSION}/tasks/{taskId}/status
{"status": "draft"|"approved"|"cancelled"}
```

Default leave **`draft`**. Approve only on explicit user request.

### 7. Report to user

Return a table:

| Service | Tag | change_owner | Task id | Status | Name |

Include dashboard URL. Confirm no duplicates and that names are short-form.

## Auth helper (Python sketch)

```python
import json, re, urllib.request, ssl

BASE = "https://ssp.devops.integrator.io"
REFRESH = "<from env / mcp.json SSP_REFRESH_TOKEN>"  # never commit
ctx = ssl.create_default_context()

def refresh_access():
    req = urllib.request.Request(
        BASE + "/api/v1/auth/refresh",
        data=b"{}",
        method="POST",
        headers={
            "Accept": "application/json",
            "Content-Type": "application/json",
            "Cookie": f"refresh_token={REFRESH}",
        },
    )
    with urllib.request.urlopen(req, context=ctx, timeout=20) as r:
        sc = r.headers.get_all("Set-Cookie") or [r.headers.get("Set-Cookie")]
    return re.search(r"access_token=([^;]+)", " ".join(s or "" for s in sc)).group(1)
```

## Example invoke

```text
For IA-2026.8.1, create SSP deployment_ms canary tasks for all 9 IA connectors.
Use Service Tags from DEVOPS Checklist Jira (filter 30282).
Set change_owner from each ticket's Owner (Swat vs Tilak).
Rename to "deployment_ms - <service>". Leave draft — do not approve.
```

## Related IDs / links

- SSP: `https://ssp.devops.integrator.io`
- Example prior release to copy shape: `IA-2026.7.1` shopify canary tasks
- Jira Owner field: `customfield_13910`
- Jira Service Tag: `customfield_15063`
- Jira Checklist Link: `customfield_15065`
