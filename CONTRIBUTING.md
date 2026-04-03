# Contributing

Thank you for contributing to the shared Cursor rules library. This guide covers how to add, modify, and propose rules, skills, and agents.

## Quick Start

### Propose a new rule

```bash
# From your workspace -- just the filename works
cursor-rules propose my-rule.mdc --category workflows

# Or full path
cursor-rules propose .cursor/rules/my-rule.mdc --category workflows
```

### Propose a new skill

```bash
cursor-rules propose .cursor/skills/deploy/SKILL.md
```

### Propose a new agent

```bash
cursor-rules propose .cursor/agents/code-reviewer.md
```

### Edit an existing item

```bash
# Edit a symlinked rule in your workspace, then:
cursor-rules propose no-secret-commit "Fix env var reference"

# Short name or full ID both work
cursor-rules propose safety/no-secret-commit "Fix env var reference"
```

Type is auto-detected from the file extension: `.mdc` = rule, `SKILL.md` = skill, `.md` = agent.

---

## Writing a Rule

### 1. Start from the template

```bash
cp ~/.cursor-rules-library/templates/rule.mdc.template .cursor/rules/my-rule.mdc
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
| `description` | Yes | One-line summary. Shows up in `cursor-rules list` and `CATALOG.md`. |
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

## Rule Categories

| Category | Purpose |
|----------|---------|
| `workflows` | Development workflow rules (PR review, build, test, deploy) |
| `coding-standards` | Language and framework conventions |
| `safety` | Guardrails: anti-hallucination, security, no-placeholder |
| `integrations` | Tool-specific rules (MCP, Jira, GitHub) |

Create a new category if none of the above fit. The `propose` command will let you pick an existing category or create a new one interactively.

---

## Writing a Skill

Skills live in `skills/<skill-name>/SKILL.md`. Start from the template:

```bash
cp ~/.cursor-rules-library/templates/skill.md.template .cursor/skills/my-skill/SKILL.md
```

### Skill frontmatter

```yaml
---
name: deploy-checklist
description: Guide the deployment process for production releases
disable-model-invocation: false
---
```

| Field | Required | Description |
|-------|----------|-------------|
| `name` | Yes | Kebab-case identifier for the skill. |
| `description` | Yes | The agent reads this to decide whether to load the skill. Make it clear and specific. |
| `disable-model-invocation` | No | If `true`, skill only activates when explicitly invoked (not auto-detected). |

### Rules vs Skills

- **Rules** are passive constraints -- they load automatically based on `alwaysApply` or `globs` and tell the agent what to do or not do. Cursor-specific (`.mdc` format).
- **Skills** are active workflows -- the agent decides whether to load them based on the `description`. They can include supporting files. Open standard (`SKILL.md` works in Cursor, Claude Code, Copilot, etc.).

Use rules for coding standards and guardrails. Use skills for multi-step workflows and conditional processes.

---

## Writing an Agent

Agents live in `agents/<agent-name>.md`. They define custom subagent configurations.

---

## Validation

Before submitting, validate your rule:

```bash
cursor-rules validate
```

This checks:
- Valid YAML frontmatter (opens with `---`, closes with `---`)
- `description` field present and non-empty
- Non-empty body (at least 10 characters)
- Kebab-case filenames (warns on uppercase or underscores)

## Proposing via CLI

The `propose` command handles the full contribution flow:

1. Validates the file (frontmatter, body length)
2. Auto-detects type from file extension
3. Prompts for category (rules only, if `--category` not given)
4. Copies to the library clone
5. Creates a branch, commits, pushes
6. Opens a PR (or prints a manual PR link)

```bash
# New rule (prompts for category)
cursor-rules propose my-rule.mdc

# New rule with category
cursor-rules propose my-rule.mdc --category safety

# New skill (auto-detected from SKILL.md filename)
cursor-rules propose .cursor/skills/deploy/SKILL.md

# Edit existing (by short name or full ID)
cursor-rules propose no-placeholder "Clarify TODO handling"
```

Filenames are resolved from `.cursor/rules/`, `.cursor/skills/`, and `.cursor/agents/` automatically -- you don't need to type the full path.

## Manual PR Process

If you prefer not to use the CLI:

1. Fork or branch from `main`
2. Add your item to the appropriate directory
3. Run `cursor-rules validate` to check
4. Run `./scripts/generate-catalog.sh .` to update the catalog
5. Commit and open a PR

### PR checklist

- [ ] File has valid frontmatter with `description`
- [ ] Filename uses kebab-case
- [ ] Placed in the correct directory (`rules/<category>/`, `skills/<name>/`, or `agents/`)
- [ ] `cursor-rules validate` passes
- [ ] `CATALOG.md` regenerated if adding a new item

## Updating Profiles

If your new rule/skill/agent should be included in a default profile (e.g., `default.json`, `backend.json`), update the relevant profile file in `profiles/` and include the change in your PR.

Profile format:

```json
{
  "description": "Short description of this profile",
  "rules": ["category/rule-name"],
  "skills": ["skill-name"],
  "agents": ["agent-name"]
}
```
