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
FORCE_SYNC=false

cmd_sync() {
  require_jq
  require_library
  require_config

  local rules_list skills_list agents_list
  rules_list=()
  skills_list=()
  agents_list=()

  # Load rules from all active profiles (supports both "profile" string and "profiles" array)
  local profiles_json
  profiles_json=$(jq -r '
    if .profiles then .profiles[]
    elif .profile then .profile
    else empty
    end' "$CONFIG_FILE" 2>/dev/null)

  if [[ -n "$profiles_json" ]]; then
    while IFS= read -r pname; do
      [[ -z "$pname" ]] && continue
      local profile_file="$LIBRARY_PATH/profiles/${pname}.json"
      if [[ ! -f "$profile_file" ]]; then
        warn "Profile '$pname' not found at $profile_file -- skipping"
        continue
      fi
      while IFS= read -r r; do [[ -n "$r" ]] && rules_list+=("$r"); done < <(jq -r '.rules[]?' "$profile_file")
      while IFS= read -r s; do [[ -n "$s" ]] && skills_list+=("$s"); done < <(jq -r '.skills[]?' "$profile_file")
      while IFS= read -r a; do [[ -n "$a" ]] && agents_list+=("$a"); done < <(jq -r '.agents[]?' "$profile_file")
    done <<< "$profiles_json"
  fi

  # Load explicit rules from config
  while IFS= read -r r; do [[ -n "$r" ]] && rules_list+=("$r"); done < <(jq -r '.rules[]?' "$CONFIG_FILE")
  while IFS= read -r s; do [[ -n "$s" ]] && skills_list+=("$s"); done < <(jq -r '.skills[]?' "$CONFIG_FILE")
  while IFS= read -r a; do [[ -n "$a" ]] && agents_list+=("$a"); done < <(jq -r '.agents[]?' "$CONFIG_FILE")

  # Deduplicate (macOS bash 3.x compatible)
  _dedup_array() {
    local items=("$@")
    if [[ ${#items[@]} -eq 0 ]]; then
      return
    fi
    printf '%s\n' "${items[@]}" | sort -u
  }

  local _dr _ds _da
  _dr=$(_dedup_array "${rules_list[@]+"${rules_list[@]}"}")
  _ds=$(_dedup_array "${skills_list[@]+"${skills_list[@]}"}")
  _da=$(_dedup_array "${agents_list[@]+"${agents_list[@]}"}")

  rules_list=()
  skills_list=()
  agents_list=()
  if [[ -n "$_dr" ]]; then
    while IFS= read -r r; do [[ -n "$r" ]] && rules_list+=("$r"); done <<< "$_dr"
  fi
  if [[ -n "$_ds" ]]; then
    while IFS= read -r s; do [[ -n "$s" ]] && skills_list+=("$s"); done <<< "$_ds"
  fi
  if [[ -n "$_da" ]]; then
    while IFS= read -r a; do [[ -n "$a" ]] && agents_list+=("$a"); done <<< "$_da"
  fi

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
        if [[ "$FORCE_SYNC" == "true" ]]; then
          rm "$dest"
          warn "Replaced local file: $dest"
        else
          warn "Skipping $dest -- local file exists (not a symlink). Use -f to force."
          continue
        fi
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
        if [[ "$FORCE_SYNC" == "true" ]]; then
          rm "$dest_file"
          warn "Replaced local file: $dest_file"
        else
          warn "Skipping $dest_file -- local file exists. Use -f to force."
          continue
        fi
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
        if [[ "$FORCE_SYNC" == "true" ]]; then
          rm "$dest"
          warn "Replaced local file: $dest"
        else
          warn "Skipping $dest -- local file exists. Use -f to force."
          continue
        fi
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

  while [[ $# -gt 0 ]]; do
    case "$1" in
      -f|--force) FORCE_SYNC=true; shift ;;
      *) shift ;;
    esac
  done

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

# ── helpers ───────────────────────────────────────────────────────────
_ensure_config() {
  if [[ ! -f "$CONFIG_FILE" ]]; then
    info "Creating $CONFIG_FILE ..."
    cat > "$CONFIG_FILE" <<'EOF'
{
  "library": "~/.cursor-rules-library",
  "rules": [],
  "skills": [],
  "agents": []
}
EOF
  fi
}

_add_item() {
  local type="$1" item_id="$2"
  require_jq
  require_library

  # Resolve source file and symlink destination
  local src="" dest=""
  case "$type" in
    rule)
      src="$LIBRARY_PATH/rules/${item_id}.mdc"
      dest=".cursor/rules/$(basename "$item_id").mdc"
      ;;
    skill)
      src="$LIBRARY_PATH/skills/${item_id}/SKILL.md"
      dest=".cursor/skills/$(basename "$item_id")/SKILL.md"
      ;;
    agent)
      src="$LIBRARY_PATH/agents/${item_id}.md"
      dest=".cursor/agents/$(basename "$item_id").md"
      ;;
  esac

  if [[ ! -f "$src" ]]; then
    err "${type^} not found: $item_id"
    err "Run '$(basename "$0") list' to see available items."
    exit 1
  fi

  _ensure_config

  local json_key="${type}s"
  local already
  already=$(jq -r --arg id "$item_id" --arg k "$json_key" '.[$k][]? | select(. == $id)' "$CONFIG_FILE" 2>/dev/null || true)
  if [[ -n "$already" ]]; then
    warn "${type^} '$item_id' is already in $CONFIG_FILE"
  else
    local tmp
    tmp=$(mktemp)
    jq --arg id "$item_id" --arg k "$json_key" '.[$k] += [$id]' "$CONFIG_FILE" > "$tmp" && mv "$tmp" "$CONFIG_FILE"
    ok "Added $type '$item_id' to $CONFIG_FILE"
  fi

  mkdir -p "$(dirname "$dest")"
  [[ -L "$dest" ]] && rm "$dest"
  ln -s "$src" "$dest"
  ok "Symlinked: $dest"
}

_remove_item() {
  local type="$1" item_id="$2"
  require_jq
  require_config

  local json_key="${type}s"
  local tmp
  tmp=$(mktemp)
  jq --arg id "$item_id" --arg k "$json_key" '.[$k] = [.[$k][] | select(. != $id)]' "$CONFIG_FILE" > "$tmp" && mv "$tmp" "$CONFIG_FILE"
  ok "Removed $type '$item_id' from $CONFIG_FILE"

  local dest=""
  case "$type" in
    rule)  dest=".cursor/rules/$(basename "$item_id").mdc" ;;
    skill) dest=".cursor/skills/$(basename "$item_id")/SKILL.md" ;;
    agent) dest=".cursor/agents/$(basename "$item_id").md" ;;
  esac

  if [[ -L "$dest" ]]; then
    rm "$dest"
    ok "Removed symlink: $dest"
  elif [[ -f "$dest" ]]; then
    warn "$dest exists but is not a symlink -- leaving it in place."
  fi
}

