# Spectomat

<img src="assets/logo.svg" alt="" width="88" align="right">

[![CI](https://github.com/spectomat/spectomat/actions/workflows/ci.yml/badge.svg)](https://github.com/spectomat/spectomat/actions/workflows/ci.yml)
[![Licence: MIT](https://img.shields.io/badge/licence-MIT-blue.svg)](LICENSE)
[![Claude Code plugin](https://img.shields.io/badge/Claude%20Code-plugin-d97757.svg)](https://docs.claude.com/en/docs/claude-code/plugins)

Spec-driven code development flow for Claude Code.

You drop ideas into `.wishlist/` and call one `/spectomat:run` command,
then an *unattended flow* turns each idea into a spec, each spec into a plan and tasks, and then executes all of them to produce well-tested, committed code.

## Workflow

### Install

```bash
claude plugin marketplace add spectomat/spectomat
claude plugin install spectomat@spectomat
```

> Requires `jq` and `git` on PATH.

### Usage

just express your wish in a chat mentioning `spectomat` keyword:

```text
use spectomat to do some marvelous things...
```

to start working on the next wish picked from the `.wishlist` folder
(if a unfinished flow exists - it will continue on it instead)

```text
/spectomat:run 25 
```

the same with CLI a project with a draft on the floor.

```bash
claude -p "/spectomat:run 25" --plugin-dir <this repo>
```

to disarm the current flow; the floor stays, `/spectomat:run` will resume from it

```text
/spectomat:cancel
```

to check the current flow status:

```text
/spectomat:status
```

to see the full [User guide](docs/guide.md).

```text
/spectomat:help
```

### Update

```bash
claude plugin update spectomat@spectomat
```

> Restart Claude Code to apply an install or update: the plugin runs from a cache copy, so a live session keeps the old one.

## Contributing

Issues and pull requests are welcome. Read [CONTRIBUTING.md](CONTRIBUTING.md) first, and [the design decisions](references/decisions.md), which record what was already rejected and why.

This project ships a [Code of Conduct](CODE_OF_CONDUCT.md). Security reports go through a [private advisory](https://github.com/spectomat/spectomat/security/advisories/new), never a public issue — see [SECURITY.md](SECURITY.md).

## Licence

MIT, see [`LICENSE`](LICENSE). Copyright © 2026 Alex Litskevich.

Third-party material and its licences are listed in [`NOTICE.md`](NOTICE.md).
