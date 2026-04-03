#!/usr/bin/env bash
set -euo pipefail

LIBRARY_DEFAULT="$HOME/.cursor-rules-library"
CONFIG_FILE=".cursor-rules.json"
VERSION="1.0.0"

# ── Colors ────────────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
BOLD='\033[1m'
NC='\033[0m'

info()  { echo -e "${BLUE}ℹ${NC}  $*"; }
ok()    { echo -e "${GREEN}✔${NC}  $*"; }
warn()  { echo -e "${YELLOW}⚠${NC}  $*"; }
err()   { echo -e "${RED}✖${NC}  $*" >&2; }

get_library_path() {
  if [[ -f "$CONFIG_FILE" ]] && command -v jq &>/dev/null; then
    local lib
    lib=$(jq -r '.library // empty' "$CONFIG_FILE" 2>/dev/null)
    if [[ -n "$lib" ]]; then
      echo "${lib/#\~/$HOME}"
      return
    fi
  fi
  echo "$LIBRARY_DEFAULT"
}

LIBRARY_PATH="$(get_library_path)"

# ── Helpers ───────────────────────────────────────────────────────────
require_jq() {
  if ! command -v jq &>/dev/null; then
    err "jq is required but not installed. Install it: brew install jq (macOS) or apt install jq (Linux)"
    exit 1
  fi
}

require_gh() {
  if ! command -v gh &>/dev/null; then
    err "GitHub CLI (gh) is required for this command. Install it: brew install gh"
    exit 1
  fi
}

require_library() {
  if [[ ! -d "$LIBRARY_PATH" ]]; then
    err "Library not found at $LIBRARY_PATH"
    err "Run '$(basename "$0") install' first."
    exit 1
  fi
}

require_config() {
  if [[ ! -f "$CONFIG_FILE" ]]; then
    err "No $CONFIG_FILE found in current directory."
    err "Create one manually or run '$(basename "$0") add <rule-id>' to bootstrap it."
    exit 1
  fi
}

extract_description() {
  local file="$1"
  awk '/^---$/{n++; next} n==1 && /^description:/{sub(/^description:[[:space:]]*/, ""); print; exit}' "$file"
}

# ── install ───────────────────────────────────────────────────────────
cmd_install() {
  local repo_url="${1:-https://github.com/ketanwakchoure/Central-IA-Cursor-Rules.git}"

  if [[ -d "$LIBRARY_PATH/.git" ]]; then
    ok "Library already installed at $LIBRARY_PATH"
    info "Run '$(basename "$0") update' to pull latest changes."
    return
  fi

  info "Cloning shared rules library to $LIBRARY_PATH ..."
  git clone "$repo_url" "$LIBRARY_PATH"
  ok "Library installed at $LIBRARY_PATH"
  echo ""
  info "Optional: add an alias to your shell profile:"
  echo "  alias cursor-rules='$LIBRARY_PATH/cli.sh'"
}