# ── add ───────────────────────────────────────────────────────────────
cmd_add() {
  local first="${1:-}"
  if [[ -z "$first" ]]; then
    err "Usage:"
    err "  $(basename "$0") add <rule-id>              Add a rule"
    err "  $(basename "$0") add skill <skill-id>       Add a skill"
    err "  $(basename "$0") add agent <agent-id>       Add an agent"
    err "  $(basename "$0") add profile <name>         Add a profile"
    exit 1
  fi

  case "$first" in
    profile)
      require_jq
      require_library
      local profile_name="${2:-}"
      if [[ -z "$profile_name" ]]; then
        err "Usage: $(basename "$0") add profile <name>"
        exit 1
      fi
      local profile_file="$LIBRARY_PATH/profiles/${profile_name}.json"
      if [[ ! -f "$profile_file" ]]; then
        err "Profile '$profile_name' not found."
        err "Run '$(basename "$0") profile' to see available profiles."
        exit 1
      fi
      _ensure_config
      local tmp
      tmp=$(mktemp)
      jq --arg p "$profile_name" '
        (if .profile then [.profile] else (.profiles // []) end) as $existing
        | if ($existing | index($p)) then .
          else . + {profiles: ($existing + [$p])}
          end
        | del(.profile)
      ' "$CONFIG_FILE" > "$tmp" && mv "$tmp" "$CONFIG_FILE"
      ok "Added profile '${profile_name}' to $CONFIG_FILE"
      local pdesc
      pdesc=$(jq -r '.description // ""' "$profile_file")
      [[ -n "$pdesc" ]] && info "$pdesc"
      echo ""
      cmd_sync
      ;;
    skill) _add_item "skill" "${2:-}" ;;
    agent) _add_item "agent" "${2:-}" ;;
    *)     _add_item "rule" "$first" ;;
  esac
}

