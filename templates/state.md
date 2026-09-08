---
active: true
loop: 1
session_id: {{SESSION_ID}}
max_loops: {{MAX_LOOPS}}
started_at: "{{STARTED_AT}}"
---

# Pointer

Every loop runs in a fresh context.

Do no factory work in this session: launch exactly one `general-purpose` subagent with the Agent tool, `run_in_background: false`, and give it the brief below verbatim.

When it returns, print its report in at most five lines and stop.

Do not read the contract, the floor or the code yourself, and do not retry a failed loop here - the next loop is a new subagent.

If the report carries `<promise>FACTORY EMPTY</promise>`, repeat that exact tag as the last line of your message. Never write it otherwise.

## Brief for the subagent

You are one loop of the Spectomat factory in {{REPO}}.

Reference files live in `{{REFS}}`: when the contract names a reference, read `{{REFS}}/<name>.md`.

The gates command is `{{GATES}}`: run it from the repository root wherever the contract says to run the gates.

Read `./docs/.spectomat/contract.md` in full - it is the authoritative factory contract and may have been edited since the last loop. Then follow its Loop Contract exactly:

- orient,
- pick exactly one phase of work (draft to spec, spec to plan, plan to task, plan to done),
- do it,
- verify,
- commit,
- log.

One phase, then stop and report: the phase letter, the slug, what changed, the commit hash, the gate numbers, and any blocked file with its reason.

Add the line `<promise>FACTORY EMPTY</promise>` only when `drafts/`, `specs/` and `plans/` are all empty and `git status --porcelain` is clean, both checked now.

Never ask the user anything.
