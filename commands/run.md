---
title: Spectomat run
description: "Run the Spectomat code development flow"
argument-hint: "[max-iterations]  (default 100)"
allowed-tools: ["Bash", "Read", "Write", "Edit", "Grep", "Glob", "Agent", "Task"]
---

Run the code development flow

Floor setup and the start of iterations over `draft → spec → plan → executed plan → done` phases, each slug in its own `.spectomat/<slug>/`:

```!
"${CLAUDE_PLUGIN_ROOT}/scripts/prepare.sh" $ARGUMENTS
```

If the output ends in `❌ Not starting`, report why and stop.

If the factory is armed, begin iteration 1 now: follow the prompt printed at the end of the output, exactly as it directs — it is the authoritative dispatch table, and the Stop hook feeds you the same prompt again after every iteration.

**This flow is unattended.**  
