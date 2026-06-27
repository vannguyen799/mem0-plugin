# mem0-local — Claude Code plugin marketplace

Hosts the **mem0** plugin: automatic long-term memory for Claude Code, backed by a
self-hosted mem0 server. Recalls relevant memories and captures durable facts on every
prompt, via a bundled `UserPromptSubmit` hook. Per-project namespaces; secret-free repo.

## Install (any machine)
```bash
# from a local checkout:
/plugin marketplace add /home/user/.claude/mem0-plugin
/plugin install mem0@mem0-local

# or, once pushed to GitHub:
/plugin marketplace add vannguyen799/mem0-plugin
/plugin install mem0@mem0-local
```
Then set your key (and optionally a custom host) in your shell env — add to `~/.bashrc`:
```bash
export MEM0_API_KEY="YOUR_KEY"                       # required
export MEM0_HOST="https://your-mem0-host"            # optional — defaults to the main mem0 server
```
`source ~/.bashrc`, then restart Claude Code. Both are env-customizable per machine.
Headless/cron shells that don't source `~/.bashrc` can instead put the same `export` lines in
`~/.claude/mem0/config.local` (sourced only when the env var is unset). No key → hook no-ops (safe).

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

## Commands
`/mem0-status` · `/mem0-recall <query>` · `/mem0-purge`

## Layout
```
mem0-plugin/
├── .claude-plugin/marketplace.json   # this marketplace
└── plugins/mem0/
    ├── .claude-plugin/plugin.json
    ├── hooks/hooks.json              # UserPromptSubmit -> scripts/mem0-prompt.sh
    ├── scripts/{config.sh,mem0-prompt.sh}
    └── commands/{mem0-status,mem0-recall,mem0-purge}.md
```

Settings (env-overridable, defaults in `scripts/config.sh`): `MEM0_ENABLED`, `MEM0_CAPTURE`,
`MEM0_REDACT`, `MEM0_SKIP_SELF`, `MEM0_REPO_KEY` (default `readable`), `MEM0_MIN_SCORE`,
`MEM0_RECALL_LIMIT`. The API key/host come from the env (`~/.bashrc`), never the repo.
