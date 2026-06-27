---
description: Configure mem0 credentials (API key + optional host) — writes ~/.claude/mem0/config.local
allowed-tools: Bash
argument-hint: <api-key> [host-url]
---
Configure mem0 from the arguments `$ARGUMENTS` (first token = API key, optional second = host URL).
This writes a machine-local config the hook + MCP server read — the most reliable method, since it
does not depend on how Claude Code was launched (unlike `~/.bashrc`, which GUI/non-login launches miss).

```bash
set -- $ARGUMENTS
KEY="${1:-}"; HOST="${2:-https://mem0.qzzprivate.qzz.io}"
if [ -z "$KEY" ]; then
  echo "Usage: /mem0-setup <api-key> [host-url]"; exit 0
fi
case "$HOST" in https://*) ;; *) echo "host must be https://..."; exit 0;; esac
mkdir -p ~/.claude/mem0
printf 'export MEM0_API_KEY="%s"\nexport MEM0_HOST="%s"\n' "$KEY" "$HOST" > ~/.claude/mem0/config.local
chmod 600 ~/.claude/mem0/config.local
echo "mem0 configured -> host=$HOST  key=***  (~/.claude/mem0/config.local, chmod 600)"
```

Then tell the user mem0 is ready to use immediately — no restart needed, since the hook and MCP
tools re-read config on each call. Suggest they run `/mem0-status` to confirm.
