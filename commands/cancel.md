---
description: "Cancel the active Spectomat loop"
allowed-tools: ["Bash(test -f .claude/spectomat-loop.local.md:*)", "Bash(rm .claude/spectomat-loop.local.md)", "Read(.claude/spectomat-loop.local.md)"]
---

# Spectomat cancel

1. Check for the state file with Bash:
   `test -f .claude/spectomat-loop.local.md && echo "EXISTS" || echo "NOT_FOUND"`
2. **If NOT_FOUND**: say "No active Spectomat loop."
3. **If EXISTS**: read the `iteration:` value from `.claude/spectomat-loop.local.md`,
   remove the file with `rm .claude/spectomat-loop.local.md`, and report
   "Cancelled Spectomat loop (was at iteration N)".

The ledger is untouched; `/spectomat:build` resumes from it.
