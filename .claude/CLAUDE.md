# CLAUDE.md

A Claude Code plugin, not an application. No dependencies, no build.

## Layout

- `.claude-plugin/` — `plugin.json` (the plugin) and `marketplace.json` (this repo as a one-plugin marketplace, source `./`).
- `commands/` — `/spectomat:run`, `status`, `cancel`. Each `!` block runs a script before Claude reads the command.
- `hooks/` — `hooks.json` registers the Stop hook; the hook itself is `scripts/stop-hook.sh`, which keeps the loop alive.
- `scripts/` — bash, no other runtime. `run.sh` prepares `docs/.spectomat/`, renders `factory.md`, and writes the state file with the factory prompt and promise `FACTORY EMPTY`; `status.sh` summarises loop and floor.
- `skills/` — `writing-specs` (spec shape), `writing-plans` (unit B), `executing-tasks` (unit C; folds superpowers' subagent-driven development and code review), `test-driven-development`, `systematic-debugging`, `verification-before-completion`. The last five are condensed from superpowers 6.3.0 for an unattended loop: keep them short, free of questions to a human, and keep every `spectomat:<name>` reference resolvable to a directory here.
- `templates/` — `factory.md` (placeholders `{{REPO}}`, `{{GATES}}`), `spec.md` (the skeleton `writing-specs` points at) and `plan.md` (the skeleton `writing-plans` points at, placeholder `{{SLUG}}`).

## Verify

```bash
claude plugin validate .claude-plugin/plugin.json --strict
claude plugin validate .claude-plugin/marketplace.json --strict
```

Exercise the scripts in a scratch git repo, never in this one: `run.sh` on an empty floor (expect refusal), drop a draft and run again (expect armed), then pipe a fake hook payload (`{"session_id","transcript_path"}`) into `scripts/stop-hook.sh` and check `decision`, the iteration counter, and that the state file is removed on `<promise>FACTORY EMPTY</promise>` and at the cap.

## Rules

- The state file is `docs/.spectomat/loop.md`. Never rename it to ralph-loop's: both plugins can be installed, and their Stop hooks must not act on the same file.
- `factory.md` is copied whole into user projects. A template change reaches only floors created after it.
- Keep the pointer prompt in `run.sh` one line; the loop contract lives in the rendered `factory.md`.
