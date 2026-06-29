#!/usr/bin/env bash
# Claude Code Stop hook for mem0 — end-of-session summary capture.
#   On session end, parse the transcript, build a compact digest (task + outcome + files touched),
#   and POST it to mem0 so the server's LLM extracts the durable facts. This is the reliable write
#   path: per-prompt capture can miss things, but every session leaves one clean summary.
# Best-effort only: must NEVER block or fail the session -> always exit 0, bounded timeouts, no noise.
# Toggle with MEM0_SESSION_SUMMARY=0.
set -uo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$DIR/config.sh" 2>/dev/null || exit 0
[ "${MEM0_ENABLED:-1}" = "1" ] || exit 0
[ "${MEM0_SESSION_SUMMARY:-1}" = "1" ] || exit 0
[ -n "${MEM0_API_KEY:-}" ] || exit 0
case "${MEM0_HOST:-}" in https://*) ;; *) exit 0;; esac

for _bin in jq curl git; do command -v "$_bin" >/dev/null 2>&1 || exit 0; done

# stdin = Stop hook payload: transcript_path, cwd, session_id.
PAYLOAD="$(cat)"
TPATH="$(printf '%s' "$PAYLOAD" | jq -r '.transcript_path // empty' 2>/dev/null)"
CWD="$(printf '%s' "$PAYLOAD" | jq -r '.cwd // empty' 2>/dev/null)"
SID="$(printf '%s' "$PAYLOAD" | jq -r '.session_id // empty' 2>/dev/null)"
[ -n "$CWD" ] || CWD="$PWD"
[ -n "$TPATH" ] && [ -f "$TPATH" ] || exit 0

# Per-repo namespace (same resolution as recall/capture).
MEM0_USER_ID="$(resolve_user_id "$CWD")"
[ -n "$MEM0_USER_ID" ] || exit 0
PROJECT_LABEL="$(resolve_project_label "$CWD" 2>/dev/null)"

# Parse the JSONL transcript tolerantly (skip any non-JSON line).
OBJS="$(jq -R 'fromjson? // empty' "$TPATH" 2>/dev/null)"
[ -n "$OBJS" ] || exit 0

# Last assistant message's text (the conclusions / outcome).
LAST_ASSISTANT="$(printf '%s' "$OBJS" | jq -rs '
  ([ .[] | select(.type=="assistant") ] | last
   | ((.message.content // []) | map(select(.type=="text") | .text) | join("\n"))) // ""' 2>/dev/null)"

# First user message = the task (content may be a string or an array of blocks).
FIRST_USER="$(printf '%s' "$OBJS" | jq -rs '
  [ .[] | select(.type=="user")
    | (.message.content)
    | if type=="string" then . else (map(select(.type=="text") | .text) | join("\n")) end ]
  | map(select(. != null and . != "")) | first // ""' 2>/dev/null)"

# Files created/edited this session (unique).
FILES="$(printf '%s' "$OBJS" | jq -rs '
  [ .[] | select(.type=="assistant") | (.message.content // [])[]
    | select(.type=="tool_use" and ((.name // "") | test("^(Edit|Write|MultiEdit|NotebookEdit)$")))
    | (.input.file_path // .input.notebook_path // empty) ]
  | unique | .[]' 2>/dev/null)"

# Bound + redact each piece before anything leaves the machine.
TASK="$(printf '%s' "$FIRST_USER"     | _mem0_redact | head -c 600)"
OUTCOME="$(printf '%s' "$LAST_ASSISTANT" | _mem0_redact | head -c "${MEM0_SUMMARY_MAX_CHARS:-2000}")"
FILE_LIST="$(printf '%s\n' "$FILES" | sed '/^$/d' | head -30 | sed 's#.*/##' | paste -sd ', ' - 2>/dev/null)"

# Nothing meaningful to record -> skip.
[ -n "$OUTCOME$FILE_LIST" ] || exit 0

SUMMARY="Session summary for project '${PROJECT_LABEL:-$MEM0_USER_ID}'."
[ -n "$TASK" ]      && SUMMARY="$SUMMARY
Task: $TASK"
[ -n "$FILE_LIST" ] && SUMMARY="$SUMMARY
Files changed: $FILE_LIST"
[ -n "$OUTCOME" ]   && SUMMARY="$SUMMARY
Outcome: $OUTCOME"

# API key via curl -K config on a non-argv fd so it never lands in /proc/<pid>/cmdline.
_keycfg() { printf 'header = "X-API-Key: %s"\n' "$MEM0_API_KEY"; }

# Fire-and-forget: detach the POST (its own stdio redirected) so the session ends immediately.
(
  jq -nc --arg c "$SUMMARY" --arg u "$MEM0_USER_ID" --arg p "$PROJECT_LABEL" --arg s "$SID" \
    '{messages:[{role:"user",content:$c}], user_id:$u,
      metadata:({source:"claude-code-session"}
        + (if $p != "" then {project:$p} else {} end)
        + (if $s != "" then {session:($s[0:8])} else {} end))}' \
  | curl -sS --proto '=https' --max-time "${MEM0_SUMMARY_TIMEOUT:-25}" -X POST "$MEM0_HOST/memories" \
      -K <(_keycfg) -H "Content-Type: application/json" --data @-
) </dev/null >/dev/null 2>&1 &
disown 2>/dev/null || true
exit 0
