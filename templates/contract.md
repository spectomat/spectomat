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

- ❌ DO NOT Edit this contract, `.spectomat/gates.sh`, anything under `drafts/`, or a slug dir carrying `done.md` or `blocked.md` — operator files and finished work.
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

- ❌ DO NOT Spawn a subagent — this phase is your fresh context; do the work yourself.
- ❌ DO NOT Create a branch or worktree — every phase works on the current branch.
- ❌ DO NOT Touch any repository but the one under flow — `git stash`, commit or checkout elsewhere destroys work no phase owns. A script refusing over a dirty tree there is the correct outcome.

### Before iteration

**❌ Never start on a dirty tree**
Run `git status --porcelain` before taking a task. A dirty tree means the previous iteration died mid-phase: inspect the changes and either finish and commit that phase or `git checkout -- .` and `git clean -fd` the paths you own. `state.json`, `log.md` and `work/` are gitignored and never count as dirt.

**❌ Never touch `drafts/`**:
arming emptied it, and anything the operator drops there afterwards is for the next run.

**Always check gate before**:
`./.spectomat/gates.sh` is the whole of the gates, and the only thing to edit when this project's checks change.

**❌ No completion claim without fresh evidence**
a gate that has not run this iteration has not passed, and a partial run does not stand for the whole.

## The floor

{{FLOOR_TEXT}}

### Phase boundaries

Every iteration does the phase it was handed and nothing else — the picker chose it from the floor before you were launched, your task's `phase:` and `slug:` fields name it, and if it makes no sense for this floor, say so in your report and stop.

`state.json` is a progress tracker on what moves work along: a phase that changes nothing there is handed to you again next iteration, on the same slug, forever. Every phase ends in exactly one of these changes, applied after its commit through `<plugin_root>/scripts/slug_set_phase.sh` or the other helpers in the plugin's `scripts/utils.sh` — never by editing the file.

| Phase | Outcome | `state.json` change |
| --- | --- | --- |
| `SPECIFY` | spec written | `bash <plugin_root>/scripts/slug_set_phase.sh <slug> REVIEW-SPEC` |
| `REVIEW-SPEC` | spec ready to plan | `bash <plugin_root>/scripts/slug_set_phase.sh <slug> PLAN` |
| `PLAN` | N task files written | `slug_start_tasks <slug> N` — phase `IMPLEMENT`, `tasks_total` N, `tasks_done` 0 |
| `IMPLEMENT` | one task closed | `slug_task_done <slug>` — bumps `tasks_done`, and moves to `REVIEW` once it reaches `tasks_total` |
| `IMPLEMENT` | a task the plan lacked added | `slug_add_tasks <slug> 1` — raises `tasks_total` so the slug is not released early |
| `REVIEW` | fix tasks added, rounds remain | `slug_add_tasks <slug> N` — back to `IMPLEMENT` with `tasks_total` raised by N |
| `REVIEW` | nothing left to fix, or the rounds are spent | `bash <plugin_root>/scripts/slug_set_phase.sh <slug> ARCHIVE` |
| `ARCHIVE` | `done.md` written | `slug_finish <slug> done` — the archiver script does this itself |
| any phase | the phase defeated you | `slug_strike <slug> <PHASE>`, and no phase change |
| any phase | third strike, `blocked.md` written | `slug_finish <slug> blocked "<reason>"` (see *Three strikes*) |

Never set a phase by hand where a counter helper exists: `bash <plugin_root>/scripts/slug_set_phase.sh <slug> REVIEW` in place of `slug_task_done` leaves `tasks_done` short, and every later reader of the counters is lied to.

### Three strikes

If a phase defeats you, append `(strike N)` to its log line and skip it next time by picking the following candidate in the same stage. On the third strike the slug is blocked: write `.spectomat/<slug>/blocked.md` naming the phase and the reason, commit it, then call `scripts/utils.sh`'s `slug_finish <slug> blocked "<reason>"`, log the reason, and continue. Both happen in the same iteration, in that order: the state call is what takes the slug out of the flow, so a marker written without it leaves the slug at its phase with three strikes against it — the picker skips it, finds no other candidate, and sends every remaining iteration to the janitor; and writing the marker first keeps any commit from describing a state change that did not happen. The marker is the committed record — `state.json` is gitignored, so `blocked.md` is the only trace of how the slug ended that survives in git. Nothing moves and nothing is deleted — the trail stays in the slug dir for the operator to read.

## Memory

`memory.md` is what you know about this codebase; this contract is what you know about the job. You arrive with neither, so both are files.

**Read it before you touch anything else** — each phase brief's own Orient step names this. Trust it over your assumptions about the project, and over a habit from another repository.

**Add to it before the commit**, so the entry rides inside the phase commit and the tree stays clean — each phase brief's own Procedure names the step.

Its own header carries the rules for what earns a line — the three tests, the four sections, the size limits — and is not repeated here. Only the phase agent handling this iteration writes the file: it applies the tests itself, so the file keeps one voice.

## Log Format

`log.md` is append-only; never edit an earlier line. Its format is not yours to
compose: run `bash <plugin_root>/scripts/log.sh <PHASE> <slug> <message>` and it
writes the line — timestamp, `·` separators and all — deterministically. Never
`printf`, `echo >>` or otherwise hand-write a line into `log.md`; `log.sh` is
the only writer. No commit SHA in the message: `git log` is the ledger of
commits, this file the ledger of phases.

The message is numbers, never adjectives — `Task 2/6 done · tests 41/41`, not
"tests mostly passing". A log line without numbers did not run the gates. A
strike ends the message `(strike N: <reason>)`, N from `slug_strike`'s own
output, not counted by hand.
