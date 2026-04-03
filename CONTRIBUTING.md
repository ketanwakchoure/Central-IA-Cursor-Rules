# Contributing

Thank you for contributing to the shared Cursor rules library. This guide covers how to add, modify, and propose rules.

## Quick Start

The fastest way to contribute a rule from your workspace:

```bash
cursor-rules propose .cursor/rules/my-rule.mdc --category workflows
```

This validates the file, creates a branch, and opens a PR automatically.

## Writing a Rule

### 1. Start from the template

Copy `templates/rule.mdc.template` and fill in your content:

```bash
cp templates/rule.mdc.template rules/<category>/my-rule.mdc
```

### 2. Frontmatter (required)

Every `.mdc` file must start with YAML frontmatter:

```yaml
---
description: One-line summary of what the rule does
globs: src/**/*.ts, src/**/*.js
alwaysApply: false
---
```

| Field | Required | Description |
|-------|----------|-------------|
| `description` | Yes | One-line summary. Shows up in `cli.sh list` and `CATALOG.md`. |
| `globs` | No | Comma-separated file patterns. Rule activates only when matching files are in context. |
| `alwaysApply` | No | If `true`, rule is always active regardless of context. Default: `false`. |

### 3. Body content

Write clear, actionable instructions for the AI agent. Good rules are:

- **Specific** -- tell the agent exactly what to do and what not to do
- **Concise** -- avoid unnecessary prose; agents read every token
- **Example-driven** -- show good/bad code examples when the rule is nuanced

### 4. Naming conventions

- **Filenames**: `kebab-case.mdc` (e.g., `pr-review.mdc`, not `PR_Review.mdc`)
- **Categories**: lowercase, kebab-case directories under `rules/`
- **Descriptions**: start with a verb or noun, no trailing period

## Categories

| Category | Purpose |
|----------|---------|
| `workflows` | Development workflow rules (PR review, build, test, deploy) |
| `coding-standards` | Language and framework conventions |
| `safety` | Guardrails: anti-hallucination, security, no-placeholder |
| `integrations` | Tool-specific rules (MCP, Jira, GitHub) |

Create a new category if none of the above fit. Use kebab-case.

## Writing a Skill

Skills live in `skills/<skill-name>/SKILL.md`. Start from `templates/skill.md.template`.

Skills differ from rules:

- Rules are **passive** -- they constrain how the agent behaves
- Skills are **active** -- they define a multi-step workflow the agent executes on demand

## Validation

Before submitting, validate your rule:

```bash
./scripts/validate.sh .
```

This checks:
- Valid YAML frontmatter
- `description` field present
- Non-empty body (at least 10 characters)
- Kebab-case filenames

## PR Process

1. Fork or branch from `main`
2. Add your rule to the appropriate category
3. Run `./scripts/validate.sh .` to check
4. Run `./scripts/generate-catalog.sh .` to update the catalog
5. Commit and open a PR

Or use the CLI shortcut:

```bash
cursor-rules propose .cursor/rules/my-rule.mdc --category workflows
```

### PR checklist

- [ ] Rule has valid frontmatter with `description`
- [ ] Filename uses kebab-case
- [ ] Placed in the correct category directory
- [ ] `./scripts/validate.sh` passes
- [ ] `CATALOG.md` regenerated if adding a new rule

## Updating Profiles

If your new rule should be included in a default profile (e.g., `default.json`, `backend.json`), update the relevant profile file in `profiles/` and include the change in your PR.
