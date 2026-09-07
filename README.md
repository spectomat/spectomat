# spectomat

Spec-driven dark factory for Claude Code. Drop ideas into a folder, run one
command, and an unattended loop turns each idea into a spec, each spec into a
plan, and each plan into tested, committed code. Carries condensed superpowers skills
(planning, TDD, review, verification) and a built-in Ralph-style Stop hook.

```
drafts/*.md  ──A──▶  specs/<slug>.md  ──B──▶  plans/<slug>.md  ──C×n──▶  code + commits  ──D──▶  done/
```

Distilled from the Telegator build (99 commits, 94 iterations, unattended).

## Requires

- `jq` and `perl` on PATH (the Stop hook uses them). No other plugin.

## Commands

| Command | Does |
| --- | --- |
| `/spectomat:run [n]` | prepares `docs/.spectomat/`, renders `factory.md`, arms the Stop hook (`n` iterations, default 100, promise `FACTORY EMPTY`) and starts iteration 1 |
| `/spectomat:status` | loop iteration, floor counts, per-plan step progress, blocked files, log tail |
| `/spectomat:cancel` | removes the loop state file; the floor stays, `run` resumes from it |

## The floor

```
docs/.spectomat/
  drafts/     ideas you drop in, one .md each — the file name becomes the slug
  specs/      written by unit A from each draft; or put a finished spec here yourself
  plans/      written by unit B from each spec
  done/       spec + plan moved here by unit D after every step is ticked and gates pass
  log.md      one line per unit
  factory.md  the rules, rendered once from templates/factory.md, re-read every iteration
  loop.md     the Stop hook's state, gitignored by run
  work/       per-task briefs, reports and diffs, gitignored
```

Each iteration does exactly one unit, the first that applies: **A** draft →
spec, **B** spec → plan, **C** plan → next task (fresh implementer subagent, reviewed diff, TDD, one task
per iteration), **D** finished plan → `done/`. Drafts win: nothing is built
while a draft remains. Nobody is asked anything; every open choice becomes an
`assumed` row in the spec's Decisions table. Three strikes moves a file to
`done/<slug>.blocked.md`. Gates are detected from `package.json` scripts
(`typecheck`, `test`, `lint`, `synth`) and can be edited in `factory.md`.

## Skills

| Skill | Use |
| --- | --- |
| `spectomat:writing-specs` | the shape a spec needs so code can cite it and tests can name its criteria |
| `spectomat:writing-plans` | unit B: bite-sized TDD tasks with checkbox steps, self-reviewed against the spec |
| `spectomat:executing-tasks` | unit C: brief, fresh implementer subagent, diff review, three fix rounds, rulings in the plan |
| `spectomat:test-driven-development` | every step: failing test first, minimal code, green suite |
| `spectomat:systematic-debugging` | any failing gate: root cause before fix |
| `spectomat:verification-before-completion` | every claim, commit and the promise: fresh evidence |

The last four are condensed from [superpowers](https://github.com/obra/superpowers) 6.3.0 (MIT, `LICENSE-superpowers`) to what the unattended loop needs; `executing-tasks` folds its subagent-driven development and code-review skills into one.

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
  commands/   run.md  status.md  cancel.md
  hooks/      hooks.json
  scripts/    run.sh  stop-hook.sh  status.sh
  skills/     writing-specs/  writing-plans/  executing-tasks/
              test-driven-development/  systematic-debugging/  verification-before-completion/
  templates/  factory.md  spec.md  plan.md
```

## Loop mechanics

The Stop hook (`scripts/stop-hook.sh`, wired by `hooks/hooks.json`, derived
from Anthropic's `ralph-loop` plugin, see `NOTICE.md`) runs when Claude tries
to end its turn. While `docs/.spectomat/loop.md` exists for this
session it blocks the exit and returns the pointer prompt as the next input. It
removes the file, and so releases the session, on
`<promise>FACTORY EMPTY</promise>`, on the iteration cap, or on a corrupt state
file. The state file name differs from ralph-loop's, so both plugins can be
installed side by side.
