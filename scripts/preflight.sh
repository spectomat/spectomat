#!/bin/bash
# Spectomat preflight — report whether the repository is ready for /spectomat:build.
# Prints facts only; the command that runs it decides what to do.

set -uo pipefail

ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
cd "$ROOT"
PROMPT="ralph-loop-prompt.md"
LEDGER=".claude/build-ledger.local.md"
STATE=".claude/spectomat-loop.local.md"
INSTALLED="$HOME/.claude/plugins/installed_plugins.json"
READY=1

echo "--- root ---"
echo "$ROOT"
[[ "$(pwd)" == "$ROOT" ]] || echo "WARNING: session cwd is not the repo root; the loop must start from $ROOT"

echo "--- repo ---"
if [[ -d .git ]]; then
  echo "git: initialised, branch $(git branch --show-current 2>/dev/null || echo '(none yet)')"
  git status --porcelain | head
else
  echo "git: ABSENT - Phase 0 will run 'git init'."
fi

echo "--- loop prompt ---"
if [[ -f "$PROMPT" ]]; then
  EDITS=$(grep -c '<!-- EDIT' "$PROMPT" || true)
  echo "$PROMPT: $(wc -l < "$PROMPT" | tr -d ' ') lines, $EDITS EDIT blocks left"
  [[ "$EDITS" -eq 0 ]] || { echo "WARNING: fill or delete every '<!-- EDIT' block before starting"; READY=0; }
  SPEC=$(sed -n 's/^Specification: `\([^`]*\)`.*/\1/p' "$PROMPT" | head -1)
else
  echo "MISSING - run /spectomat:init first."
  READY=0
  SPEC=""
fi

echo "--- spec ---"
if [[ -n "$SPEC" && -f "$SPEC" ]]; then
  echo "$SPEC: $(wc -l < "$SPEC" | tr -d ' ') lines"
  grep -q '^## ' "$SPEC" || echo "WARNING: spec has no numbered sections"
elif [[ -n "$SPEC" ]]; then
  echo "$SPEC: MISSING - the loop has nothing to build from."
  READY=0
else
  echo "(unknown until $PROMPT exists)"
fi

echo "--- ledger ---"
if [[ -f "$LEDGER" ]]; then
  echo "EXISTS - loop will RESUME. Unchecked items: $(grep -c '^- \[ \]' "$LEDGER" || true)"
else
  echo "ABSENT - loop will start at Phase 0 (plan)."
fi

echo "--- ralph state ---"
if [[ -f "$STATE" ]]; then
  echo "WARNING: $STATE exists (iteration $(grep '^iteration:' "$STATE" | sed 's/iteration: *//')). A loop may be active; /spectomat:cancel first."
else
  echo "no active loop"
fi

echo "--- plugins ---"
for p in superpowers; do
  if [[ -f "$INSTALLED" ]] && grep -q "\"$p@" "$INSTALLED"; then
    echo "$p: installed"
  else
    echo "$p: NOT FOUND in $INSTALLED - install it before starting"
    READY=0
  fi
done

echo "--- toolchain ---"
echo "node $(node -v 2>/dev/null || echo MISSING)"
[[ -d node_modules ]] && echo "node_modules: present" || echo "node_modules: absent"

echo "--- verdict ---"
[[ $READY -eq 1 ]] && echo "READY" || echo "NOT READY"
