# Contributing

Thank you for taking an interest. Spectomat is a Claude Code plugin, not an application: bash scripts, Markdown commands, agent briefs and templates. There are no dependencies and no build.

## Before you start

Read these in order. They are short, and they carry the vocabulary the rest of the repo assumes.

| File | What it is |
| --- | --- |
| [`references/glossary.md`](references/glossary.md) | The terms — flow, iteration, phase, task, floor, contract, slug, strike. Use these words, not synonyms. |
| [`docs/guide.md`](docs/guide.md) | The user guide, printed together with the glossary by `/spectomat:help`. |
| [`docs/specification.md`](docs/specification.md) | The normative spec: domain model, algorithms in pseudocode, and §8's table of design decisions already taken and rejected. |
| [`references/file-structure.md`](references/file-structure.md) | The plugin anatomy — what lives where. |

Check §8 of the specification before proposing a change. It records what was rejected and why.

## Requirements

- `bash` 3.2 or later — the scripts target macOS's bash, so no GNU-only flags.
- `jq` on `PATH`.
- `git`.
- Claude Code, for `claude plugin validate` and for exercising a real flow.

## Verifying a change

Run all four from the repository root.

```bash
claude plugin validate .claude-plugin/plugin.json --strict
claude plugin validate .claude-plugin/marketplace.json --strict
bash -n scripts/*.sh tests/*.sh templates/gates.sh       # syntax only
scripts/selftest.sh                                      # the full suite
```

`scripts/selftest.sh` runs every `tests/*_test.sh` file and reports the combined tally. The whole suite finishes in under eight seconds.

Each file under `tests/` is one section, owns its fixtures through the shared harness in `tests/lib.sh`, and runs alone:

```bash
bash tests/phase_test.sh        # just the picker
bash tests/archive_test.sh      # just the archiver
```

An optional `DIR` argument — to `scripts/selftest.sh` or to any one test file — points the run at a different `scripts/` copy, such as the installed cache under `~/.claude/plugins/cache/spectomat/`.

What the suite cannot cover is the live runtime. **Exercise a real flow in a scratch git repository, never in this checkout.** A phase agent is confined to the project under flow; one that reaches into this repository is a bug in the contract, and running a flow here invites exactly that.

`scripts/gates.sh` run inside any repository prints the gate command it would compile there.

## Testing the installed plugin

The installed plugin is a cache copy under `~/.claude/plugins/cache/spectomat/`. Edits here are not live until the version in `.claude-plugin/plugin.json` is bumped and the plugin reinstalled. A project with an active flow then needs `/spectomat:cancel` and `/spectomat:run` again. Restart Claude Code after an install or update — a live session keeps the old copy.

```bash
claude plugin marketplace add ~/Projects/spectomat
claude plugin install spectomat@spectomat
claude plugin update spectomat@spectomat
```

## Conventions

These are enforced by review, not by a linter.

- Markdown paragraphs and list items are one line each, no hard wraps. Fenced blocks, tables and frontmatter are the only multi-line structures.
- Plain English, B2 or above. Neutral tone, no rare words.
- Prefer formal definitions over prose, and structured content — sections, lists, tables — over paragraphs.
- Placeholders in templates are `{{KEY}}`, substituted literally by `render_template`. A new placeholder needs a value in the matching `render_template` call in `scripts/command-run.sh`.
- Verdicts are upper case (`SPECIFY`, `REVIEW-SPEC`, `PLAN`, `IMPLEMENT`, `REVIEW`, `ARCHIVE`, `RECOVER`, `FINISH`). Agent types and brief files are lower case (`spectomat:review-spec`, `agents/review-spec.md`).
- A change to the verdict grammar must keep `scripts/phase.sh`, `pointer_prompt` in `scripts/utils.sh`, `scripts/print.sh` and `scripts/agent-archive.sh` in step.
- A rule that binds every phase belongs in `templates/contract.md`'s Constitution and nowhere else, under one of its five groups — Judgement, What you may write, Honest reporting, Ending a phase, Where you work. A brief's Rules list holds only what is true of that one phase. A rule that would read the same in two briefs is a contract rule: move it rather than repeating it.
- A change to what a phase does belongs in its brief, not in the contract or the pointer.
- Behaviour changes belong in `docs/specification.md`, not only in the prose of `CLAUDE.md`.

## Commits and pull requests

- Conventional commits: `feat:`, `fix:`, `refactor:`, `docs:`, `style:`, `test:`, `chore:`. A scope is welcome — `feat(flow): …`.
- One concern per pull request.
- Fill in the pull request template's checklists honestly. A failing check stated plainly is more useful than a green box.

## Third-party material

Material taken from another project goes in `NOTICE.md` with its licence, and the licence text goes in the repository root as `LICENSE-<project>`. List the derived files there too.

## Licence

By contributing you agree that your contribution is licensed under the MIT License, as in [`LICENSE`](LICENSE).
