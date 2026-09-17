# Spectomat contract

This is the project's authoritative contract and may have been edited since the last iteration

You are running unattended inside a Stop-hook flow. Every iteration feeds you the same pointer prompt and you arrive with no memory of the last one. **This file is your only memory of intent, `memory.md` your only memory of this codebase, and the filesystem under `.spectomat/` your only memory of progress.** Read this file in full before doing anything.

Your task is the picker's frontmatter block, verbatim: `phase:`, `slug:` and `plugin_root:` among its fields. When a brief names a plugin file, read `<plugin_root>/<that path>`. A brief holds how its phase is done; where it disagrees with this file, this file wins.

Repository: `{{REPO}}`

## Constitution

The `.spectomat/contract.md` is **the single source of truth** about Flow, Floor, Phases - it wins anything else.

**This Flow is unattended. Nobody is watching. Never ask a question. Nobody answers questions.** Where an input is silent, decide, record the decisions, and continue.

## The floor

{{FLOOR_TEXT}}

## The Iteration Contract

Every iteration, in order:

1. **Orient.** Read this file, then `memory.md`. Run `git status --porcelain`. If the tree is dirty, the previous iteration died mid-phase: inspect the changes and either finish and commit that phase or `git checkout -- .` and `git clean -fd` the paths you own. Check `state.json`, `log.md` and `work/` are gitignored and never count as dirt. Never start a phase on a dirty tree. Never touch `drafts/` files except to move them.
2. **Do the phase you were handed.** The picker chose it from the floor before you were launched; your task's `phase:` and `slug:` fields name it. Never do a second phase, and never substitute a different one — if the phase makes no sense for this floor, say so in your report and stop.
3. **Verify** with the gates — once per task in the `IMPLEMENT` phase, once before the commit in the `ARCHIVE` phase; the `SPECIFY`, `REVIEW-SPEC`, `PLAN` and `REVIEW` phases write no code and skip them,
4. **Record and commit** — add what you learned to `memory.md` (see *Memory*), then one commit per phase, `<type>(<slug>): <what changed>`, with the memory edit inside it.
5. **Log** one line to `log.md`, then stop the iteration. The log is gitignored and never enters a commit; write it after the commit, once the phase is on record. In the `IMPLEMENT` phase the task's result entry is one `chore(<slug>): …` commit after the task commit.

> Work in progress always wins: a started plan is finished and archived before the next spec is planned, every reviewed spec is planned before the next spec is reviewed, and every spec is reviewed before the next draft is read. New drafts wait until the floor ahead of them is clear.

### Phase boundaries

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
| `ARCHIVE` | trail moved to `done/` | `slug_delete <slug>` — the archiver script does this itself |
| any phase | the phase defeated you | `slug_strike <slug> <PHASE>`, and no phase change |
| any phase | third strike, file moved to `done/` | `slug_delete <slug>` (see *Three strikes*) |

Never set a phase by hand where a counter helper exists: `bash <plugin_root>/scripts/slug_set_phase.sh <slug> REVIEW` in place of `slug_task_done` leaves `tasks_done` short, and every later reader of the counters is lied to.

### Three strikes

If a phase defeats you, append `(strike N)` to its log line and skip it next time by picking the following candidate in the same stage. On the third strike the slug is blocked: move the offending file to `done/` with the suffix `.blocked.md`, then drop the slug's entry from `state.json` with `scripts/utils.sh`'s `slug_delete <slug>`, log the reason, and continue. Both happen in the same iteration, the move first: an entry left in `state.json` with no floor file behind it makes the picker answer `RECOVER` to every iteration that follows, so a blocked slug that is not deleted blocks the whole flow. Never delete a draft, spec or plan.

## Verification Gates

Run every command in the block below from the repository root: once per task in the `IMPLEMENT` phase, before that task's commit, and once in the `ARCHIVE` phase before archiving. Every line must exit 0.

```bash
# project-specific gates, one command per line, You may change it
{{GATES}}
```

No completion claim without fresh evidence. A gate that has not run this iteration has not passed; a partial run does not stand for the whole.

## Memory

`memory.md` is what you know about this codebase; this contract is what you know about the job. You arrive with neither, so both are files.

**Read it in Orient, every iteration, before you touch anything else.** Trust it over your assumptions about the project, and over a habit from another repository.

**Add to it in step 4, before the commit**, so the entry rides inside the phase commit and the tree stays clean.

Its own header carries the rules for what earns a line — the three tests, the four sections, the size limits — and is not repeated here. Only the phase agent handling this iteration writes the file: it applies the tests itself, so the file keeps one voice.

## Log Format

Append to `log.md`, never edit earlier lines. The timestamp is the output of `date -u +%FT%RZ`, run in this iteration — never a time typed from memory. No commit SHA: `git log` is the ledger of commits, this file the ledger of phases.

```text
- 2026-09-07T19:40Z · SPECIFY · <slug> · spec written, 3 assumptions
- 2026-09-07T19:46Z · REVIEW-SPEC · <slug> · 2 issues fixed in §3.2, §9.1 · 1 decision added
- 2026-09-07T19:52Z · IMPLEMENT · <slug> · Task 2/6 done · tests 41/41
- 2026-09-07T20:10Z · ARCHIVE · <slug> · moved to done · tsc 0, tests 58/58, lint 0
- 2026-09-07T20:11Z · PLAN · <slug> · plan: 6 tasks (strike 1: spec §4 contradicts §2)
```

Numbers, never adjectives. A log line without numbers did not run the gates.

## Constraints

- ❌ DO NOT Overcomplicate things: Be concise, simple and straightforward as possible.
- ❌ DO NOT Ask the user anything: Decide and record.
- ❌ DO NOT Edit a file under `drafts/` — only move it.
- ❌ DO NOT Delete a draft, spec or plan.
- ❌ DO NOT Weaken a gate to pass.
- ❌ DO NOT Log narration into `memory.md` — durable, reusable, non-obvious, or it is not a memory.
- ❌ DO NOT Spawn a subagent — each phase is already the fresh context it gets; do the work yourself.
- ❌ DO NOT Create a branch or worktree — every phase works on the current branch.
- ❌ DO NOT Touch any repository but the one under flow — not the plugin's own checkout, not a sibling project. `git stash`, commit or checkout outside this project destroys work no phase owns. A dirty tree elsewhere is never yours to clear; if a script refuses because of it, that refusal is the correct outcome.
- ❌ DO NOT Ask the caller to run a command you were denied — a denial ends the phase. Record it, log the strike, and stop; routing it upward launders a permission the operator withheld.
