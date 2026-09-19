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
for a in specify review-spec plan implement review archive recover task; do
  is "agents/$a.md exists" "$([[ -f "$AGENTS/$a.md" ]] && echo yes || echo no)" "yes"
  is "agents/$a.md is named $a" "$(sed -n 's/^name: *//p' "$AGENTS/$a.md" | head -1)" "$a"
  is "agents/$a.md has a description" \
    "$(grep -c '^description: ' "$AGENTS/$a.md")" "1"
done
is "AGENT_COUNT is 8" "$(ls "$AGENTS"/*.md | wc -l | tr -d ' ')" "8"
# implement dispatches the task agent (D30); the task agent builds one task and
# touches no floor state — a worker that advanced state.json or logged would
# make one task two entries.
is "implement.md dispatches spectomat:task" "$(grep -q 'spectomat:task' "$AGENTS/implement.md" && echo yes || echo no)" "yes"
is "implement.md allows the Agent tool" "$(grep -q '^tools:.*Agent' "$AGENTS/implement.md" && echo yes || echo no)" "yes"
is "implement.md does not disallow the Agent tool" "$(grep -q '^disallowedTools:.*Agent' "$AGENTS/implement.md" && echo yes || echo no)" "no"
is "task.md disallows the Agent tool" "$(grep -q '^disallowedTools:.*Agent' "$AGENTS/task.md" && echo yes || echo no)" "yes"
is "task.md never advances state.json" \
  "$(grep -q -E 'slug_set_phase|slug_strike|slug_done|block_slug\.sh|tasks\.sh' "$AGENTS/task.md" && echo yes || echo no)" "no"
is "task.md never logs" "$(grep -q 'log\.sh' "$AGENTS/task.md" && echo yes || echo no)" "no"
TASK_TEMPLATE="$(dirname "$SCRIPTS")/templates/task.md"
for h in "## Scope" "### Excerpts from Spec" "### From Memory" "### From existing codebase" "### From previous tasks"; do
  is "templates/task.md has '$h'" "$(grep -q "^$h\$" "$TASK_TEMPLATE" && echo yes || echo no)" "yes"
done
is "no brief carries a placeholder" "$(grep -l '{{' "$AGENTS"/*.md | wc -l | tr -d ' ')" "0"
is "no brief points at the deleted prompts/" \
  "$(grep -l 'prompts/' "$AGENTS"/*.md | wc -l | tr -d ' ')" "0"
is "specify.md advances state.json"     "$(grep -q 'slug_set_phase' "$AGENTS/specify.md" && echo yes || echo no)" "yes"
is "review-spec.md advances state.json" "$(grep -q 'slug_set_phase' "$AGENTS/review-spec.md" && echo yes || echo no)" "yes"
is "plan.md advances state.json"        "$(grep -q 'tasks\.sh start' "$AGENTS/plan.md" && echo yes || echo no)" "yes"
is "plan.md writes the ledger"          "$(grep -q 'tasks\.sh write' "$AGENTS/plan.md" && echo yes || echo no)" "yes"
is "implement.md advances state.json"   "$(grep -q 'tasks\.sh close' "$AGENTS/implement.md" && echo yes || echo no)" "yes"
is "implement.md picks from the ledger" "$(grep -q 'tasks\.sh next' "$AGENTS/implement.md" && echo yes || echo no)" "yes"
is "implement.md prints the dispatch"   "$(grep -q 'tasks\.sh dispatch' "$AGENTS/implement.md" && echo yes || echo no)" "yes"
is "review.md advances state.json"      "$(grep -q -E 'slug_set_phase|tasks\.sh add' "$AGENTS/review.md" && echo yes || echo no)" "yes"
# The ledger is the SSOT, so no brief may reach around scripts/tasks.sh to it.
for a in plan implement review recover; do
  is "agents/$a.md never edits tasks.json with jq" \
    "$(grep -E 'jq[^|]*tasks\.json' "$AGENTS/$a.md" >/dev/null && echo yes || echo no)" "no"
done
is "no brief still names result.md" "$(grep -l 'result\.md' "$AGENTS"/*.md | wc -l | tr -d ' ')" "0"
# A brief that blocks a slug must finish it in state.json in the same breath,
# or the slug stays at its phase with its strikes spent, and the picker sends
# every remaining iteration to the janitor instead.
for a in specify review-spec implement review recover; do
  is "agents/$a.md finishes a blocked slug" "$(grep -q 'block_slug\.sh' "$AGENTS/$a.md" && echo yes || echo no)" "yes"
done
is "contract.md's three strikes finishes the slug" \
  "$(grep -q 'block_slug\.sh' "$(dirname "$SCRIPTS")/templates/contract.md" && echo yes || echo no)" "yes"
# archive.md is a thin wrapper (D21): the mutation stays in agent-archive.sh.
# FINISH has no brief at all (D24) — the Stop hook ends the flow and composes
# the report, so no agent can claim the floor is empty.
is "archive.md invokes agent-archive.sh" "$(grep -q 'agent-archive.sh' "$AGENTS/archive.md" && echo yes || echo no)" "yes"
is "archive.md never calls block_slug.sh itself" "$(grep -q 'block_slug\.sh' "$AGENTS/archive.md" && echo yes || echo no)" "no"
is "there is no finish brief" "$([[ -e "$AGENTS/finish.md" ]] && echo yes || echo no)" "no"
is "no brief mentions the retired promise" "$(grep -l 'FACTORY EMPTY' "$AGENTS"/*.md | wc -l | tr -d ' ')" "0"

finish
