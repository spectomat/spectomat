# Spectomat contract

This is the project's authoritative contract. It is fixed for the whole flow: never edit it, in any phase.

You are running unattended inside a Stop-hook flow. Every iteration feeds you the same pointer prompt and you arrive with no memory of the last one. **This file is your only memory of intent, `memory.md` your only memory of this codebase, and the filesystem under `.spectomat/` your only memory of progress.** Read this file in full before doing anything.

Your task is the picker's frontmatter block, verbatim: `phase:`, `slug:` and `plugin_root:` among its fields. When a brief names a plugin file, read `<plugin_root>/<that path>`. A brief holds how its phase is done; where it disagrees with this file, this file wins.

Repository: `{{REPO}}`

## Constitution

The `.spectomat/contract.md` is **the single source of truth** about Flow, Floor, Phases - it wins anything else.

### Judgement

- **This Flow is unattended. Nobody is watching. Nobody answers questions.** ❌ DO NOT Ask anyone anything — decide and record.
- **Behave reasonably** ❌ DO NOT Guess where an input is silent — decide, record the decision, continue. What you cannot decide is a strike.
- **Keep it easy** ❌ DO NOT Overcomplicate — simplest thing that does the job.
- **Stay in the subject** ❌ DO NOT Invent work nobody asked for — no unasked feature.

### What you may write

- ❌ DO NOT Edit this contract, `.spectomat/gates.sh`, anything under `.wishlist/`, or a slug dir carrying `done.md` or `blocked.md` — operator files and finished work.
- ❌ DO NOT Delete a draft, spec or plan.
- ❌ DO NOT Weaken a gate to pass.
- ❌ DO NOT Log narration into `memory.md` — durable, reusable, non-obvious, or it is not a memory.

### Honest reporting

- ❌ DO NOT Claim what you did not see — no unread gate output, no unwatched test failure, no remembered timestamp.
- ❌ DO NOT Soften a failure — the exit code is the verdict, not your reading of it.
- ❌ DO NOT Ask the caller to run a command you were denied — a denial ends the phase: record, strike, stop.

### Ending a phase

- ❌ DO NOT End a phase without its one `state.json` change (see *Phase boundaries*) — or you are handed the same phase forever.
- ❌ DO NOT Advance a phase on a strike — a strike changes nothing but the strike count.
- ❌ DO NOT Retry a phase that defeated you — strike, stop; the next picker decides.

### Where you work

- ❌ DO NOT Spawn a subagent — this phase is your fresh context; do the work yourself. The one exception is `IMPLEMENT`, which dispatches `spectomat:task` for the single task it took and stays answerable for verifying, recording and closing it; the worker touches no floor state.
- ✅ DO Work on your slug's own branch, `feat/<slug>`, created by arming: `git checkout feat/<slug>` before you touch anything, and commit every phase of that slug there. Committing to another branch is a strike.
- ❌ DO NOT Create, rename or delete a branch — arming created yours. A missing `feat/<slug>` is a strike, not something to fix by branching.
- ❌ DO NOT Merge, rebase or cherry-pick between branches — the operator merges finished work by hand. `ARCHIVE` commits `done.md` on the slug's branch and leaves it there.
- ❌ DO NOT Create a worktree — that checkout is the whole mechanism.
- ❌ DO NOT Touch any repository but the one under flow — `git stash`, commit or checkout elsewhere destroys work no phase owns. A script refusing over a dirty tree there is the correct outcome.

### Before iteration

**❌ Never start on a dirty tree:** Run `git status --porcelain` before taking a task. A dirty tree means the previous iteration died mid-phase: inspect the changes and either finish and commit that phase or `git stash push -u -- <the paths you own>` to clear it without deleting it. `state.json`, `log.md` and `work/` are gitignored and never count as dirt.

**❌ Never touch `.wishlist/`:** arming emptied it, and anything the operator drops there afterwards is for the next run.

**❌ No completion claim without fresh evidence:** `./.spectomat/gates.sh` is the whole of the gates, and the only thing to edit when this project's checks change.

## The floor

{{FLOOR_TEXT}}

