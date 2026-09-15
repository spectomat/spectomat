# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

A Claude Code plugin, not an application: bash scripts, Markdown commands, agent briefs and templates. No dependencies and no build; `scripts/tests/*.sh` covers the text helpers in `utils.sh`, everything else is exercised by hand. `jq` must be on PATH. `README.md` covers layout and licensing; `templates/guide.md` is the user guide (printed by `/spectomat:help`) and holds the glossary whose terms (flow, iteration, phase, task, floor, contract, slug, strike) this repo uses consistently. Use those words, not synonyms. `docs/spectomat.md` is the normative spec behind all of this — domain model, the `pick_phase`/`least_struck`/`strike_count`/`gate_block`/`archive` algorithms in pseudocode, and the design-decisions table (§8) recording what was rejected and why; read it before changing behaviour that this file only summarizes in prose.

## Verifying changes

```bash
claude plugin validate .claude-plugin/plugin.json --strict      # run from this directory
claude plugin validate .claude-plugin/marketplace.json --strict
bash -n scripts/*.sh scripts/tests/*.sh                          # syntax only
scripts/selftest.sh                                              # utils.sh, picker, archiver, prepare.sh, Stop hook
```

`scripts/selftest.sh` runs every `scripts/tests/*_test.sh` file and reports the combined tally — the picker, the archiver, `prepare.sh` arming and refusing, and the Stop hook driven with a fabricated `{"session_id","transcript_path"}` payload. What it cannot cover is the live runtime: exercise a real flow in a scratch git repo, never here. `scripts/gates.sh` run inside any repo prints the gate command it would compile there.

Each file under `scripts/tests/` is one section (`phase_test.sh`, `archive_test.sh`, `prepare_test.sh`, …), owns its own fixtures via the shared harness in `scripts/tests/lib.sh`, and is independently runnable and selectable: `bash scripts/tests/phase_test.sh` drives just the picker. Within a file, assertions are still one linear script of `is NAME GOT WANT` calls, printing `ok`/`FAIL` per assertion; the whole suite runs top to bottom in under 8 seconds. An optional `DIR` argument — to `scripts/selftest.sh` or to any one `scripts/tests/*_test.sh` file — points the run at a different `scripts/` copy — the installed cache under `~/.claude/plugins/cache/spectomat/`, for instance — instead of the one next to it.

The installed plugin is a cache copy under `~/.claude/plugins/cache/spectomat/`, so edits here are not live until the version in `.claude-plugin/plugin.json` is bumped and the plugin reinstalled. A project with an active flow then needs `/spectomat:cancel` and `/spectomat:run` again.

## How the pieces fit

Each command in `commands/` runs a script in its `!` block, then tells Claude what to do with the output. All scripts source `scripts/utils.sh` (paths, `cd_root`, `state_field`, `render_template`) and set their own `set -e/-u` options; bash 3.2 compatible, no GNU-only flags.

`prepare.sh` sets up the floor `.spectomat/` in the user's project: renders `contract.md` and `memory.md` once (never overwritten afterwards, each checked on its own so an older floor picks up a newly added file), commits what it created plus whatever drafts the user dropped into `drafts/`, then arms the flow on every run by writing `state.json` and rendering `templates/pointer.md`, and refuses if a flow is already active or the floor is empty — a `state.json` left behind by `/spectomat:cancel` has `active: false`, and arming over it resumes the flow with its slug progress intact. There is no intake: the operator names the drafts and the picker works them in alphabetical order (D13). Arming must end on a clean tree: the picker reads `git status` and answers `RECOVER` to any dirt, so an unstaged leftover costs the flow its first iteration.

The three rendered files split what they carry on purpose:

