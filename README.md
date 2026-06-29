# mem0-local — Claude Code plugin marketplace

Hosts the **mem0** plugin: long-term memory for Claude Code, backed by a self-hosted mem0 server.
A bundled `UserPromptSubmit` hook **auto-recalls** relevant memories every prompt and **auto-captures**
each prompt, a `Stop` hook **writes a session summary** on exit, and an **MCP server** gives Claude
`search_memory` / `add_memory` tools so it can also **write durable facts on its own judgment**.
Per-project namespaces; secret-free repo.

## Install (any machine)
```bash
/plugin marketplace add vannguyen799/mem0-plugin     # (or a local path)
/plugin install mem0@mem0-local
```
Then **configure credentials** with the setup command (recommended — works regardless of how Claude
Code was launched; no restart needed):
```bash
/mem0-setup YOUR_API_KEY                              # host defaults to the main mem0 server
/mem0-setup YOUR_API_KEY https://your-mem0-host       # custom host
```
It writes `~/.claude/mem0/config.local` (chmod 600), which the hook + MCP server read on every call.
Alternatively, export `MEM0_API_KEY` / `MEM0_HOST` in your shell env — but note a GUI/non-login launch
may not pass `~/.bashrc` to the plugin's hook/MCP processes, so `/mem0-setup` is the reliable path.
No key → mem0 safely no-ops.

## Auto-enable for a project / team
Commit to a repo's `.claude/settings.json`:
```json
{
  "extraKnownMarketplaces": {
    "mem0-local": {"source": {"source": "github", "repo": "vannguyen799/mem0-plugin"}}
  },
  "enabledPlugins": {"mem0@mem0-local": true}
}
```

## Per-project id
Each repo's `user_id` (memory namespace) is derived automatically (`MEM0_REPO_KEY`, default
`readable`): `package.json` name → `owner__repo` → folder name. **To pin a fixed id**, drop a
file at the project root whose contents are the id:
```bash
echo "my-project-id" > <repo>/.mem0-user      # or: MEM0_USER_ID  · or: .claude/mem0-user
```
Resolution: `$MEM0_USER_ID` env → root pin file → auto-derive. An empty / `off` / `disabled` / `-`
pin file disables mem0 for that repo.

## How memory is read & written
- **Read (auto):** the `UserPromptSubmit` hook searches mem0 every prompt and injects matches as context — Claude always has relevant memories without asking.
- **Write (auto-capture):** every prompt is sent to mem0 in the background (`MEM0_CAPTURE=1`, default); the server's LLM extracts durable facts. Prompts about mem0 itself are skipped (`MEM0_SKIP_SELF=1`). Set `MEM0_CAPTURE=0` for a quieter, agentic-only store.
- **Write (session summary):** the `Stop` hook parses the transcript at session end and POSTs a compact digest (task + outcome + files touched) so durable facts land even if per-prompt capture missed them. Toggle with `MEM0_SESSION_SUMMARY=0`.
- **Write (agentic):** Claude also calls the MCP `add_memory` tool when it judges something is durable & new.

## MCP tools (Claude-callable)
`search_memory(query)` · `add_memory(text)` · `list_memories()` — exposed by `mcp/server.js` (zero-dependency Node, reuses `config.sh` for host/key/per-project namespace).

## Commands
`/mem0-setup <key> [host]` · `/mem0-status` · `/mem0-health` · `/mem0-recall <query>` · `/mem0-purge`

## Layout
```
mem0-plugin/
├── .claude-plugin/marketplace.json   # this marketplace
└── plugins/mem0/
    ├── .claude-plugin/plugin.json
    ├── hooks/hooks.json              # UserPromptSubmit -> mem0-prompt.sh (recall+capture); Stop -> mem0-stop.sh (summary)
    ├── .mcp.json                     # registers the mem0 MCP server (agentic read/write tools)
    ├── mcp/server.js                 # zero-dep MCP server: search_memory / add_memory / list_memories
    ├── scripts/{config.sh,mem0-prompt.sh,mem0-stop.sh}
    └── commands/{mem0-setup,mem0-status,mem0-health,mem0-recall,mem0-purge}.md
```

Settings (env-overridable, defaults in `scripts/config.sh`): `MEM0_ENABLED`, `MEM0_CAPTURE` (default `1`),
`MEM0_SESSION_SUMMARY` (default `1`), `MEM0_SUMMARY_MAX_CHARS`, `MEM0_REDACT`, `MEM0_SKIP_SELF`,
`MEM0_REPO_KEY` (default `readable`), `MEM0_MIN_SCORE`, `MEM0_RECALL_LIMIT`. The API key/host come from
the env (`~/.bashrc`) or `~/.claude/mem0/config.local`, never the repo.
