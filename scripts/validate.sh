#!/usr/bin/env bash
set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BOLD='\033[1m'
NC='\033[0m'

LIBRARY_PATH="${1:-.}"
errors=0
warnings=0
checked=0

echo -e "${BOLD}Validating rules in ${LIBRARY_PATH}/rules/ ...${NC}"
echo ""

while IFS= read -r file; do
  [[ -z "$file" ]] && continue
  ((checked++))

  rel="${file#$LIBRARY_PATH/}"
  filename=$(basename "$file")

  # Check kebab-case filename
  if [[ "$filename" =~ [A-Z_] ]]; then
    echo -e "${YELLOW}WARN${NC}  $rel -- filename should use kebab-case (got: $filename)"
    ((warnings++))
  fi

  # Check frontmatter exists
  first_line=$(head -1 "$file")
  if [[ "$first_line" != "---" ]]; then
    echo -e "${RED}FAIL${NC}  $rel -- missing YAML frontmatter (file must start with ---)"
    ((errors++))
    continue
  fi

  # Check closing frontmatter delimiter
  closing=$(awk '/^---$/{n++} n==2{print NR; exit}' "$file")
  if [[ -z "$closing" ]]; then
    echo -e "${RED}FAIL${NC}  $rel -- frontmatter not closed (missing second ---)"
    ((errors++))
    continue
  fi

  # Check description field
  desc=$(awk '/^---$/{n++; next} n==1 && /^description:/{sub(/^description:[[:space:]]*/, ""); print; exit}' "$file")
  if [[ -z "$desc" ]]; then
    echo -e "${RED}FAIL${NC}  $rel -- missing 'description' field in frontmatter"
    ((errors++))
    continue
  fi

  # Check body is non-empty (at least 10 chars after frontmatter)
  body_len=$(awk '/^---$/{n++; next} n>=2{print}' "$file" | wc -c | tr -d ' ')
  if [[ "$body_len" -lt 10 ]]; then
    echo -e "${RED}FAIL${NC}  $rel -- body is too short (${body_len} chars, minimum 10)"
    ((errors++))
    continue
  fi

  echo -e "${GREEN}OK${NC}    $rel"

done < <(find "$LIBRARY_PATH/rules" -type f -name '*.mdc' 2>/dev/null | sort)

echo ""
echo -e "${BOLD}Results:${NC} $checked file(s) checked, ${RED}${errors} error(s)${NC}, ${YELLOW}${warnings} warning(s)${NC}"

if [[ $errors -gt 0 ]]; then
  exit 1
fi
