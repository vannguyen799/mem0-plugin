---
description: Show mem0 status (enabled, key present, resolved user_id, stored count) for the current repo
allowed-tools: Bash
---
Run this and report the result concisely to the user:

```bash
source "${CLAUDE_PLUGIN_ROOT}/scripts/config.sh"
uid="$(resolve_user_id "$PWD")"
echo "enabled=$MEM0_ENABLED  capture=$MEM0_CAPTURE  key=$([ -n "$MEM0_API_KEY" ] && echo set || echo MISSING)"
echo "user_id=${uid:-<none: hook no-ops here>}"
[ -n "$uid" ] && [ -n "$MEM0_API_KEY" ] && \
  echo "stored=$(curl -sS --max-time 8 -H "X-API-Key: $MEM0_API_KEY" "$MEM0_HOST/memories?user_id=$uid" | jq '.results|length')"
```

If `key=MISSING`, tell the user to create `~/.claude/mem0/config.local` with `export MEM0_API_KEY="..."`.
