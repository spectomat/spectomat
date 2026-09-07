#!/bin/bash
# Spectomat init — scaffold the spec-driven Ralph flow in the current repository.
#
#   init.sh [NAME] [--spec PATH] [--force]
#
# Writes ralph-loop-prompt.md (from the template), a spec skeleton when the
# spec file is absent, and the .gitignore entry for the ledger. Never
# overwrites an existing ralph-loop-prompt.md without --force, and never
# touches an existing spec.

set -euo pipefail

TEMPLATES="$(cd "$(dirname "${BASH_SOURCE[0]}")/../templates" && pwd)"
ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
cd "$ROOT"

NAME=""
SPEC=""
FORCE=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --spec)
      [[ -n "${2:-}" ]] || { echo "❌ --spec needs a path" >&2; exit 1; }
      SPEC="$2"; shift 2 ;;
    --force) FORCE=1; shift ;;
    -h|--help)
      sed -n '2,9p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit 0 ;;
    -*) echo "❌ unknown option: $1" >&2; exit 1 ;;
    *) NAME="$1"; shift ;;
  esac
done

[[ -n "$NAME" ]] || NAME="$(basename "$ROOT")"
[[ -n "$SPEC" ]] || SPEC="docs/$NAME.md"
SPEC="${SPEC#./}"
SPEC_DIR="$(dirname "$SPEC")"
LEDGER=".claude/build-ledger.local.md"
PROMPT="ralph-loop-prompt.md"

# Gates: detect npm scripts by convention, else leave an EDIT placeholder.
GATES=""
if [[ -f package.json ]]; then
  for s in typecheck test lint synth; do
    if grep -qE "\"$s\"[[:space:]]*:" package.json; then
      if [[ "$s" == "test" ]]; then GATES+="npm test"$'\n'; else GATES+="npm run $s"$'\n'; fi
    fi
  done
fi
if [[ -z "$GATES" ]]; then
  GATES="# EDIT: one gate per line; each must exit 0 before every commit"$'\n'
fi
GATES="${GATES%$'\n'}"

render() {
  PROJECT="$NAME" SPEC="$SPEC" SPEC_DIR="$SPEC_DIR" REPO="$ROOT" LEDGER="$LEDGER" GATES="$GATES" \
  perl -pe '
    s/\{\{PROJECT\}\}/$ENV{PROJECT}/g;
    s/\{\{SPEC_DIR\}\}/$ENV{SPEC_DIR}/g;
    s/\{\{SPEC\}\}/$ENV{SPEC}/g;
    s/\{\{REPO\}\}/$ENV{REPO}/g;
    s/\{\{LEDGER\}\}/$ENV{LEDGER}/g;
    s/\{\{GATES\}\}/$ENV{GATES}/g;
  ' "$1"
}

echo "--- spectomat init: $NAME ---"
echo "root: $ROOT"
echo "spec: $SPEC"

if [[ -f "$PROMPT" && $FORCE -eq 0 ]]; then
  echo "$PROMPT: exists, kept (use --force to overwrite)"
else
  render "$TEMPLATES/ralph-loop-prompt.md" > "$PROMPT"
  echo "$PROMPT: written"
fi

if [[ -f "$SPEC" ]]; then
  echo "$SPEC: exists, kept ($(wc -l < "$SPEC" | tr -d ' ') lines)"
else
  mkdir -p "$SPEC_DIR"
  render "$TEMPLATES/spec.md" > "$SPEC"
  echo "$SPEC: skeleton written"
fi

mkdir -p .claude
if [[ -f .gitignore ]] && grep -qxF '.claude/*.local.md' .gitignore; then
  echo ".gitignore: ledger entry present"
else
  printf '.claude/*.local.md\n' >> .gitignore
  echo ".gitignore: added .claude/*.local.md"
fi

echo "--- gates detected ---"
echo "$GATES"
echo "--- to fill ---"
echo "EDIT blocks in $PROMPT: $(grep -c '<!-- EDIT' "$PROMPT" || true)"
