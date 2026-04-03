#!/usr/bin/env bash
set -euo pipefail

LIBRARY_PATH="${1:-.}"
OUTPUT="$LIBRARY_PATH/CATALOG.md"

extract_description() {
  awk '/^---$/{n++; next} n==1 && /^description:/{sub(/^description:[[:space:]]*/, ""); print; exit}' "$1"
}

capitalize() {
  echo "$1" | awk '{print toupper(substr($0,1,1)) substr($0,2)}'
}

cat > "$OUTPUT" <<'HEADER'
# Catalog

Auto-generated index of all shared rules, skills, and agents.

> Regenerate with: `./scripts/generate-catalog.sh`

HEADER

for section in rules skills agents; do
  base="$LIBRARY_PATH/$section"
  [[ ! -d "$base" ]] && continue

  found=0
  current_category=""

  while IFS= read -r file; do
    [[ -z "$file" ]] && continue

    rel="${file#$base/}"
    category="${rel%/*}"
    name="${rel##*/}"
    name="${name%.mdc}"
    name="${name%.md}"

    [[ "$name" == ".gitkeep" ]] && continue
    [[ "$name" == *".template" ]] && continue

    if [[ "$section" == "skills" ]]; then
      name=$(dirname "$rel")
    fi

    desc=$(extract_description "$file")
    [[ -z "$desc" ]] && desc="(no description)"

    if [[ $found -eq 0 ]]; then
      printf "## %s\n\n" "$(capitalize "$section")" >> "$OUTPUT"
    fi

    if [[ "$category" != "$current_category" ]]; then
      printf "### %s\n\n" "$category" >> "$OUTPUT"
      current_category="$category"
    fi

    printf -- "- **%s** -- %s\n" "$name" "$desc" >> "$OUTPUT"
    ((found++))

  done < <(find "$base" -type f \( -name '*.mdc' -o -name 'SKILL.md' -o -name '*.md' \) ! -name '.gitkeep' ! -name '*.template' 2>/dev/null | sort)

  if [[ $found -gt 0 ]]; then
    echo "" >> "$OUTPUT"
  fi
done

echo "Generated $OUTPUT"
