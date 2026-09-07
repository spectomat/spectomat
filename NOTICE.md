# Notice

`hooks/stop-hook.sh` and the state-file format written by `scripts/start-loop.sh`
derive from the `ralph-loop` plugin by Anthropic, licensed under the Apache
License, Version 2.0 (`LICENSE-ralph-loop`). Changes: the state file is
`.claude/spectomat-loop.local.md`, the pointer prompt is fixed, and the setup
runs a preflight before arming the hook.
