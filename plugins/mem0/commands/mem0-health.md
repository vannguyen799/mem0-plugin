---
description: Diagnose mem0 — connectivity, key/host, namespace, and a live read + write/delete probe
allowed-tools: Bash
---
Run this end-to-end health check and report each line as PASS/FAIL with a one-line summary:

```bash
source "${CLAUDE_PLUGIN_ROOT}/scripts/config.sh"
uid="$(resolve_user_id "$PWD")"; host="$MEM0_HOST"; probe="__mem0_health_probe__"
keycfg() { printf 'header = "X-API-Key: %s"\n' "$MEM0_API_KEY"; }

echo "host         = ${host:-<unset>}"
echo "enabled      = ${MEM0_ENABLED:-1}   capture=${MEM0_CAPTURE:-1}   session_summary=${MEM0_SESSION_SUMMARY:-1}"
echo "key          = $([ -n "$MEM0_API_KEY" ] && echo set || echo MISSING)"
echo "user_id      = ${uid:-<none: hook no-ops in this dir>}"
case "$host" in https://*) ;; *) echo "transport    = FAIL (host must be https://)";; esac

# READ — count memories in this namespace (also proves connectivity + auth).
read_out="$(curl -sS --max-time 8 -K <(keycfg) "$host/memories?user_id=${uid:-_}" 2>/dev/null)"
read_n="$(printf '%s' "$read_out" | jq '(.results//[])|length' 2>/dev/null)"
echo "read         = $([ -n "$read_n" ] && echo "PASS ($read_n memories)" || echo "FAIL ($read_out)")"

# WRITE — add a throwaway memory to a probe namespace, expect event=ADD.
w="$(curl -sS --max-time 15 -X POST "$host/memories" -K <(keycfg) -H "Content-Type: application/json" \
  --data '{"messages":[{"role":"user","content":"mem0 health probe — safe to delete"}],"user_id":"'"$probe"'","metadata":{"source":"health"}}' \
  2>/dev/null | jq -r '(.results//[])[0].event // "FAIL"' 2>/dev/null)"
echo "write        = $([ "$w" = "ADD" ] && echo "PASS" || echo "$w")"

# CLEANUP — delete the probe namespace.
curl -sS --max-time 10 -X DELETE -K <(keycfg) "$host/memories?user_id=$probe" >/dev/null 2>&1 \
  && echo "cleanup      = ok" || echo "cleanup      = (left probe; delete manually)"
```

If `key=MISSING`, tell the user to run `/mem0-setup YOUR_API_KEY [host]`. If read/write FAIL, surface the
error text and check the host is reachable and the API key is valid.
