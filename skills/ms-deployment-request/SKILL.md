---
name: ms-deployment-request
description: Submit a microservice deployment request via the Jenkins MS_DEPLOYMENT_REQUEST job for IAQA, QA, QA-PROD, STAGING, PLATFORM1-5 or COREDEV. Use when the user asks to deploy a connector or microservice, bump a tag in an environment, fill the MS deployment form, raise a deployment request, or mentions jenkins.aut.staging.integrator.io.
disable-model-invocation: false
---

# MS deployment request

Job: `https://jenkins.aut.staging.integrator.io/job/MS_DEPLOYMENT_REQUEST/`

Deployments are consequential. Gather every answer below, show the resolved payload, and get an
explicit go-ahead before triggering.

## Prerequisites

An MCP server or credentials for the **`jenkins.aut.staging.integrator.io`** controller. A token
for `jenkins.qa.staging.integrator.io` will **not** work here — Jenkins API tokens are per-user
and per-controller, and that controller does not host this job.

Auth is HTTP Basic with `base64(<jenkins-user-id>:<api-token>)`. The user id is visible at
`/me/configure` on that host and is often a service account rather than an email address.

Never hardcode the token in this skill, in a workspace file, or in a commit. Read it from the
environment or an MCP config at runtime:

```bash
B64=$(printf '%s' "$JENKINS_AUT_USER:$JENKINS_AUT_TOKEN" | base64)
```

## Required questions

Ask all of these before submitting. Use `AskQuestion` with the known choices where possible.

1. **Which environment?** One of `IAQA`, `QA`, `QA-PROD`, `STAGING`, `PLATFORM1`–`PLATFORM5`,
   `COREDEV`. No default — never guess.
2. **Which service(s) and tag(s)?** Format `service:tag`, comma-separated for multiple. Confirm
   the tag exists as a GitHub release and resolve "latest" explicitly rather than assuming.
3. **Which JIRA tracker?** Full URL, not the bare key. If several apply (dev story vs bug),
   ask which one.
4. **Canary?** One of: none, ADD, REMOVE, or a canary tag update. Default is none — leave all
   three canary fields blank.
5. **Requester email?** A Celigo address; mandatory or the job fails.
6. **Confirm the delta.** Show which commits ship between the currently deployed tag and the new
   one, then confirm that is intended.

## Parameters

| Parameter | Notes |
| --- | --- |
| `JIRA_TRACKER` | Full URL, e.g. `https://celigo.atlassian.net/browse/PRE-27643` |
| `ENV` | Exact choice string, uppercase |
| `MS_TAG` | `service:tag` — e.g. `walmart-netsuite-connector:ml-1.0.0.58.0` |
| `MS_TAG_CANARY` | Canary only. Blank for a plain deploy |
| `CANARY_ACTION` | Blank, `ADD`, or `REMOVE` |
| `CANARY_HEADERS` | YAML snippet, canary only |
| `EMAIL` | Requester's Celigo email |

IA connectors use `ml-*` tags for plain deployments and `<release>-fb-*` tags for feature
branches. IA and IO use different canary headers, so never copy an IO canary snippet.

## Workflow

**1. Resolve the tag and the delta.**

```bash
gh api repos/celigo/<repo>/releases --jq '.[0:5] | .[] | "\(.tag_name)\t\(.published_at[:10])"'
rg -o "tag: .*" deployments/<env>/ia/<repo>/microservice.yaml   # currently deployed
gh api repos/celigo/<repo>/compare/<deployed>...<new> \
  --jq '.commits[] | "  \(.sha[0:8])  \(.commit.message | split("\n")[0])"'
```

Confirm the new tag's commit is on `master` and contains the intended change.

**2. Check past builds for convention** before filling anything unusual.

```bash
curl -s -H "Authorization: Basic $B64" \
 'https://jenkins.aut.staging.integrator.io/job/MS_DEPLOYMENT_REQUEST/api/json?tree=builds%5Bnumber,result,actions%5Bparameters%5Bname,value%5D%5D%7B0,20%7D'
```

**3. Present the payload as a table and get explicit approval.**

**4. Submit.**

```bash
curl -s -D - -o /dev/null -X POST -H "Authorization: Basic $B64" \
  --data-urlencode 'JIRA_TRACKER=https://celigo.atlassian.net/browse/<KEY>' \
  --data-urlencode 'ENV=<ENV>' \
  --data-urlencode 'MS_TAG=<service>:<tag>' \
  --data-urlencode 'MS_TAG_CANARY=' \
  --data-urlencode 'CANARY_ACTION=' \
  --data-urlencode 'CANARY_HEADERS=' \
  --data-urlencode 'EMAIL=<user>@celigo.com' \
  'https://jenkins.aut.staging.integrator.io/job/MS_DEPLOYMENT_REQUEST/buildWithParameters'
```

Expect `201` plus a `Location:` queue-item URL.

**5. Verify.** Resolve the queue item to a build number, then read back the parameters Jenkins
actually recorded — do not report success on the `201` alone.

```bash
curl -s -H "Authorization: Basic $B64" 'https://jenkins.aut.staging.integrator.io/queue/item/<id>/api/json?tree=why,executable%5Bnumber,url%5D'
curl -s -H "Authorization: Basic $B64" 'https://jenkins.aut.staging.integrator.io/job/MS_DEPLOYMENT_REQUEST/<n>/api/json?tree=number,building,result,actions%5Bparameters%5Bname,value%5D%5D'
```

## Output

Report the build number and URL, the parameters Jenkins recorded, and the commits that ship in
the new tag. If the build fails, fetch the console log and report the failing stage.

## Gotchas

- **Encode brackets** in `tree=` query strings (`%5B` / `%5D`) or Jenkins returns HTML and JSON
  parsing fails.
- **401 vs 403**: 403 means no credentials reached Jenkins; 401 means the credentials were
  rejected — usually a wrong user id, not a wrong token.
- Builds may be attributed to a shared service account. `EMAIL` is what identifies the requester,
  so it must be correct.
- The job usually raises a CD pull request for DevOps to review and merge rather than deploying
  directly. Tell the user to watch for that PR.
- Deploying during release week can collide with the release schedule — check the current
  IAQA/staging/PST timeline before deploying to a shared environment.
