---
description: Search this repo's mem0 memories for a query (read-only) and show matches
allowed-tools: Bash
argument-hint: <search query>
---
Search mem0 for `$ARGUMENTS` in the current repo's namespace and show the matches with scores:

```bash
source "${CLAUDE_PLUGIN_ROOT}/scripts/config.sh"
uid="$(resolve_user_id "$PWD")"
jq -nc --arg q "$ARGUMENTS" --arg u "$uid" '{query:$q, user_id:$u, limit:10}' \
  | curl -sS --max-time 8 -X POST "$MEM0_HOST/search" \
      -H "X-API-Key: $MEM0_API_KEY" -H "Content-Type: application/json" --data @- \
  | jq -r '.results[] | "\(.score|.*100|floor)%  \(.memory)"'
```

Summarize what mem0 remembers relevant to the query.
