# Factory Memory — `{{REPO}}`

What the factory has learned about this codebase. Every loop reads it before working and adds to it before committing. It is committed, so it is also the human's map of the project.

**One line per entry**, in the section it belongs to, `- <the fact> — <why the next loop cares>`, paths and commands in backticks. Newest last.

**A fact earns a line only if all three hold**: it is still true after the current plan is archived, a loop working on a *different* task would want it, and it is not one grep away from a file that loop already reads. Everything else is a log line, a spec decision or a task ruling.

**Correct or delete on contradiction.** A wrong memory costs more than no memory. When a section passes ~12 lines, merge the weakest entries or drop them; the whole file stays under ~40.

## Map

Where a kind of thing lives, when the path is not guessable from the name.

## Commands

How to run, test and inspect this project, with what it costs.

## Patterns

Conventions a new file must follow to look like the ones around it.

## Traps

Something that cost a strike or a fix round: symptom, cause, the rule that avoids it.
