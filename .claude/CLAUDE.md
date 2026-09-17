# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

A Claude Code plugin, not an application: bash scripts, Markdown commands, agent briefs and templates. No dependencies and no build; `tests/*.sh` covers the text helpers in `utils.sh`, everything else is exercised by hand. `jq` must be on PATH. `README.md` covers layout and licensing; `docs/guide.md` is the user guide (printed by `/spectomat:help`) and holds the glossary whose terms (flow, iteration, phase, task, floor, contract, slug, strike) this repo uses consistently. Use those words, not synonyms. `docs/specification.md` is the normative spec behind all of this — domain model, the `pick_phase`/`least_struck`/`strike_count`/`gate_block`/`archive` algorithms in pseudocode, and the design-decisions table (§8) recording what was rejected and why; read it before changing behaviour that this file only summarizes in prose. `docs/brainstorm.md` is the REVIEW-SPEC phase's brainstorming procedure, referenced (not inlined) from `agents/review-spec.md` when the spec and draft are both silent.

## Verifying changes

```bash
claude plugin validate .claude-plugin/plugin.json --strict      # run from this directory
claude plugin validate .claude-plugin/marketplace.json --strict
bash -n scripts/*.sh tests/*.sh                          # syntax only
scripts/selftest.sh                                              # utils.sh, picker, archiver, prepare.sh, Stop hook
```

`scripts/selftest.sh` runs every `tests/*_test.sh` file and reports the combined tally — the picker, the archiver, `prepare.sh` arming and refusing, and the Stop hook driven with a fabricated `{session_id}` payload. What it cannot cover is the live runtime: exercise a real flow in a scratch git repo, never here. `scripts/gates.sh` run inside any repo prints the gate command it would compile there.

Each file under `tests/` is one section (`phase_test.sh`, `archive_test.sh`, `prepare_test.sh`, …), owns its own fixtures via the shared harness in `tests/lib.sh`, and is independently runnable and selectable: `bash tests/phase_test.sh` drives just the picker. Within a file, assertions are still one linear script of `is NAME GOT WANT` calls, printing `ok`/`FAIL` per assertion; the whole suite runs top to bottom in under 8 seconds. An optional `DIR` argument — to `scripts/selftest.sh` or to any one `tests/*_test.sh` file — points the run at a different `scripts/` copy — the installed cache under `~/.claude/plugins/cache/spectomat/`, for instance — instead of the one next to it.

The installed plugin is a cache copy under `~/.claude/plugins/cache/spectomat/`, so edits here are not live until the version in `.claude-plugin/plugin.json` is bumped and the plugin reinstalled. A project with an active flow then needs `/spectomat:cancel` and `/spectomat:run` again.

## How the pieces fit

Each command in `commands/` runs a script in its `!` block, then tells Claude what to do with the output. All scripts source `scripts/utils.sh` (paths, `cd_root`, `state_field`, `render_template`) and set their own `set -e/-u` options; bash 3.2 compatible, no GNU-only flags.

`prepare.sh` sets up the floor `.spectomat/` in the user's project: renders `contract.md` and `memory.md` once (never overwritten afterwards, each checked on its own so an older floor picks up a newly added file), commits what it created plus whatever drafts the user dropped into `drafts/`, then arms the flow on every run by writing `state.json`, and refuses if a flow is already active or the floor is empty — a `state.json` left behind by `/spectomat:cancel` has `active: false`, and arming over it resumes the flow with its slug progress intact. There is no intake: the operator names the drafts and the picker works them in alphabetical order (D13). Arming must end on a clean tree: the picker reads `git status` and answers `RECOVER` to any dirt, so an unstaged leftover costs the flow its first iteration.

`docs/floor.md` covers the floor's persistent files in full — what each one carries and why, the pointer prompt, the Stop hook wiring, and how each phase writes its own transition into `state.json`.

## Conventions

- Markdown paragraphs and list items are one line each, no hard wraps. Fenced blocks, tables and frontmatter are the only multi-line structures.
- Placeholders in templates are `{{KEY}}`, substituted literally by `render_template`; a new placeholder needs a value in the matching `render_template` call in `prepare.sh`.
- Whatever `{{GATES}}` renders into the contract lands inside a runnable `bash` block, so it must be a real command whose exit code means what it says. A repo with no gates detected gets an honest no-op (`echo "ok: …"`), never an `echo "❌ …"` that prints failure and exits 0. The `#`-comment form belongs only to `gates.sh`'s own stdout, which is read by people and never executed.
- A phase agent is confined to the project under flow. It must never `git stash`, commit or checkout in another repository — including this plugin's own checkout — and must never ask its caller to run a command a permission check denied it. Both were observed in a live run: an `ARCHIVE` agent stashed the operator's uncommitted template edits here to get past `archive.sh`'s dirty-tree guard, then asked the caller to run the blocked script. The rules live in `templates/contract.md`'s Constraints (binding every phase) and, for the denial case, in `agents/archive.md`.
- Third-party material and its licence go in `NOTICE.md`; changes to derived files are listed there.
- Verdicts are upper case (`SPECIFY`, `REVIEW-SPEC`, `PLAN`, `IMPLEMENT`, `REVIEW`, `ARCHIVE`, `RECOVER`, `FINISH`); the agent types and brief files that serve them are lower case (`spectomat:review-spec`, `agents/review-spec.md`), and the pointer lowercases the verdict's first word to bridge the two.
- A change to the verdict grammar must keep `phase.sh`, `pointer_prompt` in `utils.sh`, `print.sh` and `archive.sh` in step; a change to what a phase does belongs in its brief, not in the contract or the pointer.
