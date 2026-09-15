# Spectomat pointer

Fresh context each iteration. Do no factory work here.

## 1. Ask the picker

Run `bash {{PLUGIN_ROOT}}/scripts/phase.sh` once. It prints exactly one line, starting with the phase name. Do not interpret the floor, the contract or the code yourself — act only on that line.

## 2. Act on that line, and only on it

Every line gets exactly one subagent: launch it with the Agent tool, `run_in_background: false`, and the `subagent_type` from the table below when that type is listed; otherwise use `"general-purpose"` and pass the paired brief file's body, with its frontmatter stripped, as the brief.

| Line | subagent_type | Brief |
| --- | --- | --- |
| `SPECIFY <slug>` | `spectomat:specify` | `{{PLUGIN_ROOT}}/agents/specify.md` |
| `REVIEW-SPEC <slug>` | `spectomat:review-spec` | `{{PLUGIN_ROOT}}/agents/review-spec.md` |
| `PLAN <slug>` | `spectomat:plan` | `{{PLUGIN_ROOT}}/agents/plan.md` |
| `IMPLEMENT <slug>` | `spectomat:implement` | `{{PLUGIN_ROOT}}/agents/implement.md` |
| `REVIEW <slug>` | `spectomat:review` | `{{PLUGIN_ROOT}}/agents/review.md` |
| `ARCHIVE <slug>` | `spectomat:archive` | `{{PLUGIN_ROOT}}/agents/archive.md` |
| `RECOVER` | `spectomat:recover` | `{{PLUGIN_ROOT}}/agents/recover.md` |
| `FINISH` | `spectomat:finish` | `{{PLUGIN_ROOT}}/agents/finish.md` |

The task line for any subagent is these two lines, verbatim:

```text
<the line phase.sh printed>
Plugin root: {{PLUGIN_ROOT}}
```

## 3. Report and stop

Print the report in at most five lines, then stop. Never retry a failed iteration here — the next iteration is a new picker call and a new subagent. Write `<promise>FACTORY EMPTY</promise>` only when the picker printed `FINISH`; it is a verdict you relay, never a judgement you make.
