---
description: Delete ALL mem0 memories for the current repo's namespace (asks to confirm first)
allowed-tools: Bash
---
This permanently deletes every memory under the current repo's mem0 namespace.

First show what would be deleted, then STOP and ask the user to confirm before deleting:

```bash
source "${CLAUDE_PLUGIN_ROOT}/scripts/config.sh"
uid="$(resolve_user_id "$PWD")"
echo "namespace: $uid"
curl -sS --max-time 8 -H "X-API-Key: $MEM0_API_KEY" "$MEM0_HOST/memories?user_id=$uid" \
  | jq -r '.results[] | "- \(.memory)"'
```

Only after the user explicitly confirms, delete them:

```bash
source "${CLAUDE_PLUGIN_ROOT}/scripts/config.sh"
uid="$(resolve_user_id "$PWD")"
for id in $(curl -sS -H "X-API-Key: $MEM0_API_KEY" "$MEM0_HOST/memories?user_id=$uid" | jq -r '.results[]?.id'); do
  curl -sS -X DELETE "$MEM0_HOST/memories/$id" -H "X-API-Key: $MEM0_API_KEY" >/dev/null && echo "deleted $id"
done
```
