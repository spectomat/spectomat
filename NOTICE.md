`scripts/stop-hook.sh` and the state-file format written by `scripts/run.sh`
derive from the `ralph-loop` plugin by Anthropic, licensed under the Apache
License, Version 2.0 (`LICENSE-ralph-loop`). Changes: the state file is
`docs/.spectomat/loop.md`, the pointer prompt is fixed, and the setup
prepares the factory floor before arming the hook.

The skills `writing-plans`, `test-driven-development`, `systematic-debugging`
and `verification-before-completion`, and the `executing-tasks` skill (a merge
of `subagent-driven-development`, `executing-plans`, `requesting-code-review`
and `receiving-code-review`), are condensed from
[superpowers](https://github.com/obra/superpowers) 6.3.0 by Jesse Vincent,
MIT License (`LICENSE-superpowers`). They are shortened and rewritten for an
unattended loop: no questions to a human, no branches or worktrees, skill
references namespaced `spectomat:`, plan and work paths under
`docs/.spectomat/`.
