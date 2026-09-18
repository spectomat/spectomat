# Security policy

## Reporting a vulnerability

Report privately through [GitHub's private vulnerability reporting](https://github.com/spectomat/spectomat/security/advisories/new). Do not open a public issue.

Please include the plugin version, the phase involved if there is one, and the steps to reproduce.

Expect an acknowledgement within seven days. If a report is confirmed, a fix ships in a patch release and the advisory is published with credit, unless you prefer otherwise.

## Supported versions

The latest release only. Spectomat is pre-1.0 and no older line is maintained.

## What is in scope

Spectomat runs unattended agents with shell access inside your project. The interesting surface is anything that lets untrusted text reach a shell, or lets a phase act outside the project under flow.

- A phase agent writing, committing or checking out outside the project under flow — including into this plugin's own checkout.
- Shell injection through a draft, a spec, a slug name, a task file or any other content the flow reads.
- Path traversal out of `.spectomat/` through a slug or file name.
- `scripts/gates.sh` compiling a gate command from repository content in a way that executes something unintended.
- The Stop hook or a command script acting on a `state.json` it should have refused.
- Secrets written into `.spectomat/` files that are then committed.

## What is not in scope

- The behaviour of Claude Code itself, or of the model. Report those to [Anthropic](https://github.com/anthropics/claude-code/issues).
- Consequences of running the flow on a project you do not control, or with a `gates.sh` you did not review. `gates.sh` is rendered once into your project and never overwritten; it is yours, and it runs.
- The flow making changes you did not want. That is a correctness bug — open an issue.

## Operating advice

- Run the flow in a repository under version control, with a clean tree. Arming refuses a dirty tree for this reason.
- Read `.spectomat/gates.sh` after it is first rendered. It runs on every task.
- Treat a draft from an untrusted source as untrusted input.
