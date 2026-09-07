# spectomat

Spec-driven autonomous development for Claude Code. Combines `superpowers`
(brainstorming, planning, TDD, review, verification) with a built-in Ralph
loop (a Stop hook feeds the same prompt back until a true completion promise):

```
spec  ──/spectomat:init──▶  ralph-loop-prompt.md  ──/spectomat:build──▶  ledger + commits
```

Distilled from the Telegator build (99 commits, 94 iterations, unattended).

## Requires

- `superpowers` plugin
- `jq` and `perl` on PATH (the Stop hook uses them)

## Commands

| Command | Does |
| --- | --- |
| `/spectomat:init [name] [--spec path] [--force]` | writes `ralph-loop-prompt.md` from the template, a spec skeleton if absent, `.gitignore` entry for the ledger; then walks you through the `<!-- EDIT -->` blocks |
| `/spectomat:build [n]` | preflight, then arms the Stop hook (`n` iterations, default 30, promise `DONE`) |
| `/spectomat:cancel` | removes the loop state file; the ledger stays |
| `/spectomat:status` | ledger progress per phase, next item, blocked items, loop iteration |

## Skills

| Skill | Use |
| --- | --- |
| `spectomat:spectomat` | the flow, the three artefacts, which superpowers skill runs where |
| `spectomat:writing-specs` | the shape a spec needs so code can cite it and tests can name its criteria |

## Install

```bash
claude plugin marketplace add ~/Projects/spectomat
claude plugin install spectomat@spectomat
```

Then restart Claude Code.

## Layout

```
spectomat/
  .claude-plugin/  plugin.json  marketplace.json
  commands/   init.md  build.md  status.md  cancel.md
  hooks/      hooks.json  stop-hook.sh
  scripts/    init.sh  preflight.sh  start-loop.sh  status.sh
  skills/     spectomat/SKILL.md  writing-specs/SKILL.md
  templates/  ralph-loop-prompt.md  spec.md  build-ledger.md
```

## The three artefacts

| Artefact | Owner | Role |
| --- | --- | --- |
| `docs/<project>.md` | user | what to build; never edited by the loop |
| `ralph-loop-prompt.md` | user | how the loop runs; re-read every iteration |
| `.claude/build-ledger.local.md` | loop | progress memory; gitignored |

The prompt template is a full copy per project: edit it freely, nothing
propagates from the plugin after `init`. Re-run `init --force` to reset it.

## Loop mechanics

The Stop hook (`hooks/stop-hook.sh`, derived from Anthropic's `ralph-loop`
plugin, see `NOTICE.md`) runs when Claude tries to end its turn. While
`.claude/spectomat-loop.local.md` exists for this session it blocks the exit and
returns the pointer prompt as the next input. It removes the file, and so
releases the session, on `<promise>DONE</promise>`, on the iteration cap, or on
a corrupt state file. The state file name differs from ralph-loop's, so both
plugins can be installed side by side.