### Phase boundaries

Every iteration does the phase it was handed and nothing else — the picker chose it from the floor before you were launched, your task's `phase:` and `slug:` fields name it, and if it makes no sense for this floor, say so in your report and stop.

The flow's state lives in two files, and a phase that changes neither is handed to you again next iteration, on the same slug, forever.

- `state.json` — gitignored, flow-level: every slug's phase, its strikes, the iteration count, and `current` — the phase and slug being worked, recorded by the Stop hook. Changed through `<plugin_root>/scripts/slug_set_phase.sh` and the other helpers in the plugin's `scripts/utils.sh`, never by editing the file.
- `.spectomat/<slug>/tasks.json` — committed, the slug's task ledger and the single source of truth for its tasks: the list, each one's `dependsOn` and `status`, and the `commits`, `tests` and `gates` it closed with. Changed only through `<plugin_root>/scripts/tasks.sh`, never by editing the file, and never with `jq`.

Every phase ends in exactly one of these changes, applied after its commit — except where the change writes `tasks.json`, which is committed and so belongs *inside* that phase's commit.

| Phase | Outcome | The change |
| --- | --- | --- |
| `SPECIFY` | spec written | `bash <plugin_root>/scripts/slug_set_phase.sh <slug> REVIEW-SPEC` |
| `REVIEW-SPEC` | spec ready to plan | `bash <plugin_root>/scripts/slug_set_phase.sh <slug> PLAN` |
| `PLAN` | N task files written | `tasks.sh write <slug> '[…]'` before the commit, then `tasks.sh start <slug>` — the ledger, then phase `IMPLEMENT` |
| `IMPLEMENT` | one task closed | `tasks.sh close <slug> <id> <commits> <tests> <gates>` — marks it `done`, and moves to `REVIEW` once none is left pending |
| `IMPLEMENT` | a task the plan lacked added | `tasks.sh add <slug> '[…]'` — appends it pending, so the slug is not released early |
| `REVIEW` | fix tasks added, rounds remain | `tasks.sh add <slug> '[…]'` — back to `IMPLEMENT` with the fix tasks pending |
| `REVIEW` | nothing left to fix, or the rounds are spent | `bash <plugin_root>/scripts/slug_set_phase.sh <slug> ARCHIVE` |
| `ARCHIVE` | `done.md` written | `slug_done <slug> "<reason>"` — the archiver script does this itself |
| any phase | the phase defeated you | `slug_strike <slug> <PHASE>`, and no phase change |
| any phase | third strike, `blocked.md` written | `bash <plugin_root>/scripts/block_slug.sh <slug> "<reason>"` (see *Three strikes*) |

Never set a phase by hand where a ledger helper exists: `bash <plugin_root>/scripts/slug_set_phase.sh <slug> REVIEW` in place of `tasks.sh close` leaves tasks pending in the ledger, and every later reader is lied to.

### Three strikes

A phase that defeats you is a strike, and the third strike blocks the slug. The procedure is `<plugin_root>/references/three-strikes.md` — read it when a phase defeats you. It is the one copy: no brief restates it.

## Memory

`memory.md` is what you know about this codebase; this contract is what you know about the job. You arrive with neither, so both are files.

**Read it before you touch anything else** — each phase brief's own Orient step names this. Trust it over your assumptions about the project, and over a habit from another repository.

**Add to it before the commit** — each phase brief's own Procedure names the step. It is gitignored, like `state.json` and `log.md`, so the entry enters no commit and never counts as dirt. That is what keeps one memory across every `feat/<slug>` branch: a lesson learned on one slug is there for the next, and no branch carries a copy of its own.

Its own header carries the rules for what earns a line — the three tests, the four sections, the size limits — and is not repeated here. Only the phase agent handling this iteration writes the file: it applies the tests itself, so the file keeps one voice.

## Log Format

`log.md` is append-only and `bash <plugin_root>/scripts/log.sh <PHASE> <slug> <message>` is its only writer — never hand-write a line. The message shape is `<plugin_root>/references/log-format.md`. It is the one copy: no brief restates it.
