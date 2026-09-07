---
description: "Start the loop that plans once, then builds one ledger item per iteration from the spec"
argument-hint: "[max-iterations]  (default 30)"
allowed-tools: ["Bash", "Read", "Write", "Edit", "Grep", "Glob", "Task", "Skill"]
---

# Spectomat build

Preflight and loop start (already run):

```!
"${CLAUDE_PLUGIN_ROOT}/scripts/start-loop.sh" $ARGUMENTS
```

If the output ends in `❌ Not starting`, report what is missing and stop. The
loop must not begin on a prompt with `<!-- EDIT` placeholders, a missing spec,
or an already active loop.

If the output says the loop is armed, begin iteration 1 now: follow the prompt
printed at the end of the output. The Stop hook feeds that same prompt back
each time you finish an iteration, until you output `<promise>DONE</promise>`
or the iteration cap is reached.

**Do not output a false promise to escape the loop.** Emit it only when every
condition of the Completion Gate in `ralph-loop-prompt.md` is true and you
have seen the evidence this iteration.

## What this does

Phase 0 dispatches parallel read-only agents over the spec, runs
`superpowers:writing-plans` on their reports, and writes the ledger to
`.claude/build-ledger.local.md`. Every later iteration takes one ledger item,
writes its test first, implements, verifies, commits, and records — through
foundations, the build phases the spec's build sequence gives, cross-cutting
work, code review, acceptance, `README.md` and `CLAUDE.md`, and the completion
gate.

The pointer prompt is one line on purpose. The real loop spec lives in
`ralph-loop-prompt.md`, re-read every iteration, so edits between iterations
take effect without restarting the loop.

## Operating it

- **Watch progress:** `/spectomat:status`
- **Steer it:** edit the ledger between iterations — reorder items, add one,
  strike one out. The next iteration reads it fresh.
- **Change the rules:** edit `ralph-loop-prompt.md`.
- **Change the product:** edit the spec, then add a ledger item for what that
  change implies. The loop will not re-plan on its own.
- **Resume:** if the iteration cap is hit, run `/spectomat:build` again. The
  ledger survives, so the loop picks up where it stopped rather than re-planning.
- **Stop early:** `/spectomat:cancel`.
