# Spectomat

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
just refer the word `spectomat` in your message
 or explicitly call `/spectomat:spectomat-run-new-draft
```

inside a project with a draft on the floor.

```bash
claude -p "/spectomat:run 25" --plugin-dir <this repo>` 
```

> Requires `jq` on PATH.

### Update

```bash
claude plugin update spectomat@spectomat
```

> Restart Claude Code to apply an install or update: the plugin runs from a cache copy, so a live session keeps the old one.

### Development

See [File structure](./references/file-structure.md) for the plugin anatomy details.

```bash
claude plugin marketplace add ~/Projects/spectomat # from local mashine
claude plugin install spectomat@spectomat
claude plugin update spectomat@spectomat
claude plugin validate .claude-plugin/plugin.json --strict
claude plugin validate .claude-plugin/marketplace.json --strict
```

## Licence

MIT, see `LICENSE`.

Third-party material and its licences are listed in `NOTICE.md`.