- `contract.md` is committed in the project and contains no plugin path: the invariants that outlive the briefs — floor, iteration steps, strikes, when to gate, log format, constraints — and the project's own gate commands in its Verification Gates block. It is rendered once and never overwritten, so it is the operator's only steering surface; craft that no operator would edit belongs in a brief, not here.
- `memory.md` is committed in the project and belongs to it after the first render: durable facts about *the codebase*, where the contract holds rules about *the job*. Every iteration reads it in Orient and adds to it inside the phase commit — never after, or the next iteration starts on a dirty tree. Every phase agent reads it; only the one handling that iteration writes it, so it keeps one voice. The rules for what earns a line live in `templates/memory.md`'s own header and nowhere else; the contract's Memory section says only when to read and write it.
- `state.json` and `pointer.md` are gitignored and re-rendered each run. `state.json` (`active`, `iteration`, `max_iterations`, `session_id`, `started_at`, and a `slugs` map of slug → `{phase, tasks_total, tasks_done, strikes}`) drives the Stop hook, is the armed flag, and is the single source of truth the picker reads to decide the next phase — the floor's files are only cross-checked against it (`check_orphans` in `phase.sh` answers `RECOVER` when the two disagree in either direction). Phase transitions go through the `slug_*` helpers in `utils.sh`, never by hand-editing the file; `pointer.md` is the prompt fed back each iteration and carries `PLUGIN_ROOT` (absolute plugin path, locating `agents/`). They are created and removed together — `disarm()` in `utils.sh` — because a pointer outliving its state would be fed back with no counter behind it. `GATES` (one `&&` chain compiled by `gates.sh` from `package.json` scripts, or an echo when none) is rendered into the contract.

`hooks/hooks.json` wires `scripts/stop-hook.sh`: while `state.json` exists for the session that started it (session id match, so other sessions in the same project are untouched), it blocks exit, bumps `iteration` with `jq` and feeds `pointer.md` back. The pointer dispatches to the picker (`scripts/phase.sh`): one verdict per iteration, one subagent every time — `spectomat:specify|review-spec|plan|implement|review|archive|finish`, or `spectomat:recover`. The session itself does no factory work. The phase briefs hold the craft of their phase; the contract holds the invariants. `spectomat:archive`'s brief invokes `scripts/archive.sh` and relays its result unchanged rather than doing any mutation itself, and `spectomat:finish`'s brief only composes the closing report — the session still emits the promise (D21 in `docs/spectomat.md`). Every phase ends by writing its own transition into `state.json` through a `slug_*` helper — `REVIEW-SPEC` calls `slug_set_phase` to release a spec to `PLAN`, `PLAN` calls `slug_start_tasks` to register the task count and open `IMPLEMENT`, `IMPLEMENT` calls `slug_task_done` per task and reaches `REVIEW` on the last one, and `REVIEW` calls either `slug_set_phase … ARCHIVE` or `slug_add_tasks` to send the plan back. `agents/recover.md` is the janitor, launched by the picker when the floor is dirty. Derived from Anthropic's ralph-loop; the state file name and format differ so both plugins coexist.

The craft of each phase lives in its brief; the invariants live in the contract.

## Conventions

- Markdown paragraphs and list items are one line each, no hard wraps. Fenced blocks, tables and frontmatter are the only multi-line structures.
- Placeholders in templates are `{{KEY}}`, substituted literally by `render_template`; a new placeholder needs a value in the matching `render_template` call in `prepare.sh`.
- Third-party material and its licence go in `NOTICE.md`; changes to derived files are listed there.
- Verdicts are upper case (`SPECIFY`, `REVIEW-SPEC`, `PLAN`, `IMPLEMENT`, `REVIEW`, `ARCHIVE`, `RECOVER`, `FINISH`); the agent types and brief files that serve them are lower case (`spectomat:review-spec`, `agents/review-spec.md`), and the pointer lowercases the verdict's first word to bridge the two.
- A change to the verdict grammar must keep `phase.sh`, `templates/pointer.md`, `print.sh` and `archive.sh` in step; a change to what a phase does belongs in its brief, not in the contract or the pointer.