# ── remove ────────────────────────────────────────────────────────────
cmd_remove() {
  require_jq
  require_config

  local first="${1:-}"
  if [[ -z "$first" ]]; then
    err "Usage:"
    err "  $(basename "$0") remove <rule-id>              Remove a rule"
    err "  $(basename "$0") remove skill <skill-id>       Remove a skill"
    err "  $(basename "$0") remove agent <agent-id>       Remove an agent"
    err "  $(basename "$0") remove profile <name>         Remove a profile"
    exit 1
  fi

  case "$first" in
    profile)
      local profile_name="${2:-}"
      if [[ -z "$profile_name" ]]; then
        err "Usage: $(basename "$0") remove profile <name>"
        exit 1
      fi

      local is_active
      is_active=$(jq -r --arg p "$profile_name" '
        if .profiles then (.profiles | index($p) // empty)
        elif .profile == $p then "yes"
        else empty
        end' "$CONFIG_FILE" 2>/dev/null || true)

      if [[ -z "$is_active" ]]; then
        warn "Profile '$profile_name' is not active in $CONFIG_FILE"
        return
      fi

      local profile_file="$LIBRARY_PATH/profiles/${profile_name}.json"

      # Collect ALL items from the profile being removed
      local removing_rules="" removing_skills="" removing_agents=""
      if [[ -f "$profile_file" ]]; then
        removing_rules=$(jq -r '.rules[]?' "$profile_file" 2>/dev/null || true)
        removing_skills=$(jq -r '.skills[]?' "$profile_file" 2>/dev/null || true)
        removing_agents=$(jq -r '.agents[]?' "$profile_file" 2>/dev/null || true)
      fi

      # Collect items to KEEP (from other profiles + explicit lists)
      local keep_rules="" keep_skills="" keep_agents=""
      local other_profiles
      other_profiles=$(jq -r --arg p "$profile_name" '
        if .profiles then [.profiles[] | select(. != $p)][]
        else empty
        end' "$CONFIG_FILE" 2>/dev/null || true)

      if [[ -n "$other_profiles" ]]; then
        while IFS= read -r op; do
          [[ -z "$op" ]] && continue
          local opfile="$LIBRARY_PATH/profiles/${op}.json"
          [[ ! -f "$opfile" ]] && continue
          keep_rules="${keep_rules}$(jq -r '.rules[]?' "$opfile" 2>/dev/null)"$'\n'
          keep_skills="${keep_skills}$(jq -r '.skills[]?' "$opfile" 2>/dev/null)"$'\n'
          keep_agents="${keep_agents}$(jq -r '.agents[]?' "$opfile" 2>/dev/null)"$'\n'
        done <<< "$other_profiles"
      fi
      keep_rules="${keep_rules}$(jq -r '.rules[]?' "$CONFIG_FILE" 2>/dev/null)"$'\n'
      keep_skills="${keep_skills}$(jq -r '.skills[]?' "$CONFIG_FILE" 2>/dev/null)"$'\n'
      keep_agents="${keep_agents}$(jq -r '.agents[]?' "$CONFIG_FILE" 2>/dev/null)"$'\n'

      # Remove profile from config
      local tmp
      tmp=$(mktemp)
      jq --arg p "$profile_name" '
        if .profiles then .profiles = [.profiles[] | select(. != $p)]
        else del(.profile)
        end' "$CONFIG_FILE" > "$tmp" && mv "$tmp" "$CONFIG_FILE"
      ok "Removed profile '${profile_name}' from $CONFIG_FILE"

      # Remove non-overlapping symlinks
      local removed=0
      _remove_profile_items() {
        local items="$1" keep="$2" type="$3"
        [[ -z "$items" ]] && return
        while IFS= read -r item_id; do
          [[ -z "$item_id" ]] && continue
          if echo "$keep" | grep -qx "$item_id" 2>/dev/null; then
            info "Keeping $type '$item_id' (used by another profile or explicit list)"
            continue
          fi
          local dest=""
          case "$type" in
            rule)  dest=".cursor/rules/$(basename "$item_id").mdc" ;;
            skill) dest=".cursor/skills/$(basename "$item_id")/SKILL.md" ;;
            agent) dest=".cursor/agents/$(basename "$item_id").md" ;;
          esac
          if [[ -L "$dest" ]]; then
            rm "$dest"
            ok "Removed symlink: $dest"
            ((removed++))
          fi
        done <<< "$items"
      }
      _remove_profile_items "$removing_rules" "$keep_rules" "rule"
      _remove_profile_items "$removing_skills" "$keep_skills" "skill"
      _remove_profile_items "$removing_agents" "$keep_agents" "agent"

      echo ""
      ok "Profile '${profile_name}' removed. $removed symlink(s) cleaned up."
      ;;
    skill) _remove_item "skill" "${2:-}" ;;
    agent) _remove_item "agent" "${2:-}" ;;
    *)     _remove_item "rule" "$first" ;;
  esac
}

