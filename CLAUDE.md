# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

A Claude Code plugin, not an application: bash scripts, Markdown commands, templates and reference files. No dependencies, no build, no tests of its own. `jq` and `perl` must be on PATH. `README.md` covers layout and licensing; `templates/guide.md` is the user guide (printed by `/spectomat:help`) and holds the glossary whose terms (flow, loop, phase, wave, floor, contract, slug, strike) this repo uses consistently. Use those words, not synonyms.

## Verifying changes

```bash
claude plugin validate .claude-plugin/plugin.json --strict      # run from this directory
claude plugin validate .claude-plugin/marketplace.json --strict
bash -n scripts/*.sh                                             # syntax only
```

Exercise the scripts in a scratch git repo, never here: `run.sh` on an empty floor must refuse, with a draft it must arm; pipe a fake Stop payload (`{"session_id","transcript_path"}`) into `scripts/stop-hook.sh` and check `decision`, the `loop:` counter, and that the state file disappears on `<promise>FACTORY EMPTY</promise>` and at the cap. `scripts/gates.sh` run inside any repo prints the gate command it would compile there.

The installed plugin is a cache copy under `~/.claude/plugins/cache/spectomat/`, so edits here are not live until the version in `.claude-plugin/plugin.json` is bumped and the plugin reinstalled. A project with an active flow then needs `/spectomat:cancel` and `/spectomat:run` again.

## How the pieces fit

Each command in `commands/` runs a script in its `!` block, then tells Claude what to do with the output. All scripts source `scripts/utils.sh` (paths, `cd_root`, `state_field`, `render_template`) and set their own `set -e/-u` options; bash 3.2 compatible, no GNU-only flags.

`run.sh` prepares the floor `.spectomat/` in the user's project: moves `wishlist/*.md` into `drafts/` as `NNN-<name>.md` in modification order with the counter in `.inc`, renders `contract.md` and `memory.md` once (never overwritten afterwards, each checked on its own so an older floor picks up a newly added file), commits what it created, then renders the state file from `templates/state.md` on every run and refuses if a state file already exists or the floor is empty.

The three rendered files split what they carry on purpose:

- `contract.md` is committed in the project and contains no plugin path. It names references by short name and says when to run the gates; project-specific gate commands live in its Verification Gates block.
- `memory.md` is committed in the project and belongs to it after the first render: durable facts about *the codebase*, where the contract holds rules about *the job*. Every loop reads it in Orient and adds to it inside the phase commit — never after, or the next loop starts on a dirty tree. Implementers and reviewers read it; only the loop agent writes it, so it keeps one voice. Its rules live in the contract's Memory section and the template's header; keep the two in step.
- `state.md` is gitignored and re-rendered each run. Its frontmatter (`loop`, `max_loops`, `session_id`) drives the Stop hook; its body is the pointer prompt, which carries `REFS` (absolute `references/` path) and `GATES` (one `&&` chain compiled by `gates.sh` from `package.json` scripts, or an echo when none).

`hooks/hooks.json` wires `scripts/stop-hook.sh`: while the state file exists for the session that started it (session id match, so other sessions in the same project are untouched), it blocks exit, bumps `loop:` and feeds the pointer back. The pointer makes the session launch one fresh `general-purpose` subagent per loop; the session itself does no factory work. The hook releases on the exact promise, the cap or a corrupt file. Derived from Anthropic's ralph-loop; the state file name differs so both plugins coexist.

`references/` are plain instruction files, deliberately not skills: skills would appear in every session's skill list. `writing-specs`, `writing-plans` and `executing-tasks` point at `templates/spec.md`, `plan.md` and `task.md`; `executing-tasks` sends `prompts/implementer.md` and `prompts/reviewer.md` verbatim to subagents. The last four references are condensed from superpowers, see `NOTICE.md`; keep them short and free of questions to a human, and keep every cross-reference between them pointing at a file that exists.

## Conventions

- Markdown paragraphs and list items are one line each, no hard wraps. Fenced blocks, tables and frontmatter are the only multi-line structures.
- Placeholders in templates are `{{KEY}}`, substituted literally by `render_template`; a new placeholder needs a value in the matching `render_template` call in `run.sh`.
- Third-party material and its licence go in `NOTICE.md`; changes to derived files are listed there.
- A change to the state file keys or the pointer text must keep `stop-hook.sh`, `print.sh`, `cancel.sh` and `templates/state.md` in step.
