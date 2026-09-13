# Spectomat pointer

Every iteration runs in a fresh context. Do no factory work in this session.

## 1. Ask the picker

Run: `bash {{PLUGIN_ROOT}}/scripts/phase.sh`

It prints exactly one line, starting with the phase name. Do not interpret the floor yourself, and do not run it twice.

## 2. Act on that line, and only on it

| Line | Do |
| --- | --- |
| `SPECIFY <slug>` / `REVIEW-SPEC <slug>` / `PLAN <slug>` / `IMPLEMENT <slug>` / `REVIEW <slug>` | launch exactly one subagent with the Agent tool, `run_in_background: false`, `subagent_type: "spectomat:<phase>"` when that type is listed; otherwise `subagent_type: "general-purpose"` with the body of `{{PLUGIN_ROOT}}/agents/<phase>.md` after its frontmatter as the brief |
| `RECOVER` | the same, with `spectomat:recover` / `{{PLUGIN_ROOT}}/agents/recover.md` |
| `ARCHIVE <slug>` | run `bash {{PLUGIN_ROOT}}/scripts/archive.sh <slug>` and report its output; launch no subagent |
| `FINISH` | the floor is empty and the tree is clean. Report what finished, then make `<promise>FACTORY EMPTY</promise>` the last line of your message |

`<phase>` is the first word of the line, lowercased: `SPECIFY` → `specify`, `REVIEW-SPEC` → `review-spec`, `PLAN` → `plan`, `IMPLEMENT` → `implement`, `REVIEW` → `review`. The verdict is upper case; the agent type and the brief file name are lower case.

The task line for any subagent is these two lines, verbatim:

```text
<the line phase.sh printed>
Plugin root: {{PLUGIN_ROOT}}
```

## 3. Report and stop

Print the report in at most five lines, then stop.

Do not read the contract, the floor or the code yourself. Do not retry a failed iteration here — the next iteration is a new picker call and a new subagent. Write `<promise>FACTORY EMPTY</promise>` only when the picker printed `FINISH`; it is a verdict you relay, never a judgement you make.
