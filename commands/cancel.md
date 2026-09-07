---
description: "Cancel the active Spectomat loop"
allowed-tools: ["Bash(test -f docs/.spectomat/loop.md:*)", "Bash(rm docs/.spectomat/loop.md)", "Read(docs/.spectomat/loop.md)"]
---

# Spectomat cancel

1. Check for the state file with Bash:
   `test -f docs/.spectomat/loop.md && echo "EXISTS" || echo "NOT_FOUND"`
2. **If NOT_FOUND**: say "No active Spectomat loop."
3. **If EXISTS**: read the `iteration:` value from `docs/.spectomat/loop.md`,
   remove the file with `rm docs/.spectomat/loop.md`, and report
   "Cancelled Spectomat loop (was at iteration N)".

The floor under `docs/.spectomat/` is untouched; `/spectomat:run` resumes from it.
