---
description: "Cancel the active Spectomat loop"
allowed-tools: ["Bash(test -f docs/.spectomat/state.md:*)", "Bash(rm docs/.spectomat/state.md)", "Read(docs/.spectomat/state.md)"]
---

# Spectomat cancel

1. Check for the state file with Bash:
   `test -f docs/.spectomat/state.md && echo "EXISTS" || echo "NOT_FOUND"`
2. **If NOT_FOUND**: say "No active Spectomat loop."
3. **If EXISTS**: read the `iteration:` value from `docs/.spectomat/state.md`,
   remove the file with `rm docs/.spectomat/state.md`, and report
   "Cancelled Spectomat loop (was at iteration N)".

The floor under `docs/.spectomat/` is untouched; `/spectomat:run` resumes from it.
