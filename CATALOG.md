# Catalog

Auto-generated index of all shared rules, skills, and agents.

> Regenerate with: `./scripts/generate-catalog.sh`

## Rules

### safety

- **no-placeholder** -- Never leave incomplete code with TODO comments or placeholder implementations
- **no-secret-commit** -- Never commit secrets, credentials, API keys, or tokens to version control
- **verify-packages** -- Verify package and module existence before importing -- never assume based on training data
### workflows

- **build-workflow** -- Build workflow for legacy SuiteScript products - never directly edit build output files
- **pr-review** -- Review, validate, fix, run and comment on auto-generated test case PRs. Trigger by saying "Review PR" with a PR link and Zephyr test case key.
- **test-runner** -- How to run the NetSuite CLI test runner (ns-test) for legacy SuiteScript tests, including closure rebuild, sync.js fixes, and common failure patterns.

## Skills

### ia-dev-workflow

- **ia-dev-workflow** -- Develop, debug, deploy, and live-verify Celigo Integration App (IA) flows against integrator.io staging plus a backend (NetSuite, Shopify, etc.). Covers local connector server + ngrok bring-up, running/polling flows via the integrator.io API, saving IA settings (persistSettings), editing platform script records, applying installer-config changes via add-on reinstall, inspecting backend records (SuiteQL / REST proxy), rebuilding and deploying SuiteScript bundles, diagnosing governance timeouts and silent data loss, and building a live verification harness. Use when developing or debugging any IA epic on staging, or when the user mentions "run the flow", "check NetSuite records", "SuiteQL", "ngrok"/"tunnel", "persistSettings", "reinstall the add-on", "platform script", "rebuild the closure/bundle", "script execution time exceeded", "invalid hook function", or asks to verify a flow end-to-end.
### ia-release-confluence-checklist

- **ia-release-confluence-checklist** -- Prepare/update Celigo IA connector Confluence production-ready checklists for a release (e.g. 2026.8.1). Use when the user asks to update IA release checklists, Confluence PE checklist pages, master tag/Jenkins links, base image Qualys scan, QA WIP, or DevOps sign-off for shopify/amazon/walmart/etc connectors.
### ms-deployment-request

- **ms-deployment-request** -- Submit a microservice deployment request via the Jenkins MS_DEPLOYMENT_REQUEST job for IAQA, QA, QA-PROD, STAGING, PLATFORM1-5 or COREDEV. Use when the user asks to deploy a connector or microservice, bump a tag in an environment, fill the MS deployment form, raise a deployment request, or mentions jenkins.aut.staging.integrator.io.
### rest-api-ia-zephyr-pr-review

- **rest-api-ia-zephyr-pr-review** -- Review celigo/rest-api-ia Shopify-NetSuite IA testcase PRs against Zephyr Scale requirements, connector settings, item fixtures, payload format, and expected-response validation. Use when the user asks to review rest-api-ia PRs, AI generated testcases, E2E Native Exchanges, Zephyr testcase IDs like PRE-T24669, or Shopify-NetSuite IA settings.

