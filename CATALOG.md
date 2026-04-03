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

