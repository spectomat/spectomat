#!/bin/bash
# briefs — every agents/*.md exists, is named right, and advances state.json
# the way its phase must.
#
#   tests/briefs_test.sh              tests ../scripts
#   tests/briefs_test.sh DIR          tests the scripts in DIR

set -uo pipefail
SCRIPTS="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../scripts" && pwd)}"
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

echo "briefs"
AGENTS="$(dirname "$SCRIPTS")/agents"
for a in specify review-spec plan implement review archive finish recover; do
  is "agents/$a.md exists" "$([[ -f "$AGENTS/$a.md" ]] && echo yes || echo no)" "yes"
  is "agents/$a.md is named $a" "$(sed -n 's/^name: *//p' "$AGENTS/$a.md" | head -1)" "$a"
  is "agents/$a.md has a description" \
    "$(grep -c '^description: ' "$AGENTS/$a.md")" "1"
done
is "AGENT_COUNT is 8" "$(ls "$AGENTS"/*.md | wc -l | tr -d ' ')" "8"
is "no brief carries a placeholder" "$(grep -l '{{' "$AGENTS"/*.md | wc -l | tr -d ' ')" "0"
is "no brief points at the deleted prompts/" \
  "$(grep -l 'prompts/' "$AGENTS"/*.md | wc -l | tr -d ' ')" "0"
is "specify.md advances state.json"     "$(grep -q 'slug_set_phase' "$AGENTS/specify.md" && echo yes || echo no)" "yes"
is "review-spec.md advances state.json" "$(grep -q 'slug_set_phase' "$AGENTS/review-spec.md" && echo yes || echo no)" "yes"
is "plan.md advances state.json"        "$(grep -q 'slug_start_tasks' "$AGENTS/plan.md" && echo yes || echo no)" "yes"
is "implement.md advances state.json"   "$(grep -q 'slug_task_done' "$AGENTS/implement.md" && echo yes || echo no)" "yes"
is "review.md advances state.json"      "$(grep -q -E 'slug_set_phase|slug_add_tasks' "$AGENTS/review.md" && echo yes || echo no)" "yes"
# A brief that blocks a slug must delete it from state.json in the same breath,
# or the picker's orphan check answers RECOVER to every iteration after it.
for a in specify review-spec implement review recover; do
  is "agents/$a.md deletes a blocked slug" "$(grep -q 'slug_delete' "$AGENTS/$a.md" && echo yes || echo no)" "yes"
done
is "contract.md's three strikes deletes the slug" \
  "$(grep -q 'slug_delete' "$(dirname "$SCRIPTS")/templates/contract.md" && echo yes || echo no)" "yes"
# archive.md and finish.md are thin wrappers (D21): the mutation stays in
# archive.sh, and the promise stays the pointer's, never the brief's own.
is "archive.md invokes archive.sh" "$(grep -q 'archive.sh' "$AGENTS/archive.md" && echo yes || echo no)" "yes"
is "archive.md never calls slug_delete itself" "$(grep -q 'slug_delete' "$AGENTS/archive.md" && echo yes || echo no)" "no"

finish
