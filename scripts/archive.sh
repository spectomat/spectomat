#!/bin/bash
# Spectomat archiver — phase D.
#
#   archive.sh <slug>
#
# Runs the contract's gates, moves the slug's trail into done/, bumps the patch
# version to the slug's NNN, makes one commit and writes one log line. A failing
# gate moves nothing and exits 1, until the third strike: then the trail is
# archived with a .blocked infix so the floor can move on.

set -uo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/utils.sh"
cd_root

SLUG="${1:-}"
BLOCK=""      # ".blocked" once the third strike lands
GATE_RESULT="" # "N/N" or "failed", for the log line
VERSION=""    # the new package.json version, when there is one

now() { date -u +%FT%RZ; }
log_line() { printf '%s\n' "$1" >> "$FLOOR/log.md"; }

require_ready() {
  [[ -n "$SLUG" ]] || die "usage: archive.sh <slug>"
  [[ -z "$(git status --porcelain)" ]] || die "tree is dirty: the janitor runs before phase D"
  [[ -f "$FLOOR/specs/$SLUG.md" ]] || die "no $FLOOR/specs/$SLUG.md"
  [[ -f "$FLOOR/plans/$SLUG.md" ]] || die "no $FLOOR/plans/$SLUG.md"
}

# Run the gates. A failure logs a strike and stops, unless it is the third:
# then the trail is archived blocked instead of stranding the floor.
gate_or_strike() {
  local total n
  total=$(gate_block | wc -l | tr -d ' ')
  if run_gates; then
    GATE_RESULT="$total/$total"
    return 0
  fi
  n=$(( $(strike_count D "$SLUG") + 1 ))
  log_line "- $(now) · D · $SLUG · gate failed: $GATE_FAILED (strike $n)"
  if [[ $n -lt $STRIKE_LIMIT ]]; then
    echo "❌ gate failed: $GATE_FAILED (strike $n of $STRIKE_LIMIT)" >&2
    exit 1
  fi
  BLOCK=".blocked"
  GATE_RESULT="failed"
}

move_trail() {
  git mv "$FLOOR/specs/$SLUG.md" "$FLOOR/done/$SLUG.spec$BLOCK.md"
  git mv "$FLOOR/plans/$SLUG.md" "$FLOOR/done/$SLUG.plan$BLOCK.md"
  [[ ! -d "$FLOOR/plans/$SLUG" ]] || git mv "$FLOOR/plans/$SLUG" "$FLOOR/done/$SLUG"
}

# The patch version becomes the slug's NNN; major and minor are kept. Blocked
# work ships no version. npm is used rather than a jq rewrite so package-lock
# stays in step.
bump_version() {
  local cur
  [[ -z "$BLOCK" ]] || return 0
  [[ -f package.json ]] || return 0
  cur=$(jq -r '.version // empty' package.json 2>/dev/null) || return 0
  [[ -n "$cur" ]] || return 0
  VERSION=$(next_version "$cur" "$SLUG") || { VERSION=""; return 0; }
  npm version --no-git-tag-version "$VERSION" >/dev/null 2>&1 || VERSION=""
}

commit_archive() {
  local msg
  if [[ -n "$BLOCK" ]]; then
    msg="chore($SLUG): blocked after $STRIKE_LIMIT strikes"
  else
    msg="chore($SLUG): archived${VERSION:+, v$VERSION}"
  fi
  git add -A "$FLOOR/done" "$FLOOR/specs" "$FLOOR/plans"
  [[ ! -f package.json ]] || git add package.json
  [[ ! -f package-lock.json ]] || git add package-lock.json
  git commit -q -m "$msg"
}

log_result() {
  if [[ -n "$BLOCK" ]]; then
    log_line "- $(now) · D · $SLUG · blocked after $STRIKE_LIMIT strikes · gates $GATE_RESULT"
  else
    log_line "- $(now) · D · $SLUG · archived · gates $GATE_RESULT${VERSION:+ · v$VERSION}"
  fi
}

main() {
  require_ready
  gate_or_strike
  move_trail
  bump_version
  commit_archive
  log_result
  echo "D $SLUG · gates $GATE_RESULT${VERSION:+ · v$VERSION}${BLOCK:+ · BLOCKED}"
}

main "$@"
