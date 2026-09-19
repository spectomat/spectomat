#!/bin/bash
# Spectomat verification — every check a change must pass, run in parallel.
#
#   scripts/verify_all.sh
#
#   manifests   claude plugin validate --strict, plugin and marketplace
#   syntax      bash -n on the scripts, the tests and the gates template
#   selftest    scripts/selftest.sh
#   links       relative markdown links across every tracked *.md
#   whitespace  git diff --check against HEAD
#
# Prints one line per check, then the output of each failed one.
# Exits non-zero when any check fails.

set -uo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 1

OUT=$(mktemp -d); trap 'rm -rf "$OUT"' EXIT

check_manifests() {
  local p1 p2 r1 r2
  claude plugin validate .claude-plugin/plugin.json --strict & p1=$!
  claude plugin validate .claude-plugin/marketplace.json --strict & p2=$!
  wait "$p1"; r1=$?
  wait "$p2"; r2=$?
  [[ $r1 -eq 0 && $r2 -eq 0 ]]
}

check_syntax() {
  local f rc=0
  for f in scripts/*.sh tests/*.sh templates/gates.sh; do
    bash -n "$f" || rc=1
  done
  return $rc
}

check_selftest() { scripts/selftest.sh; }

# A link is `](target)`; a target with a scheme or a bare #anchor is not ours.
check_links() {
  local f dir target path rc=0
  while IFS= read -r f; do
    dir=$(dirname "$f")
    while IFS= read -r target; do
      path=${target%%#*}; path=${path%% *}
      [[ -n "$path" ]] || continue
      [[ "$path" == /* ]] && path=".$path" || path="$dir/$path"
      [[ -e "$path" ]] || { printf '%s: broken link: %s\n' "$f" "$target"; rc=1; }
    done < <(grep -o '\]([^)]*)' "$f" | sed 's/^](//; s/)$//' | grep -Ev '^([a-zA-Z][a-zA-Z0-9+.-]*:|#)')
  done < <(git ls-files '*.md')
  return $rc
}

check_whitespace() { git diff --check HEAD; }

#        name        label                                         verdict when green
CHECKS=(
  'manifests|claude plugin validate --strict, both manifests|both passed'
  'syntax|bash -n on the scripts, tests and gates|syntax ok'
  'selftest|scripts/selftest.sh|'
  'links|relative markdown links across all docs|none broken'
  'whitespace|git diff --check|clean'
)

PIDS=()
for c in "${CHECKS[@]}"; do
  name=${c%%|*}
  "check_$name" > "$OUT/$name" 2>&1 &
  PIDS+=($!)
done

FAILED=()
i=0
for c in "${CHECKS[@]}"; do
  IFS='|' read -r name label green <<< "$c"
  wait "${PIDS[$i]}"; rc=$?; i=$((i + 1))
  # The suite's own tally is its verdict, green or red.
  [[ "$name" == selftest ]] && green=$(tail -1 "$OUT/$name")
  if [[ $rc -eq 0 ]]; then
    printf '✅ %s — %s\n' "$label" "$green"
  else
    printf '❌ %s — failed\n' "$label"
    FAILED+=("$name")
  fi
done

for name in ${FAILED[@]+"${FAILED[@]}"}; do
  printf '\n── %s ──\n' "$name"
  cat "$OUT/$name"
done

[[ ${#FAILED[@]} -eq 0 ]]
