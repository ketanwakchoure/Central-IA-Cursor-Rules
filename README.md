# Central-IA-Cursor-Rules

A shared library of Cursor IDE rules, skills, and agents. Clone once, symlink everywhere -- keep your team's AI coding standards consistent across all workspaces.

## The Problem

Each project workspace ends up with its own copy of Cursor rules (`.mdc` files), skills, and agent configs. Rules get duplicated and drift across repos. There is no single source of truth.

## How It Works

```
Central Repo (GitHub)
        |
        |  cli.sh install (git clone)
        v
~/.cursor-rules-library/        <-- one clone per dev machine
        |
        |  cli.sh sync (symlinks)
        v
your-project/.cursor/rules/     <-- symlinks to library files
```

1. The library is cloned once to `~/.cursor-rules-library/`
2. Each workspace has a `.cursor-rules.json` that lists which rules to use
3. `cli.sh sync` creates symlinks from `.cursor/rules/` to the library
4. Local (non-symlinked) rules are preserved untouched

## Quick Start

### 1. Install the library

```bash
# Clone to ~/.cursor-rules-library/
git clone https://github.com/ketanwakchoure/Central-IA-Cursor-Rules.git ~/.cursor-rules-library

# Or use the CLI:
~/.cursor-rules-library/cli.sh install
```

### 2. Add an alias (optional but recommended)

```bash
# Add to ~/.zshrc or ~/.bashrc
alias cursor-rules='~/.cursor-rules-library/cli.sh'
```

### 3. Configure a workspace

Create `.cursor-rules.json` in your project root:

```json
{
  "library": "~/.cursor-rules-library",
  "profile": "default",
  "rules": [
    "workflows/pr-review"
  ],
  "skills": [],
  "agents": []
}
```

### 4. Sync

```bash
cursor-rules sync
```

This creates symlinks in `.cursor/rules/` pointing to the library.

### 5. Stay updated

```bash
cursor-rules update
```

Pulls the latest rules and re-syncs.

## CLI Reference

| Command | Description |
|---------|-------------|
| `install [repo-url]` | Clone the shared library to `~/.cursor-rules-library` |
| `sync` | Symlink rules from library into current workspace based on `.cursor-rules.json` |
| `update` | Pull latest library changes and re-sync |
| `list [--category <cat>]` | List all available rules, skills, and agents |
| `add <rule-id>` | Add a rule to `.cursor-rules.json` and symlink it |
| `remove <rule-id>` | Remove a rule from `.cursor-rules.json` and delete its symlink |
| `propose <file> [--category <cat>]` | Contribute a local rule to the shared library via PR |
| `validate` | Lint all library rules for valid frontmatter |
| `doctor` | Check installation health and symlink integrity |
| `help` | Show help message |

### Examples

```bash
# See what's available
cursor-rules list

# Add a specific rule
cursor-rules add safety/no-placeholder

# Check everything is healthy
cursor-rules doctor

# Contribute a rule you wrote
cursor-rules propose .cursor/rules/my-rule.mdc --category workflows
```

## Config Format: `.cursor-rules.json`

```json
{
  "library": "~/.cursor-rules-library",
  "profile": "backend",
  "rules": [
    "workflows/pr-review",
    "safety/no-placeholder"
  ],
  "skills": [],
  "agents": []
}
```

| Field | Required | Description |
|-------|----------|-------------|
| `library` | No | Path to the library clone. Default: `~/.cursor-rules-library` |
| `profile` | No | Named profile from `profiles/`. Loads a pre-defined set of rules as a base. |
| `rules` | No | Additional rule IDs to include (merged with profile). Format: `category/name` |
| `skills` | No | Skill IDs to include. |
| `agents` | No | Agent IDs to include. |

When both `profile` and explicit `rules` are present, they are merged (deduplicated).

This file **should be committed** to your repo so the team shares the same rule selection.

## Profiles

Profiles are pre-defined bundles of rules for common roles. They live in `profiles/`.

| Profile | Description |
|---------|-------------|
| `default` | Safety rules that should always be active |
| `backend` | Safety + workflow rules for backend/API development |
| `frontend` | Safety + PR review rules for frontend development |
| `full-stack` | All available rules |

Use a profile by setting `"profile": "backend"` in your `.cursor-rules.json`.

## Available Rules

See [CATALOG.md](CATALOG.md) for the full list, or run:

```bash
cursor-rules list
```

### Categories

| Category | Purpose |
|----------|---------|
| `workflows` | Development workflow rules (PR review, build, test) |
| `coding-standards` | Language and framework conventions |
| `safety` | Guardrails: anti-hallucination, security, no-placeholder |
| `integrations` | Tool-specific rules (MCP, Jira, GitHub) |

## .gitignore Strategy

Symlinked rules should not be tracked by the workspace repo. Add to your workspace `.gitignore`:

```gitignore
# Shared cursor rules are symlinks managed by cursor-rules CLI
# .cursor-rules.json IS tracked (it's the team config)
.cursor/rules/*.mdc
!.cursor/rules/local-*.mdc
```

Alternatively, prefix local rules with `local-` to keep them tracked while ignoring library symlinks.

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) for details on adding rules, naming conventions, and the PR process.

### Quick contribute

```bash
cursor-rules propose .cursor/rules/my-rule.mdc --category workflows
```

This validates the file, creates a branch, commits, pushes, and opens a PR.

## Prerequisites

- **git** -- for cloning and updating the library
- **jq** -- for parsing `.cursor-rules.json` (`brew install jq` on macOS)
- **gh** (optional) -- GitHub CLI, only needed for `propose` command (`brew install gh`)

## Repository Structure

```
Central-IA-Cursor-Rules/
├── README.md
├── CONTRIBUTING.md
├── CATALOG.md
├── cli.sh
├── .cursor-rules.json.example
├── templates/
│   ├── rule.mdc.template
│   └── skill.md.template
├── scripts/
│   ├── validate.sh
│   └── generate-catalog.sh
├── profiles/
│   ├── default.json
│   ├── backend.json
│   ├── frontend.json
│   └── full-stack.json
├── rules/
│   ├── workflows/
│   ├── coding-standards/
│   ├── safety/
│   └── integrations/
├── skills/
└── agents/
```

## License

MIT
