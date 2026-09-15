#!/bin/bash
# licence — the NOTICE.md obligation: it must not point at a file that is gone.
#
#   scripts/tests/licence_test.sh          tests the scripts next to it
#   scripts/tests/licence_test.sh DIR      tests the scripts in DIR

set -uo pipefail
SCRIPTS="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

echo "licence"
REPO_ROOT="$(dirname "$SCRIPTS")"
missing=$(cd "$REPO_ROOT" && for f in $(grep -oE '`[a-zA-Z0-9_./-]+\.(md|sh|json)`' NOTICE.md | tr -d '`'); do
            # `.spectomat/` paths are written into the user's project at runtime,
            # so they are not files of this repo and are not checked here.
            [[ "$f" == .spectomat/* ]] && continue
            [[ -e "$f" ]] || printf '%s ' "$f"; done)
is "NOTICE.md names only files that exist" "${missing% }" ""

finish
