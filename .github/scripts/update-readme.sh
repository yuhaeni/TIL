#!/usr/bin/env bash

REPO_ROOT="$(git rev-parse --show-toplevel)"
README="$REPO_ROOT/README.md"
TMPFILE="$(mktemp)"
SECTION_FILE="$(mktemp)"

# 카테고리 목록 생성 함수
generate_section() {
  local dir="$1"
  local label="$2"

  echo "### ${label}"
  echo ""

  for file in "$REPO_ROOT/$dir"/*.md; do
    [ -f "$file" ] || continue
    filename=$(basename "$file")
    title=$(grep -m 1 '^# ' "$file" | sed 's/^# //')
    if [ -z "$title" ]; then
      title="${filename%.md}"
    fi
    encoded_path="${dir}/$(echo "$filename" | sed 's/ /%20/g')"
    echo "- [${title}](${encoded_path})"
  done

  echo ""
}

# 섹션 내용을 파일로 저장
{
  generate_section "operating-system" "🖥️ 운영체제"
  generate_section "system-design" "⚙️ 시스템 설계"
  generate_section "docker" "🐳 Docker"
  generate_section "java" "☕ Java"
  generate_section "algorithm" "🧮 알고리즘"
} > "$SECTION_FILE"

# README.md에서 TIL_START ~ TIL_END 사이를 교체
in_section=0
while IFS= read -r line; do
  if echo "$line" | grep -q '<!-- TIL_START -->'; then
    echo "$line"
    cat "$SECTION_FILE"
    in_section=1
    continue
  fi
  if echo "$line" | grep -q '<!-- TIL_END -->'; then
    in_section=0
  fi
  if [ "$in_section" -eq 0 ]; then
    echo "$line"
  fi
done < "$README" > "$TMPFILE"

mv "$TMPFILE" "$README"
rm -f "$SECTION_FILE"

echo "README.md 업데이트 완료"
