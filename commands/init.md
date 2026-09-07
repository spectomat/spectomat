---
description: "Scaffold the spec-driven Ralph flow: ralph-loop-prompt.md, spec skeleton, ledger ignore"
argument-hint: "[project-name] [--spec docs/<file>.md] [--force]"
allowed-tools: ["Bash(${CLAUDE_PLUGIN_ROOT}/scripts/init.sh:*)", "Read", "Edit", "Grep", "Glob"]
---

# Spectomat init

Scaffold (already run):

```!
"${CLAUDE_PLUGIN_ROOT}/scripts/init.sh" $ARGUMENTS
```

The repository now holds three artefacts with different owners:

| Artefact | Owner | Role |
| --- | --- | --- |
| the spec (path printed above) | the user | *what* to build — normative, the loop never edits it |
| `ralph-loop-prompt.md` | the user | *how* the loop runs — re-read every iteration |
| `.claude/build-ledger.local.md` | the loop | progress memory — gitignored, written in Phase 0 |

## Now fill the EDIT blocks

Read `ralph-loop-prompt.md`. Every `<!-- EDIT ... -->` comment marks a
project-specific block. For each one, in file order:

1. Derive a proposal from the spec (if it has content) and the repository:
   mission, environment limits, spec areas for Phase 0's readers, build
   phases from the spec's build sequence, project rules, gate commands, and
   forbidden actions.
2. Show the proposal and ask the user to confirm or correct it — one block per
   message. Use `superpowers:brainstorming` when the spec itself is still
   empty: the spec must exist before the loop can plan.
3. Replace the comment with the confirmed text. Delete a block the user says
   does not apply.

Do **not** start the loop from this command. When no `<!-- EDIT` remains, tell
the user to run `/spectomat:build`.

If the spec was just created as a skeleton, use `spectomat:writing-specs` to
help write it first; a loop over an empty spec plans nothing.