# ── profile ───────────────────────────────────────────────────────────
cmd_profile() {
  require_jq
  require_library

  local profile_name="${1:-}"

  # No args: list all profiles
  if [[ -z "$profile_name" ]]; then
    echo -e "${BOLD}Available profiles:${NC}"
    echo ""
    while IFS= read -r pfile; do
      [[ -z "$pfile" ]] && continue
      local pname
      pname=$(basename "$pfile" .json)
      local pdesc
      pdesc=$(jq -r '.description // "(no description)"' "$pfile")
      local pcount
      pcount=$(jq -r '.rules | length' "$pfile")
      echo -e "  ${GREEN}${pname}${NC}  --  ${pdesc} (${pcount} rules)"
    done < <(find "$LIBRARY_PATH/profiles" -name '*.json' 2>/dev/null | sort)
    echo ""
    info "Usage:"
    info "  $(basename "$0") profile <name>           Preview rules in a profile"
    info "  $(basename "$0") add profile <name>       Install a profile"
    info "  $(basename "$0") remove profile <name>    Remove a specific profile"
    return
  fi

  # With arg: preview the profile's rules
  local profile_file="$LIBRARY_PATH/profiles/${profile_name}.json"
  if [[ ! -f "$profile_file" ]]; then
    err "Profile '$profile_name' not found."
    err "Run '$(basename "$0") profile' to see available profiles."
    exit 1
  fi

  local pdesc
  pdesc=$(jq -r '.description // "(no description)"' "$profile_file")
  echo -e "${BOLD}${profile_name}${NC}  --  ${pdesc}"
  echo ""
  echo -e "${BOLD}Rules:${NC}"
  while IFS= read -r rule_id; do
    [[ -z "$rule_id" ]] && continue
    local src="$LIBRARY_PATH/rules/${rule_id}.mdc"
    local desc="(not found)"
    if [[ -f "$src" ]]; then
      desc=$(extract_description "$src")
      [[ -z "$desc" ]] && desc="(no description)"
    fi
    echo -e "  ${GREEN}${rule_id}${NC}  --  ${desc}"
  done < <(jq -r '.rules[]?' "$profile_file")

  echo ""
  info "To install: $(basename "$0") add profile ${profile_name}"
}

