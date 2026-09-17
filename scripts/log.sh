#!/bin/bash
# Spectomat log — the one place a factory log line is formatted.
#
#   log.sh <PHASE> <slug> <message...>
#
# Appends "- <ts> · <PHASE> · <slug> · <message>" to log.md. The timestamp is
# always `date -u +%FT%RZ` run now — a caller never supplies one, so the log
# cannot carry a remembered or typed time. Creates log.md with its header on
# first use, matching prepare.sh's own bootstrap. The log is gitignored and
# never committed; this script only appends to it.

set -uo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/utils.sh"
cd_root

main() {
  local phase="${1:-}" slug="${2:-}"
  shift 2 2>/dev/null || true
  local message="$*"
  [[ -n "$phase" && -n "$slug" && -n "$message" ]] \
    || die "usage: log.sh <PHASE> <slug> <message...>"
  [[ -f "$FLOOR/log.md" ]] || printf '# Spectomat factory log\n\n' > "$FLOOR/log.md"
  printf '%s\n' "- $(date -u +%FT%RZ) · $phase · $slug · $message" >> "$FLOOR/log.md"
}

main "$@"
