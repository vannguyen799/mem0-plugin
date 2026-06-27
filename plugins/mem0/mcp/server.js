#!/usr/bin/env node
'use strict';
// Minimal zero-dependency MCP stdio server exposing mem0 as tools Claude can call on its own judgment:
//   search_memory(query)  · add_memory(text)  · list_memories()
// Host / API key / per-project user_id are resolved by reusing the plugin's scripts/config.sh
// (so env, ~/.claude/mem0/config.local, root pin files, and auto-derive all behave identically).
const {execFileSync} = require('child_process');
const path = require('path');
const readline = require('readline');

const PLUGIN_ROOT = process.env.CLAUDE_PLUGIN_ROOT || path.resolve(__dirname, '..');
const CONFIG = path.join(PLUGIN_ROOT, 'scripts', 'config.sh');
const PROJECT_DIR = process.env.CLAUDE_PROJECT_DIR || process.cwd();

function resolveConfig() {
  const script =
    `source ${q(CONFIG)} 2>/dev/null; ` +
    `printf '%s\\n%s\\n%s\\n' "$MEM0_HOST" "$MEM0_API_KEY" "$(resolve_user_id ${q(PROJECT_DIR)})"`;
  const out = execFileSync('bash', ['-c', script], {encoding: 'utf8'});
  const [host, key, userId] = out.split('\n');
  return {host, key, userId};
}
function q(s) {return "'" + String(s).replace(/'/g, "'\\''") + "'";}

async function api(host, key, pathname, method, body) {
  const res = await fetch(host + pathname, {
    method,
    headers: {'X-API-Key': key, 'Content-Type': 'application/json'},
    body: body ? JSON.stringify(body) : undefined,
  });
  if (!res.ok) throw new Error(`mem0 ${method} ${pathname} -> HTTP ${res.status}`);
  return res.json();
}

const TOOLS = [
  {
    name: 'search_memory',
    description: 'Search long-term memory for this project (semantic). Use when you need prior context, ' +
      'user preferences, or decisions you might have forgotten. Returns matching memories with scores.',
    inputSchema: {
      type: 'object',
      properties: {
        query: {type: 'string', description: 'What to look up'},
        limit: {type: 'number', description: 'Max results (default 8)'},
      },
      required: ['query'],
    },
  },
  {
    name: 'add_memory',
    description: 'Save a durable fact to long-term memory for this project. Call ONLY when you learn ' +
      'something new and lasting (a preference, decision, convention, or stable fact) — not transient task detail. ' +
      'Write one clean declarative sentence.',
    inputSchema: {
      type: 'object',
      properties: {text: {type: 'string', description: 'The fact to remember, as a clean sentence'}},
      required: ['text'],
    },
  },
  {
    name: 'list_memories',
    description: 'List everything currently stored in this project\'s memory namespace.',
    inputSchema: {type: 'object', properties: {}},
  },
];

const ok = text => ({content: [{type: 'text', text}], isError: false});
const err = text => ({content: [{type: 'text', text}], isError: true});

async function callTool(name, args) {
  let host, key, userId;
  try { ({host, key, userId} = resolveConfig()); }
  catch (e) { return err('config error: ' + e.message); }
  if (!key) return err('MEM0_API_KEY not set — add `export MEM0_API_KEY="..."` to ~/.bashrc.');
  if (!userId) return err('No mem0 namespace for this project (non-git with no pin file).');

  try {
    if (name === 'search_memory') {
      const d = await api(host, key, '/search', 'POST', {query: args.query, user_id: userId, limit: args.limit || 8});
      const lines = (d.results || []).map(r => `- (${Math.round((r.score || 0) * 100)}%) ${r.memory}`);
      return ok(lines.length ? lines.join('\n') : 'No matching memories.');
    }
    if (name === 'add_memory') {
      if (!args.text || !String(args.text).trim()) return err('text is required');
      const d = await api(host, key, '/memories', 'POST',
        {messages: [{role: 'user', content: String(args.text)}], user_id: userId, metadata: {source: 'claude-mcp'}});
      const added = (d.results || []).filter(r => r.event === 'ADD').map(r => `- ${r.memory}`);
      return ok(added.length ? `Saved to "${userId}":\n${added.join('\n')}` : 'Noted (no new durable fact extracted).');
    }
    if (name === 'list_memories') {
      const d = await api(host, key, `/memories?user_id=${encodeURIComponent(userId)}`, 'GET');
      const lines = (d.results || []).map(r => `- ${r.memory}`);
      return ok(`Namespace "${userId}":\n${lines.join('\n') || '(empty)'}`);
    }
    return err('Unknown tool: ' + name);
  } catch (e) {
    return err(String(e.message || e));
  }
}

async function handle(method, params) {
  switch (method) {
    case 'initialize':
      return {protocolVersion: '2024-11-05', capabilities: {tools: {}}, serverInfo: {name: 'mem0', version: '1.0.0'}};
    case 'tools/list':
      return {tools: TOOLS};
    case 'tools/call':
      return await callTool(params.name, params.arguments || {});
    case 'ping':
      return {};
    default:
      throw {code: -32601, message: 'Method not found: ' + method};
  }
}

function send(obj) {process.stdout.write(JSON.stringify(obj) + '\n');}

const rl = readline.createInterface({input: process.stdin});
rl.on('line', async line => {
  line = line.trim();
  if (!line) return;
  let msg;
  try {msg = JSON.parse(line);} catch {return;}
  if (msg.id === undefined || msg.id === null) return;   // notification -> no response
  try {
    send({jsonrpc: '2.0', id: msg.id, result: await handle(msg.method, msg.params || {})});
  } catch (e) {
    send({jsonrpc: '2.0', id: msg.id, error: e.code ? e : {code: -32603, message: String(e.message || e)}});
  }
});
