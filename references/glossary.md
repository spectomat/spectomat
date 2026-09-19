# Glossary

## Plugin

- **Plugin** is Spectomat itself: a Claude Code plugin made of commands, agents, a hook, scripts, templates and reference files.

- **Command** is a slash command the user types: `/spectomat:run`, `/spectomat:status`, `/spectomat:cancel`, `/spectomat:help`.

- **Session** is the Claude Code session where `/spectomat:run` was called. It holds the flow and dispatches the agents.

## Work

- **Flow** is one unattended run that turns drafts into committed code: the sequence of iterations from arming to `FINISH`.

- **Iteration** is one step of the flow: one verdict, one phase, one commit.

- **Phase** is one kind of work on a slug: `SPECIFY`, `REVIEW-SPEC`, `PLAN`, `IMPLEMENT`, `REVIEW`, `ARCHIVE`. It is also the slug's position in `state.json`, where `DONE` and `BLOCKED` are the two terminal values.

- **Slug** is the name of one idea: the draft's file name without `.md`, and the directory `.spectomat/<slug>/` that holds all files of that idea.

- **Draft** is the idea as the user wrote it: `<slug>/draft.md`.

- **Spec** is the normative description of what to build, made from the draft: `<slug>/spec.md`.

- **Plan** is the split of a spec into tasks: an overview and one task file per task.

- **Task** is one independent piece of work in a plan, with its own file, tests and commit.

- **Task ledger** is `<slug>/tasks.json`: the committed list of the slug's tasks with their dependencies, status and closing evidence.

- **Strike** is one failed attempt at a phase for a slug. Three strikes make the slug `BLOCKED`.

- **Verification gate** is one command in `.spectomat/gates.sh` that must exit 0 for work to count as passing.

## Floor

- **Floor** is `.spectomat/`: the directory the flow keeps in the user's project.

- **Contract** is `.spectomat/contract.md`: the rules that bind every phase.

- **Memory** is `.spectomat/memory.md`: durable facts about the user's codebase — map, commands, patterns, traps.

- **State file** is `.spectomat/state.json`: the flow's live state — each slug's phase and strikes, the iteration counter, and `current`. It is not committed.

- **Marker** is `<slug>/done.md` or `<slug>/blocked.md`: the committed record of how a slug finished.

## Machinery

- **Picker** is `scripts/phase.sh`: the script that decides what the next iteration does.

- **Verdict** is the picker's answer: a phase, `RECOVER` or `FINISH`, plus the slug and the agent to dispatch.

- **Pointer** is the prompt that carries the verdict to the session. It is generated text, not a file.

- **Brief** is an agent's instruction file under `agents/`.

- **Phase agent** is the fresh subagent that performs one phase: `spectomat:specify`, `review-spec`, `plan`, `implement`, `review`, `archive`.

- **Task agent** is `spectomat:task`: the fresh subagent that builds and gates one task.

- **Archiver** is the `ARCHIVE` phase agent together with `scripts/agent-archive.sh`, the script that does the archiving.

- **Janitor** is `spectomat:recover`: the subagent that serves the `RECOVER` verdict — it restores a clean tree or rules on slugs that are out of strikes.
