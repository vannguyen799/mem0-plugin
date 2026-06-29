---
description: Selectively delete mem0 memories matching a query (shows matches, confirms, then deletes only the chosen ones)
allowed-tools: Bash
argument-hint: <what to forget>
---
Selectively forget memories in the current repo's namespace. This deletes only the memories the
user picks — NOT the whole namespace (use `/mem0:purge` for that).

First, find candidates semantically matching `$ARGUMENTS` and show each with its id, score, and text:

```bash
source "${CLAUDE_PLUGIN_ROOT}/scripts/config.sh"
uid="$(resolve_user_id "$PWD")"
[ -n "$uid" ] || { echo "no mem0 namespace for this repo"; exit 0; }
echo "namespace: $uid"
jq -nc --arg q "$ARGUMENTS" --arg u "$uid" '{query:$q, user_id:$u, limit:10}' \
  | curl -sS --max-time 8 -X POST "$MEM0_HOST/search" \
      -H "X-API-Key: $MEM0_API_KEY" -H "Content-Type: application/json" --data @- \
  | jq -r '.results[] | "\(.id)\t\(.score|.*100|floor)%\t\(.memory)"'
```

Then STOP. Show the user the numbered matches and ask **which ones to delete** (let them pick a
subset, "all", or "none"). Do NOT delete anything the user did not explicitly choose.

Only after the user confirms, delete the chosen ids (replace `IDS` with the space-separated ids):

```bash
source "${CLAUDE_PLUGIN_ROOT}/scripts/config.sh"
for id in IDS; do
  curl -sS -X DELETE "$MEM0_HOST/memories/$id" -H "X-API-Key: $MEM0_API_KEY" >/dev/null \
    && echo "deleted $id"
done
```

Report which memories were removed.
