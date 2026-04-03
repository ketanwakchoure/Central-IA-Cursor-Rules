# Central-IA-Cursor-Rules

A shared library of Cursor IDE rules, skills, and agents. Clone once, symlink everywhere -- keep your team's AI coding standards consistent across all workspaces.

## The Problem

Each project workspace ends up with its own copy of Cursor rules (`.mdc` files), skills, and agent configs. Rules get duplicated and drift across repos. There is no single source of truth.

## How It Works

```
Central Repo (GitHub)
        |
        |  cursor-rules install (git clone)
        v
~/.cursor-rules-library/        <-- one clone per dev machine
        |
        |  cursor-rules sync (symlinks)
        v
your-project/.cursor/rules/     <-- symlinks to library files
your-project/.cursor/skills/    <-- symlinks to library skills
your-project/.cursor/agents/    <-- symlinks to library agents
```

1. The library is cloned once to `~/.cursor-rules-library/`
2. Each workspace has a `.cursor-rules.json` that lists which profiles/rules/skills/agents to use
3. `cursor-rules sync` creates symlinks from `.cursor/` to the library
4. Local (non-symlinked) files are preserved untouched
5. Edit a symlinked file and run `cursor-rules propose` to open a PR

## Quick Start

### 1. Install the library

```bash
git clone https://github.com/ketanwakchoure/Central-IA-Cursor-Rules.git ~/.cursor-rules-library
```

### 2. Add an alias (recommended)

```bash
# Add to ~/.zshrc or ~/.bashrc
alias cursor-rules="$HOME/.cursor-rules-library/cli.sh"
```

### 3. Install a profile

```bash
# See available profiles
cursor-rules profile

# Install one (creates .cursor-rules.json + syncs all rules)
cursor-rules add profile backend
```

### 4. Stay updated

```bash
cursor-rules update
```

Pulls the latest rules from GitHub and re-syncs.

## CLI Reference

### Browse

| Command | Description |
|---------|-------------|
| `list` | List all rules, skills, and agents |
| `list rules` | List rules only |
| `list rules safety` | List rules in a specific category |
| `list skills` | List skills only |
| `list agents` | List agents only |
| `list profiles` | List available profiles |
| `profile` | List profiles with descriptions and rule counts |
| `profile <name>` | Preview rules in a profile (read-only) |

### Add

| Command | Description |
|---------|-------------|
| `add <rule-id>` | Add a rule to config and symlink it |
| `add skill <skill-id>` | Add a skill to config and symlink it |
| `add agent <agent-id>` | Add an agent to config and symlink it |
| `add profile <name>` | Install a profile (updates config + syncs all its items) |

Multiple profiles can be stacked -- rules from all active profiles are merged and deduplicated.

### Remove

| Command | Description |
|---------|-------------|
| `remove <rule-id>` | Remove a rule from config and delete its symlink |
| `remove skill <skill-id>` | Remove a skill from config and delete its symlink |
| `remove agent <agent-id>` | Remove an agent from config and delete its symlink |
| `remove profile <name>` | Remove a profile; only deletes items not used by other active profiles or explicit lists |

### Sync

| Command | Description |
|---------|-------------|
| `sync` | Symlink all items from config into the workspace (skips local files) |
| `sync -f` | Force-sync: replace local files with library symlinks |
| `update` | Pull latest library changes from GitHub, then sync |
| `update -f` | Pull latest, then force-sync |

### Propose

| Command | Description |
|---------|-------------|
| `propose <file.mdc> [--category <cat>]` | Propose a new rule (auto-detects type from extension) |
| `propose <SKILL.md>` | Propose a new skill (detected from filename) |
| `propose <file.md>` | Propose a new agent (detected from `.md` extension) |
| `propose <name> "message"` | Propose edits to an existing item via PR |

Type is auto-detected: `.mdc` = rule, `SKILL.md` = skill, `.md` = agent. Short names work -- `propose no-placeholder "Fix typo"` resolves to `safety/no-placeholder` automatically.

### Utilities

| Command | Description |
|---------|-------------|
| `install [repo-url]` | Clone the library to `~/.cursor-rules-library` |
| `validate` | Lint all library rules for valid frontmatter |
| `doctor` | Check installation health, config validity, and symlink integrity |
| `help` | Show help message |

### Examples

```bash
cursor-rules list                                      # everything
cursor-rules list rules safety                         # rules in safety category
cursor-rules list profiles                             # all profiles
cursor-rules profile backend                           # preview backend profile
cursor-rules add profile backend                       # install backend profile
cursor-rules add workflows/pr-review                   # add a single rule
cursor-rules add skill deploy                          # add a skill
cursor-rules remove profile backend                    # remove backend profile
cursor-rules sync                                      # sync (skip local files)
cursor-rules sync -f                                   # force-replace local files
cursor-rules update -f                                 # pull + force-sync
cursor-rules propose .cursor/rules/my-rule.mdc --category workflows   # new rule
cursor-rules propose no-secret-commit "Fix env var reference"          # edit rule
cursor-rules doctor                                    # health check
```

## Config Format: `.cursor-rules.json`

```json
{
  "library": "~/.cursor-rules-library",
  "profiles": ["default", "backend"],
  "rules": [
    "workflows/pr-review"
  ],
  "skills": [],
  "agents": []
}
```

| Field | Required | Description |
|-------|----------|-------------|
| `library` | No | Path to the library clone. Default: `~/.cursor-rules-library` |
| `profiles` | No | Array of active profile names. Rules from all profiles are merged. |
| `rules` | No | Explicit rule IDs on top of profiles. Format: `category/name` |
| `skills` | No | Explicit skill IDs. |
| `agents` | No | Explicit agent IDs. |

When profiles and explicit items are both present, they are merged and deduplicated. This file **should be committed** to your repo so the team shares the same selection.

Legacy format (`"profile": "backend"` as a string) is auto-migrated to the array format on the next `add profile` command.

## Profiles

Profiles are pre-defined bundles of rules, skills, and agents for common roles. They live in `profiles/`.

| Profile | Description | Rules |
|---------|-------------|-------|
| `default` | Safety rules that should always be active | 3 |
| `backend` | Safety + workflow rules for backend/API development | 5 |
| `frontend` | Safety + PR review rules for frontend development | 4 |
| `full-stack` | All available rules | 6 |

```bash
# Preview what's in a profile
cursor-rules profile backend

# Install it
cursor-rules add profile backend

# Stack multiple profiles
cursor-rules add profile default
cursor-rules add profile backend

# Remove one (keeps rules shared with other profiles)
cursor-rules remove profile backend
```

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

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) for full details.

### Propose a new rule

```bash
cursor-rules propose .cursor/rules/my-rule.mdc --category workflows
```

Auto-detects type from file extension, validates frontmatter, creates a branch, and opens a PR.

### Edit an existing rule

Edit the symlinked file in your workspace, then:

```bash
cursor-rules propose no-secret-commit "Fix env var reference"
```

Only commits changes to that specific rule. Short names resolve automatically.

## .gitignore Strategy

Symlinked rules should not be tracked by the workspace repo. Add to your workspace `.gitignore`:

```gitignore
# Shared cursor rules are symlinks managed by cursor-rules CLI
# .cursor-rules.json IS tracked (it's the team config)
.cursor/rules/*.mdc
.cursor/skills/
.cursor/agents/
!.cursor/rules/local-*.mdc
```

## Prerequisites

- **git** -- for cloning and updating the library
- **jq** -- for parsing `.cursor-rules.json` (`brew install jq` on macOS)
- **gh** (optional) -- GitHub CLI, for auto-creating PRs in `propose` (`brew install gh`)

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
