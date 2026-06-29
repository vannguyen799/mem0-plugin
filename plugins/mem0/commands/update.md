---
description: Record a new fact and reconcile it — find memories it contradicts/supersedes, confirm, delete the stale ones, then save the new fact
allowed-tools: Bash
argument-hint: <the new/corrected fact>
---
Update memory for the current repo with `$ARGUMENTS`, removing memories that now CONTRADICT or are
SUPERSEDED by it. mem0's server already dedupes on write, but this gives the user an explicit,
reviewable pass so conflicting facts don't pile up.

First, surface existing memories semantically related to the new fact, with id + score + text:

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

Then REASON over the matches: which ones **directly conflict with** or are **made obsolete by**
`$ARGUMENTS`? Ignore ones that are merely related but still true. Show the user the conflicting
memories you propose to delete and STOP for confirmation. Do not delete anything that is still
accurate alongside the new fact.

After the user confirms, delete the stale ids (replace `IDS`) and save the new fact:

```bash
source "${CLAUDE_PLUGIN_ROOT}/scripts/config.sh"
uid="$(resolve_user_id "$PWD")"
for id in IDS; do
  curl -sS -X DELETE "$MEM0_HOST/memories/$id" -H "X-API-Key: $MEM0_API_KEY" >/dev/null \
    && echo "removed stale $id"
done
jq -nc --arg t "$ARGUMENTS" --arg u "$uid" \
  '{messages:[{role:"user",content:$t}], user_id:$u, metadata:{source:"mem0-update"}}' \
  | curl -sS -X POST "$MEM0_HOST/memories" \
      -H "X-API-Key: $MEM0_API_KEY" -H "Content-Type: application/json" --data @- \
  | jq -r '.results[]? | "\(.event): \(.memory)"'
```

Report what was removed and what was saved (the server returns ADD/UPDATE/DELETE events).