# ── sync ──────────────────────────────────────────────────────────────
cmd_sync() {
  require_jq
  require_library
  require_config

  local profile rules_list skills_list agents_list
  profile=$(jq -r '.profile // empty' "$CONFIG_FILE")

  rules_list=()
  skills_list=()
  agents_list=()

  if [[ -n "$profile" ]]; then
    local profile_file="$LIBRARY_PATH/profiles/${profile}.json"
    if [[ ! -f "$profile_file" ]]; then
      err "Profile '$profile' not found at $profile_file"
      exit 1
    fi
    while IFS= read -r r; do rules_list+=("$r"); done < <(jq -r '.rules[]? // empty' "$profile_file")
    while IFS= read -r s; do skills_list+=("$s"); done < <(jq -r '.skills[]? // empty' "$profile_file")
    while IFS= read -r a; do agents_list+=("$a"); done < <(jq -r '.agents[]? // empty' "$profile_file")
  fi

  while IFS= read -r r; do rules_list+=("$r"); done < <(jq -r '.rules[]? // empty' "$CONFIG_FILE")
  while IFS= read -r s; do skills_list+=("$s"); done < <(jq -r '.skills[]? // empty' "$CONFIG_FILE")
  while IFS= read -r a; do agents_list+=("$a"); done < <(jq -r '.agents[]? // empty' "$CONFIG_FILE")

  # Deduplicate
  mapfile -t rules_list < <(printf '%s\n' "${rules_list[@]}" | sort -u)
  mapfile -t skills_list < <(printf '%s\n' "${skills_list[@]}" | sort -u)
  mapfile -t agents_list < <(printf '%s\n' "${agents_list[@]}" | sort -u)

  local linked=0

  # Sync rules
  if [[ ${#rules_list[@]} -gt 0 ]]; then
    mkdir -p .cursor/rules
    for rule_id in "${rules_list[@]}"; do
      [[ -z "$rule_id" ]] && continue
      local src="$LIBRARY_PATH/rules/${rule_id}.mdc"
      local dest=".cursor/rules/$(basename "$rule_id").mdc"
      if [[ ! -f "$src" ]]; then
        warn "Rule not found: $rule_id (expected at $src)"
        continue
      fi
      if [[ -L "$dest" ]]; then
        rm "$dest"
      elif [[ -f "$dest" ]]; then
        warn "Skipping $dest -- local file exists (not a symlink). Remove it first to sync."
        continue
      fi
      ln -s "$src" "$dest"
      ok "Linked rule: $rule_id"
      ((linked++))
    done
  fi

  # Sync skills
  if [[ ${#skills_list[@]} -gt 0 ]]; then
    mkdir -p .cursor/skills
    for skill_id in "${skills_list[@]}"; do
      [[ -z "$skill_id" ]] && continue
      local src="$LIBRARY_PATH/skills/${skill_id}/SKILL.md"
      local dest=".cursor/skills/$(basename "$skill_id")"
      if [[ ! -f "$src" ]]; then
        warn "Skill not found: $skill_id (expected at $src)"
        continue
      fi
      mkdir -p "$dest"
      local dest_file="$dest/SKILL.md"
      if [[ -L "$dest_file" ]]; then
        rm "$dest_file"
      elif [[ -f "$dest_file" ]]; then
        warn "Skipping $dest_file -- local file exists. Remove it first to sync."
        continue
      fi
      ln -s "$src" "$dest_file"
      ok "Linked skill: $skill_id"
      ((linked++))
    done
  fi

  # Sync agents
  if [[ ${#agents_list[@]} -gt 0 ]]; then
    mkdir -p .cursor/agents
    for agent_id in "${agents_list[@]}"; do
      [[ -z "$agent_id" ]] && continue
      local src="$LIBRARY_PATH/agents/${agent_id}.md"
      local dest=".cursor/agents/$(basename "$agent_id").md"
      if [[ ! -f "$src" ]]; then
        warn "Agent not found: $agent_id (expected at $src)"
        continue
      fi
      if [[ -L "$dest" ]]; then
        rm "$dest"
      elif [[ -f "$dest" ]]; then
        warn "Skipping $dest -- local file exists. Remove it first to sync."
        continue
      fi
      ln -s "$src" "$dest"
      ok "Linked agent: $agent_id"
      ((linked++))
    done
  fi

  echo ""
  ok "Sync complete. $linked item(s) linked."
}

# ── update ────────────────────────────────────────────────────────────
cmd_update() {
  require_library

  info "Pulling latest changes ..."
  git -C "$LIBRARY_PATH" pull --ff-only
  ok "Library updated."

  if [[ -f "$CONFIG_FILE" ]]; then
    echo ""
    cmd_sync
  else
    info "No $CONFIG_FILE in current directory -- skipping sync."
  fi
}

# ── list ──────────────────────────────────────────────────────────────
cmd_list() {
  require_library

  local filter_category="${1:-}"
  local section

  for section in rules skills agents; do
    local base="$LIBRARY_PATH/$section"
    [[ ! -d "$base" ]] && continue

    local found=0
    local output=""

    while IFS= read -r file; do
      [[ -z "$file" ]] && continue
      local rel="${file#$base/}"
      local category="${rel%/*}"
      local name="${rel##*/}"
      name="${name%.mdc}"
      name="${name%.md}"

      if [[ -n "$filter_category" && "$category" != "$filter_category" ]]; then
        continue
      fi

      local desc
      desc=$(extract_description "$file")
      [[ -z "$desc" ]] && desc="(no description)"

      if [[ $found -eq 0 ]]; then
        local label
        label=$(echo "$section" | awk '{print toupper(substr($0,1,1)) substr($0,2)}')
        output+="\n${BOLD}${label}${NC}\n"
      fi
      output+="  ${GREEN}${category}/${name}${NC}  --  ${desc}\n"
      ((found++))
    done < <(find "$base" -type f \( -name '*.mdc' -o -name 'SKILL.md' -o -name '*.md' \) ! -name '.gitkeep' ! -name '*.template' 2>/dev/null | sort)

    if [[ $found -gt 0 ]]; then
      echo -e "$output"
    fi
  done
}

# ── add ───────────────────────────────────────────────────────────────
cmd_add() {
  require_jq
  require_library

  local rule_id="${1:-}"
  if [[ -z "$rule_id" ]]; then
    err "Usage: $(basename "$0") add <rule-id>"
    err "Example: $(basename "$0") add workflows/pr-review"
    exit 1
  fi

  local src="$LIBRARY_PATH/rules/${rule_id}.mdc"
  if [[ ! -f "$src" ]]; then
    err "Rule not found: $rule_id"
    err "Run '$(basename "$0") list' to see available rules."
    exit 1
  fi

  if [[ ! -f "$CONFIG_FILE" ]]; then
    info "Creating $CONFIG_FILE ..."
    cat > "$CONFIG_FILE" <<EOF
{
  "library": "~/.cursor-rules-library",
  "rules": [],
  "skills": [],
  "agents": []
}
EOF
  fi

  local already
  already=$(jq -r --arg id "$rule_id" '.rules[] | select(. == $id)' "$CONFIG_FILE" 2>/dev/null || true)
  if [[ -n "$already" ]]; then
    warn "Rule '$rule_id' is already in $CONFIG_FILE"
  else
    local tmp
    tmp=$(mktemp)
    jq --arg id "$rule_id" '.rules += [$id]' "$CONFIG_FILE" > "$tmp" && mv "$tmp" "$CONFIG_FILE"
    ok "Added '$rule_id' to $CONFIG_FILE"
  fi

  mkdir -p .cursor/rules
  local dest=".cursor/rules/$(basename "$rule_id").mdc"
  [[ -L "$dest" ]] && rm "$dest"
  ln -s "$src" "$dest"
  ok "Symlinked: $dest -> $src"
}

# ── remove ────────────────────────────────────────────────────────────
cmd_remove() {
  require_jq
  require_config

  local rule_id="${1:-}"
  if [[ -z "$rule_id" ]]; then
    err "Usage: $(basename "$0") remove <rule-id>"
    exit 1
  fi

  local tmp
  tmp=$(mktemp)
  jq --arg id "$rule_id" '.rules = [.rules[] | select(. != $id)]' "$CONFIG_FILE" > "$tmp" && mv "$tmp" "$CONFIG_FILE"
  ok "Removed '$rule_id' from $CONFIG_FILE"

  local dest=".cursor/rules/$(basename "$rule_id").mdc"
  if [[ -L "$dest" ]]; then
    rm "$dest"
    ok "Removed symlink: $dest"
  elif [[ -f "$dest" ]]; then
    warn "$dest exists but is not a symlink -- leaving it in place."
  fi
}

# ── propose ───────────────────────────────────────────────────────────
cmd_propose() {
  require_jq
  require_gh
  require_library

  local file=""
  local category=""

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --category) category="$2"; shift 2 ;;
      *) file="$1"; shift ;;
    esac
  done

  if [[ -z "$file" ]]; then
    err "Usage: $(basename "$0") propose <file.mdc> [--category <category>]"
    exit 1
  fi

  if [[ ! -f "$file" ]]; then
    err "File not found: $file"
    exit 1
  fi

  # Validate the file
  local desc
  desc=$(extract_description "$file")
  if [[ -z "$desc" ]]; then
    err "File is missing a 'description' field in frontmatter."
    err "Add YAML frontmatter with at least: description: <your description>"
    exit 1
  fi

  local body_len
  body_len=$(awk '/^---$/{n++; next} n>=2{print}' "$file" | wc -c | tr -d ' ')
  if [[ "$body_len" -lt 10 ]]; then
    err "File body is too short (${body_len} chars). Add meaningful content after the frontmatter."
    exit 1
  fi

  # Prompt for category if not provided
  if [[ -z "$category" ]]; then
    echo "Available categories:"
    local i=1
    local cats=()
    while IFS= read -r d; do
      local name
      name=$(basename "$d")
      cats+=("$name")
      echo "  $i) $name"
      ((i++))
    done < <(find "$LIBRARY_PATH/rules" -mindepth 1 -maxdepth 1 -type d | sort)
    echo "  $i) Create new category"
    echo ""
    read -rp "Select category [1-$i]: " choice

    if [[ "$choice" -eq "$i" ]]; then
      read -rp "New category name (kebab-case): " category
    else
      category="${cats[$((choice-1))]}"
    fi
  fi

  local rule_name
  rule_name=$(basename "$file")
  local dest_dir="$LIBRARY_PATH/rules/$category"
  mkdir -p "$dest_dir"
  cp "$file" "$dest_dir/$rule_name"

  local branch="propose/$(echo "$rule_name" | sed 's/\.mdc$//')"
  cd "$LIBRARY_PATH"
  git checkout -b "$branch" 2>/dev/null || git checkout "$branch"
  git add "rules/$category/$rule_name"
  git commit -m "Add rule: $category/$(echo "$rule_name" | sed 's/\.mdc$//')" -m "$desc"
  git push -u origin "$branch"

  local pr_url
  pr_url=$(gh pr create \
    --title "Add rule: $category/$(echo "$rule_name" | sed 's/\.mdc$//')" \
    --body "## New Rule Proposal

**Category:** $category
**File:** $rule_name
**Description:** $desc

---
Auto-generated by \`cli.sh propose\`" 2>&1)

  echo ""
  ok "PR created: $pr_url"
  cd - > /dev/null
}

# ── validate ──────────────────────────────────────────────────────────
cmd_validate() {
  require_library

  local script="$LIBRARY_PATH/scripts/validate.sh"
  if [[ ! -f "$script" ]]; then
    err "Validation script not found at $script"
    exit 1
  fi

  bash "$script" "$LIBRARY_PATH"
}

# ── doctor ────────────────────────────────────────────────────────────
cmd_doctor() {
  echo -e "${BOLD}cursor-rules doctor${NC}"
  echo ""

  local issues=0

  # Check library
  if [[ -d "$LIBRARY_PATH/.git" ]]; then
    ok "Library installed at $LIBRARY_PATH"
  else
    err "Library NOT found at $LIBRARY_PATH"
    ((issues++))
  fi

  # Check jq
  if command -v jq &>/dev/null; then
    ok "jq found: $(jq --version)"
  else
    err "jq NOT found -- required for config parsing"
    ((issues++))
  fi

  # Check gh
  if command -v gh &>/dev/null; then
    ok "gh found: $(gh --version | head -1)"
  else
    warn "gh (GitHub CLI) not found -- needed only for 'propose' command"
  fi

  # Check config in current directory
  if [[ -f "$CONFIG_FILE" ]]; then
    ok "$CONFIG_FILE found in current directory"

    if command -v jq &>/dev/null; then
      if jq empty "$CONFIG_FILE" 2>/dev/null; then
        ok "$CONFIG_FILE is valid JSON"
      else
        err "$CONFIG_FILE has invalid JSON"
        ((issues++))
      fi
    fi
  else
    info "No $CONFIG_FILE in current directory (optional)"
  fi

  # Check symlink health
  if [[ -d .cursor/rules ]]; then
    local broken=0
    while IFS= read -r link; do
      if [[ ! -e "$link" ]]; then
        err "Broken symlink: $link -> $(readlink "$link")"
        ((broken++))
      fi
    done < <(find .cursor/rules -type l 2>/dev/null)

    if [[ $broken -eq 0 ]]; then
      local count
      count=$(find .cursor/rules -type l 2>/dev/null | wc -l | tr -d ' ')
      ok "All symlinks healthy ($count linked rules)"
    else
      ((issues += broken))
    fi
  fi

  echo ""
  if [[ $issues -eq 0 ]]; then
    ok "No issues found."
  else
    err "$issues issue(s) found."
  fi
}

# ── help ──────────────────────────────────────────────────────────────
cmd_help() {
  cat <<EOF
${BOLD}cursor-rules${NC} v${VERSION} -- Shared Cursor Rules Library CLI

${BOLD}USAGE${NC}
  $(basename "$0") <command> [options]

${BOLD}COMMANDS${NC}
  install [repo-url]          Clone the shared library to ~/.cursor-rules-library
  sync                        Symlink rules from library into current workspace
  update                      Pull latest library changes and re-sync
  list [--category <cat>]     List all available rules, skills, and agents
  add <rule-id>               Add a rule to .cursor-rules.json and symlink it
  remove <rule-id>            Remove a rule from .cursor-rules.json and its symlink
  propose <file> [--category] Contribute a local rule to the shared library via PR
  validate                    Lint all library rules for valid frontmatter
  doctor                      Check installation health and symlink integrity
  help                        Show this help message

${BOLD}EXAMPLES${NC}
  $(basename "$0") install
  $(basename "$0") list
  $(basename "$0") add workflows/pr-review
  $(basename "$0") sync
  $(basename "$0") propose .cursor/rules/my-rule.mdc --category workflows
  $(basename "$0") doctor

${BOLD}CONFIG${NC}
  Place a .cursor-rules.json in your workspace root:
  {
    "library": "~/.cursor-rules-library",
    "profile": "default",
    "rules": ["workflows/pr-review", "safety/no-placeholder"],
    "skills": [],
    "agents": []
  }

EOF
}

# ── Main dispatch ─────────────────────────────────────────────────────
main() {
  local cmd="${1:-help}"
  shift || true

  case "$cmd" in
    install)  cmd_install "$@" ;;
    sync)     cmd_sync ;;
    update)   cmd_update ;;
    list)     cmd_list "$@" ;;
    add)      cmd_add "$@" ;;
    remove)   cmd_remove "$@" ;;
    propose)  cmd_propose "$@" ;;
    validate) cmd_validate ;;
    doctor)   cmd_doctor ;;
    help|-h|--help) cmd_help ;;
    *)
      err "Unknown command: $cmd"
      echo ""
      cmd_help
      exit 1
      ;;
  esac
}

main "$@"