# ── propose ───────────────────────────────────────────────────────────
#
# Two modes:
#   propose <file.mdc> [--category <cat>]   -- new rule from a local file
#   propose "message"                       -- edit PR for changes to existing rules
#
cmd_propose() {
  require_library

  local file=""
  local category=""
  local rule_name=""
  local message=""

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --category) category="$2"; shift 2 ;;
      *)
        if [[ -f "$1" ]]; then
          file="$1"
        elif [[ -z "$rule_name" ]]; then
          rule_name="$1"
        else
          message="$1"
        fi
        shift ;;
    esac
  done

  # ── Mode: edit an existing item by name ──
  # Usage: propose <name> "message"
  # Searches rules, skills, and agents by full ID or short name
  if [[ -z "$file" && -n "$rule_name" ]]; then
    local matches=()
    local match_ids=()
    local match_types=()

    # Search rules
    while IFS= read -r candidate; do
      [[ -z "$candidate" ]] && continue
      local rel="${candidate#$LIBRARY_PATH/rules/}"
      local id="${rel%.mdc}"
      if [[ "$id" == "$rule_name" || "$(basename "$id")" == "$rule_name" ]]; then
        matches+=("$candidate")
        match_ids+=("$id")
        match_types+=("rule")
      fi
    done < <(find "$LIBRARY_PATH/rules" -name '*.mdc' 2>/dev/null | sort)

    # Search skills
    while IFS= read -r candidate; do
      [[ -z "$candidate" ]] && continue
      local skill_dir
      skill_dir=$(dirname "$candidate")
      local id="${skill_dir#$LIBRARY_PATH/skills/}"
      if [[ "$id" == "$rule_name" || "$(basename "$id")" == "$rule_name" ]]; then
        matches+=("$candidate")
        match_ids+=("$id")
        match_types+=("skill")
      fi
    done < <(find "$LIBRARY_PATH/skills" -name 'SKILL.md' 2>/dev/null | sort)

    # Search agents
    while IFS= read -r candidate; do
      [[ -z "$candidate" ]] && continue
      local rel="${candidate#$LIBRARY_PATH/agents/}"
      local id="${rel%.md}"
      if [[ "$id" == "$rule_name" || "$(basename "$id")" == "$rule_name" ]]; then
        matches+=("$candidate")
        match_ids+=("$id")
        match_types+=("agent")
      fi
    done < <(find "$LIBRARY_PATH/agents" -name '*.md' ! -name '.gitkeep' 2>/dev/null | sort)

    if [[ ${#matches[@]} -eq 0 ]]; then
      err "'$rule_name' not found in rules, skills, or agents."
      err "Run '$(basename "$0") list' to see available items."
      exit 1
    fi

    local rule_file=""
    local item_type=""
    if [[ ${#matches[@]} -gt 1 ]]; then
      warn "Multiple items match '$rule_name':"
      local idx=1
      for i in "${!match_ids[@]}"; do
        echo "  $idx) [${match_types[$i]}] ${match_ids[$i]}"
        ((idx++))
      done
      echo ""
      read -rp "Select [1-${#matches[@]}]: " choice
      rule_file="${matches[$((choice-1))]}"
      rule_name="${match_ids[$((choice-1))]}"
      item_type="${match_types[$((choice-1))]}"
    else
      rule_file="${matches[0]}"
      rule_name="${match_ids[0]}"
      item_type="${match_types[0]}"
    fi

    local rel_path="${rule_file#$LIBRARY_PATH/}"
    info "Resolved ${item_type}: $rule_name"

    # Check if this specific rule has changes
    local rule_changed
    rule_changed=$(git -C "$LIBRARY_PATH" diff -- "$rel_path" 2>/dev/null)
    if [[ -z "$rule_changed" ]]; then
      err "No changes detected in '$rule_name'"
      info "Edit the rule first (via its symlink), then run this command."
      exit 1
    fi

    echo -e "${BOLD}Changes in ${rule_name}:${NC}"
    echo ""
    git -C "$LIBRARY_PATH" diff --stat -- "$rel_path"
    echo ""

    if [[ -z "$message" ]]; then
      read -rp "PR title: " message
      if [[ -z "$message" ]]; then
        err "A PR title is required."
        exit 1
      fi
    fi

    local branch
    branch="update/$(echo "$rule_name" | tr '/' '-')-$(echo "$message" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9]/-/g' | sed 's/--*/-/g' | sed 's/^-//;s/-$//' | cut -c1-30)"

    local orig_dir
    orig_dir=$(pwd)
    cd "$LIBRARY_PATH"

    git checkout -b "$branch" 2>/dev/null || { err "Branch '$branch' already exists."; cd "$orig_dir"; exit 1; }
    git add "$rel_path"
    git commit -m "$message"
    git push -u origin "$branch" 2>&1

    local pr_body
    pr_body="## Rule Update

**Rule:** $rule_name
**File:** $rel_path

$message

---
Auto-generated by \`cli.sh propose\`"

    _open_pr "$message" "$pr_body" "$branch"

    git checkout main 2>/dev/null
    cd "$orig_dir"
    return
  fi

  if [[ -z "$file" ]]; then
    err "Usage:"
    err "  $(basename "$0") propose <file> [--category <cat>]      Add a new rule/skill/agent"
    err "  $(basename "$0") propose <name> \"message\"               PR for edits to an existing item"
    err ""
    err "Examples:"
    err "  $(basename "$0") propose .cursor/rules/my-rule.mdc --category workflows"
    err "  $(basename "$0") propose no-secret-commit \"Fix env var reference\""
    exit 1
  fi

  # ── Mode: propose a new item from a local file ──
  require_jq

  if [[ ! -f "$file" ]]; then
    err "File not found: $file"
    exit 1
  fi

  # Auto-detect type from file
  local item_type="" filename
  filename=$(basename "$file")
  if [[ "$filename" == *.mdc ]]; then
    item_type="rule"
  elif [[ "$filename" == "SKILL.md" ]]; then
    item_type="skill"
  elif [[ "$filename" == *.md ]]; then
    item_type="agent"
  else
    err "Cannot detect type from '$filename'."
    err "Expected: *.mdc (rule), SKILL.md (skill), or *.md (agent)"
    exit 1
  fi
  info "Detected type: ${item_type}"

  # Validate frontmatter
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

  local item_name dest_dir dest_rel_path branch_name

  case "$item_type" in
    rule)
      # Rules go into rules/<category>/
      if [[ -z "$category" ]]; then
        echo "Available categories:"
        local i=1
        local cats=()
        while IFS= read -r d; do
          local cname
          cname=$(basename "$d")
          cats+=("$cname")
          echo "  $i) $cname"
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
      item_name=$(echo "$filename" | sed 's/\.mdc$//')
      dest_dir="$LIBRARY_PATH/rules/$category"
      dest_rel_path="rules/$category/$filename"
      branch_name="propose/${item_name}"
      ;;
    skill)
      # Skills go into skills/<name>/SKILL.md
      # Derive name from parent directory of the SKILL.md file, or ask
      local skill_name
      skill_name=$(basename "$(dirname "$file")")
      if [[ "$skill_name" == "." || "$skill_name" == "/" ]]; then
        read -rp "Skill name (kebab-case): " skill_name
      fi
      item_name="$skill_name"
      dest_dir="$LIBRARY_PATH/skills/$skill_name"
      dest_rel_path="skills/$skill_name/SKILL.md"
      branch_name="propose/skill-${skill_name}"
      ;;
    agent)
      item_name=$(echo "$filename" | sed 's/\.md$//')
      dest_dir="$LIBRARY_PATH/agents"
      dest_rel_path="agents/$filename"
      branch_name="propose/agent-${item_name}"
      ;;
  esac

  mkdir -p "$dest_dir"
  cp "$file" "$dest_dir/$filename"

  local orig_dir
  orig_dir=$(pwd)
  cd "$LIBRARY_PATH"

  git checkout -b "$branch_name" 2>/dev/null || git checkout "$branch_name"
  git add "$dest_rel_path"
  git commit -m "Add ${item_type}: ${item_name}" -m "$desc"
  git push -u origin "$branch_name"

  local pr_title="Add ${item_type}: ${item_name}"
  local pr_body="## New ${item_type^} Proposal

**Type:** ${item_type}
**Name:** ${item_name}
**File:** ${dest_rel_path}
**Description:** $desc

---
Auto-generated by \`cli.sh propose\`"

  _open_pr "$pr_title" "$pr_body" "$branch_name"

  git checkout main 2>/dev/null
  cd "$orig_dir"
}

_open_pr() {
  local title="$1"
  local body="$2"
  local branch="$3"

  if command -v gh &>/dev/null && gh pr create \
    --title "$title" \
    --body "$body" \
    --head "$branch" 2>&1; then
    echo ""
    ok "PR created successfully."
  else
    echo ""
    warn "Could not auto-create PR. Push succeeded -- create it manually:"
    info "https://github.com/$(git remote get-url origin | sed 's|.*github.com[:/]||;s|\.git$||')/pull/new/${branch}"
  fi
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
  local script
  script=$(basename "$0")
  echo -e "${BOLD}cursor-rules${NC} v${VERSION} -- Shared Cursor Rules Library CLI"
  echo ""
  echo -e "${BOLD}USAGE${NC}"
  echo "  $script <command> [options]"
  echo ""
  echo -e "${BOLD}COMMANDS${NC}"
  echo "  install [repo-url]          Clone the shared library to ~/.cursor-rules-library"
  echo "  sync [-f]                   Symlink rules from library into current workspace"
  echo "  update [-f]                 Pull latest library changes and re-sync"
  echo "  list [--category <cat>]     List all available rules, skills, and agents"
  echo "  add <rule-id>               Add a rule"
  echo "  add skill <skill-id>        Add a skill"
  echo "  add agent <agent-id>        Add an agent"
  echo "  add profile <name>          Install a profile (syncs all its items)"
  echo "  remove <rule-id>            Remove a rule"
  echo "  remove skill <skill-id>     Remove a skill"
  echo "  remove agent <agent-id>     Remove an agent"
  echo "  remove profile <name>       Remove a profile; keeps items used elsewhere"
  echo "  profile                     List available profiles"
  echo "  profile <name>              Preview rules in a profile"
  echo "  propose <file> [--category] Propose a new rule to the library via PR"
  echo "  propose <rule> \"message\"    Propose edits to a specific rule via PR"
  echo "  validate                    Lint all library rules for valid frontmatter"
  echo "  doctor                      Check installation health and symlink integrity"
  echo "  help                        Show this help message"
  echo ""
  echo -e "${BOLD}EXAMPLES${NC}"
  echo "  $script install"
  echo "  $script list"
  echo "  $script profile                          # list profiles"
  echo "  $script profile backend                   # preview backend profile"
  echo "  $script add profile backend               # install backend profile"
  echo "  $script add workflows/pr-review           # add a single rule"
  echo "  $script remove profile backend             # remove backend profile"
  echo "  $script sync                              # sync (skip local files)"
  echo "  $script sync -f                           # force-replace local files"
  echo "  $script update -f                          # pull + force-sync"
  echo "  $script propose .cursor/rules/my-rule.mdc --category workflows       # new rule"
  echo "  $script propose safety/no-secret-commit \"Fix env var reference\"    # edit rule"
  echo "  $script doctor"
  echo ""
  echo -e "${BOLD}CONFIG${NC}"
  echo "  Place a .cursor-rules.json in your workspace root:"
  echo '  {'
  echo '    "library": "~/.cursor-rules-library",'
  echo '    "profile": "default",'
  echo '    "rules": ["workflows/pr-review", "safety/no-placeholder"],'
  echo '    "skills": [],'
  echo '    "agents": []'
  echo '  }'
}

# ── Main dispatch ─────────────────────────────────────────────────────
main() {
  local cmd="${1:-help}"
  shift || true

  case "$cmd" in
    install)  cmd_install "$@" ;;
    sync)
      while [[ $# -gt 0 ]]; do
        case "$1" in
          -f|--force) FORCE_SYNC=true; shift ;;
          *) shift ;;
        esac
      done
      cmd_sync ;;
    update)   cmd_update ;;
    list)     cmd_list "$@" ;;
    add)      cmd_add "$@" ;;
    remove)   cmd_remove "$@" ;;
    profile)  cmd_profile "$@" ;;
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
