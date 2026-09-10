---
active: true
loop: 1
session_id: {{SESSION_ID}}
max_loops: {{MAX_LOOPS}}
started_at: "{{STARTED_AT}}"
---

# State tracker

Every loop runs in a fresh context.

Do no factory work in this session: launch exactly one subagent with the Agent tool, `run_in_background: false`, and give it the task line below as its prompt.

- `subagent_type: "spectomat:looper"` when that type is listed - its brief is built in.
- Otherwise `subagent_type: "general-purpose"`, with the body of `{{PLUGIN_ROOT}}/agents/looper.md` (everything after its frontmatter) as the brief, followed by the task line.

When it returns, print its report in at most five lines and stop.

Do not read the contract, the floor or the code yourself, and do not retry a failed loop here - the next loop is a new subagent.

If the report carries `<promise>FACTORY EMPTY</promise>`, repeat that exact tag as the last line of your message. Never write it otherwise.

## Task line

Run one loop of the Spectomat factory now. Reference files live in `{{PLUGIN_ROOT}}/references`.
