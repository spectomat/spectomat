# Spectomat

[![CI](https://github.com/spectomat/spectomat/actions/workflows/ci.yml/badge.svg)](https://github.com/spectomat/spectomat/actions/workflows/ci.yml)
[![Licence: MIT](https://img.shields.io/badge/licence-MIT-blue.svg)](LICENSE)
[![Claude Code plugin](https://img.shields.io/badge/Claude%20Code-plugin-d97757.svg)](https://docs.claude.com/en/docs/claude-code/plugins)

Spec-driven code development flow for Claude Code.

Drop ideas into `.spectomat/drafts/`, call one `/spectomat:run` command, and an unattended flow turns each idea into a spec, each spec into a plan and tasks, and then executes all of them to produce well-tested, committed code.

> [User guide](docs/guide.md) is shown by `/spectomat:help`.

## Workflow

### Install

```bash
claude plugin marketplace add spectomat/spectomat
claude plugin install spectomat@spectomat
```

### Run

in a chat:

```text
just refer the word "spectomat" in your message
or explicitly call /spectomat:spectomat-run-new-draft
```

inside a project with a draft on the floor.

```bash
claude -p "/spectomat:run 25" --plugin-dir <this repo>
```

> Requires `jq` on PATH.

### Update

```bash
claude plugin update spectomat@spectomat
```

> Restart Claude Code to apply an install or update: the plugin runs from a cache copy, so a live session keeps the old one.

### Development

See [File structure](./references/file-structure.md) for the plugin anatomy, and [CONTRIBUTING.md](CONTRIBUTING.md) for the conventions and the full verification steps.

```bash
claude plugin marketplace add ~/Projects/spectomat # from a local machine
claude plugin install spectomat@spectomat
claude plugin update spectomat@spectomat
claude plugin validate .claude-plugin/plugin.json --strict
claude plugin validate .claude-plugin/marketplace.json --strict
scripts/selftest.sh
```

## Documentation

| File | What it is |
| --- | --- |
| [User guide](docs/guide.md) | How the flow works. Printed by `/spectomat:help`. |
| [Specification](docs/specification.md) | The normative spec: domain model, algorithms, design decisions. |
| [Glossary](references/glossary.md) | The terms — flow, iteration, phase, task, floor, contract, slug, strike. |
| [File structure](references/file-structure.md) | The plugin anatomy. |

## Contributing

Issues and pull requests are welcome. Read [CONTRIBUTING.md](CONTRIBUTING.md) first, and §8 of the specification, which records what was already rejected and why.

This project ships a [Code of Conduct](CODE_OF_CONDUCT.md). Security reports go through a [private advisory](https://github.com/spectomat/spectomat/security/advisories/new), never a public issue — see [SECURITY.md](SECURITY.md).

## Licence

MIT, see [`LICENSE`](LICENSE). Copyright © 2026 Alex Litskevich.

Third-party material and its licences are listed in [`NOTICE.md`](NOTICE.md).
