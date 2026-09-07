---
description: "Show factory progress: loop iteration, floor counts, plan steps, blocked files, log tail"
allowed-tools: ["Bash(${CLAUDE_PLUGIN_ROOT}/scripts/status.sh:*)"]
---

# Spectomat status

```!
"${CLAUDE_PLUGIN_ROOT}/scripts/status.sh"
```

Report the summary above to the user in a few lines: where the loop is, what
comes next, and any BLOCKED item with its reason. Do not start or modify
anything.
