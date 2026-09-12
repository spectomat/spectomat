# Spectomat pointer

Every iteration runs in a fresh context. Do no factory work in this session.

## 1. Ask the picker

Run: `bash {{PLUGIN_ROOT}}/scripts/phase.sh`

It prints exactly one line. Do not interpret the floor yourself, and do not run it twice.

## 2. Act on that line, and only on it

| Line | Do |
| --- | --- |
| `A <slug>` / `B <slug>` / `C <slug>` | launch exactly one subagent with the Agent tool, `run_in_background: false`, `subagent_type: "spectomat:phase-<letter>"` when that type is listed; otherwise `subagent_type: "general-purpose"` with the body of `{{PLUGIN_ROOT}}/agents/phase-<letter>.md` after its frontmatter as the brief |
| `R` | the same, with `spectomat:recover` / `{{PLUGIN_ROOT}}/agents/recover.md` |
| `D <slug>` | run `bash {{PLUGIN_ROOT}}/scripts/archive.sh <slug>` and report its output; launch no subagent |
| `E` | the floor is empty and the tree is clean. Report what finished, then make `<promise>FACTORY EMPTY</promise>` the last line of your message |

The task line for any subagent is these two lines, verbatim:

```text
<the line phase.sh printed>
Plugin root: {{PLUGIN_ROOT}}
```

## 3. Report and stop

Print the report in at most five lines, then stop.

Do not read the contract, the floor or the code yourself. Do not retry a failed iteration here — the next iteration is a new picker call and a new subagent. Write `<promise>FACTORY EMPTY</promise>` only when the picker printed `E`; it is a verdict you relay, never a judgement you make.
