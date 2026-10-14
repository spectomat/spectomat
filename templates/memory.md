# Factory Memory — `{{REPO}}`

The operator's rules for this flow, then what the factory has learned about this codebase. Every iteration reads it in full before working and adds to it before it ends. It is tracked by git, but the flow never commits it: the operator reviews its changes and commits them, so one copy rides every branch.

## Rules

The operator's own rules. **Highest priority**: each one wins over the plugin's contract and over every phase brief.

Written by the operator only: a phase agent reads this section and never edits or prunes it. One rule per line, `- <the rule> — <why>`. Delete a rule to lift it.

## Learned

Every section below is the factory's, written by the phase agents.

**One line per entry**, in the section it belongs to, `- <the fact> — <why the next iteration cares>`, paths and commands in backticks. Newest last.

**A fact earns a line only if all three hold**: it is still true after the current plan is archived, an iteration working on a *different* task would want it, and it is not one grep away from a file that iteration already reads. Anything that fails a test belongs elsewhere: what happened is `log.md`, what is being built is the spec, how it is being built is the plan, a decision binding one task is a line in the plan's `ruling.md`.

**Correct or delete on contradiction.** A wrong memory costs more than no memory. When a section passes ~12 lines, merge the weakest entries or drop them; the four sections together stay under ~40.

Zero new entries in an iteration is a normal outcome. Two or three is a good iteration. Ten means you are writing a log.

### Map

Where a kind of thing lives, when the path is not guessable from the name.

### Commands

How to run, test and inspect this project, with what it costs.

### Patterns

Conventions a new file must follow to look like the ones around it.

### Traps

Something that cost a strike or a review round: symptom, cause, the rule that avoids it.
