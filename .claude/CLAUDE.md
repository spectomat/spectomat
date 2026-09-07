# CLAUDE.md

A Claude Code plugin, not an application. No dependencies, no build.

## Layout

- `.claude-plugin/` — `plugin.json` (the plugin) and `marketplace.json` (this repo as a one-plugin marketplace, source `./`).
- `commands/` — `/spectomat:init`, `build`, `status`, `cancel`. Each `!` block runs a script before Claude reads the command.
- `hooks/` — the Stop hook that keeps the loop alive. Derived from Anthropic's `ralph-loop`; see `NOTICE.md`.
- `scripts/` — bash, no other runtime. `init.sh` renders templates, `preflight.sh` reports readiness, `start-loop.sh` runs preflight then writes the state file, `status.sh` summarises the ledger.
- `skills/` — `spectomat` (the flow) and `writing-specs` (spec shape).
- `templates/` — `ralph-loop-prompt.md`, `spec.md`, `build-ledger.md`. Placeholders are `{{PROJECT}}`, `{{SPEC}}`, `{{SPEC_DIR}}`, `{{REPO}}`, `{{LEDGER}}`, `{{GATES}}`; project-specific blocks are `<!-- EDIT -->` comments.

## Verify

```bash
claude plugin validate .claude-plugin/plugin.json --strict
claude plugin validate .claude-plugin/marketplace.json --strict
```

Exercise the scripts in a scratch git repo, never in this one: `init.sh`, then `start-loop.sh` (expect NOT READY while `<!-- EDIT` blocks remain), then pipe a fake hook payload (`{"session_id","transcript_path"}`) into `hooks/stop-hook.sh` and check `decision`, the iteration counter, and that the state file is removed on `<promise>DONE</promise>` and at the cap.

## Rules

- The state file is `.claude/spectomat-loop.local.md`. Never rename it to ralph-loop's: both plugins can be installed, and their Stop hooks must not act on the same file.
- Templates are copied whole into user projects. A template change reaches only new `init` runs.
- Keep the pointer prompt in `start-loop.sh` one line; the loop spec lives in the rendered `ralph-loop-prompt.md`.
