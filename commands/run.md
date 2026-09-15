---
description: "Run the unattended dark factory"
argument-hint: "[max-iterations]  (default 100)"
allowed-tools: ["Bash", "Read", "Write", "Edit", "Grep", "Glob", "Agent", "Task"]
---

# Spectomat run

Run the unattended dark factory - floor setup
and the start of iterations over `drafts → specs → plans → executed plans → done` phases:

```!
"${CLAUDE_PLUGIN_ROOT}/scripts/prepare.sh" $ARGUMENTS
```

If the output ends in `❌ Not starting`, report why and stop.

If the factory is armed, begin iteration 1 now: follow the prompt printed at the end of the output, exactly as it directs — it is the authoritative dispatch table, and the Stop hook feeds you the same prompt again after every iteration.

**This flow is unattended.** Nobody answers questions. Decide, record the decision where `.spectomat/contract.md` says, and continue — `.spectomat/contract.md` is the single source of truth for the floor layout, phase priority and the three-strikes rule.
