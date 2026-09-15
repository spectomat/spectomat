#!/bin/bash
# phase.sh — the picker: one verdict per iteration, priority order, strikes,
# RECOVER, and the no-mutation guarantee.
#
#   scripts/tests/phase_test.sh          tests the scripts next to it
#   scripts/tests/phase_test.sh DIR      tests the scripts in DIR

set -uo pipefail
SCRIPTS="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

echo "phase.sh"
pk() { is "$1" "$(cd "$FIXTURE" && bash "$SCRIPTS/phase.sh")" "$2"; }

floor p_empty
pk "an empty floor is FINISH" "FINISH"

floor p_a; draft 001-a
pk "a draft is SPECIFY" "SPECIFY 001-a"

floor p_b; spec 001-a
pk "an unreviewed spec is REVIEW-SPEC" "REVIEW-SPEC 001-a"

floor p_b2; spec 001-a yes
pk "a reviewed spec with no plan is PLAN" "PLAN 001-a"

floor p_bare; spec 001-a yes; plan_bare 001-a
pk "an overview with no task files is PLAN" "PLAN 001-a"

floor p_c; spec 001-a; plan 001-a 3 1
pk "an open step is IMPLEMENT" "IMPLEMENT 001-a"

floor p_d; spec 001-a; plan 001-a 3 0
pk "every step ticked and unreviewed is REVIEW" "REVIEW 001-a"

floor p_reviewed; spec 001-a; plan 001-a 3 0 yes
pk "a closing verdict releases it to ARCHIVE" "ARCHIVE 001-a"

# REVIEW round 1 adds fix tasks and writes no verdict: the plan reopens and the
# picker sends it back to IMPLEMENT, which is the whole fix loop.
floor p_fixtasks; spec 001-a; plan 001-a 3 0
printf 'step\n' > "$FIXTURE/.spectomat/plans/001-a/task-04-fix.md"
printf 'overview\n\n## Review\n\n- Round 1 — 2 findings (0 critical, 2 important, 0 minor) — tasks 04 added\n' > "$FIXTURE/.spectomat/plans/001-a.md"
fixture_commit
state_slug 001-a IMPLEMENT 4 3
pk "a review round without a verdict reopens IMPLEMENT" "IMPLEMENT 001-a"

# One candidate per stage, all six at once; ARCHIVE wins.
floor p_order; draft 006-f; spec 005-e; spec 004-d yes; plan 003-c 2 1; spec 003-c; spec 002-b; plan 002-b 1 0; spec 001-a; plan 001-a 2 0 yes
pk "ARCHIVE outranks REVIEW, IMPLEMENT, PLAN, REVIEW-SPEC and SPECIFY" "ARCHIVE 001-a"

floor p_order2; draft 003-c; plan 002-b 2 1; spec 002-b; spec 001-a; plan 001-a 2 0
pk "REVIEW outranks IMPLEMENT, PLAN and SPECIFY" "REVIEW 001-a"

floor p_order3; draft 003-c; spec 002-b; spec 001-a yes
pk "PLAN outranks REVIEW-SPEC and SPECIFY" "PLAN 001-a"

floor p_order4; draft 001-a; spec 002-b
pk "REVIEW-SPEC outranks SPECIFY" "REVIEW-SPEC 002-b"

# The two review phases share a prefix; a strike at one must not count at the
# other, or a struck spec review would silently skip the plan review too.
floor p_strike_prefix; spec 001-a; plan 001-a 2 0
strike 001-a REVIEW-SPEC 3
pk "REVIEW-SPEC strikes do not count against REVIEW" "REVIEW 001-a"

floor p_strike_prefix2; spec 001-a
strike 001-a REVIEW 3
pk "REVIEW strikes do not count against REVIEW-SPEC" "REVIEW-SPEC 001-a"

floor p_dirty; draft 001-a; dirty
pk "a dirty tree is RECOVER" "RECOVER"

floor p_dirty_empty; dirty
pk "a dirty tree beats FINISH" "RECOVER"

floor p_strike; draft 001-a; draft 002-b
strike 001-a SPECIFY 1
pk "the less-struck draft wins" "SPECIFY 002-b"

floor p_blocked; draft 001-a
strike 001-a SPECIFY 3
pk "a leftover at the limit is RECOVER, not FINISH" "RECOVER"

floor p_orphan; plan_bare 001-a
pk "an orphan overview is RECOVER, not FINISH" "RECOVER"

floor p_untracked_file; draft 001-a
jq 'del(.slugs["001-a"])' "$FIXTURE/.spectomat/state.json" > "$FIXTURE/.spectomat/state.json.tmp" && mv "$FIXTURE/.spectomat/state.json.tmp" "$FIXTURE/.spectomat/state.json"
pk "a floor file with no state.json entry is RECOVER" "RECOVER"

floor p_pure; spec 001-a; plan 001-a 2 1
before=$(cd "$FIXTURE" && find .spectomat -type f -exec cksum {} \; | sort; cd "$FIXTURE" && git status --porcelain)
pk "the picker still says IMPLEMENT" "IMPLEMENT 001-a"
after=$(cd "$FIXTURE" && find .spectomat -type f -exec cksum {} \; | sort; cd "$FIXTURE" && git status --porcelain)
is "the picker mutates nothing" "$after" "$before"

finish
