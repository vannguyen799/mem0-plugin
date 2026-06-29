# mem0 plugin config — sourced by the hook. SECRET-FREE (safe to commit/distribute).
# The API key comes from your ENVIRONMENT — add to ~/.bashrc:  export MEM0_API_KEY="..."
# Host defaults to the main mem0 server below (override only if you self-host elsewhere).
# Fallback for non-login / headless shells that don't source ~/.bashrc: an optional
# ~/.claude/mem0/config.local is sourced ONLY when MEM0_API_KEY isn't already in the env.
if [ -z "${MEM0_API_KEY:-}" ] && [ -f "$HOME/.claude/mem0/config.local" ]; then . "$HOME/.claude/mem0/config.local"; fi

# All settings use ${VAR:-default} so the env (e.g. ~/.bashrc) wins (sourced after the shell env).
export MEM0_HOST="${MEM0_HOST:-https://mem0.qzzprivate.qzz.io}"   # fallback = main mem0 host; MUST be https://
export MEM0_API_KEY="${MEM0_API_KEY:-}"   # from env (~/.bashrc), config.local fallback; blank => hook no-ops

# Behaviour / kill switches
export MEM0_ENABLED="${MEM0_ENABLED:-1}"   # 0 = fully off: NO network calls at all (true local-only kill switch)
export MEM0_CAPTURE="${MEM0_CAPTURE:-0}"   # 0 (default) = agentic-writes-only: the hook does NOT auto-save prompts.
                                 #     Claude DECIDES + distills durable facts via the MCP add_memory tool, and the
                                 #     Stop hook writes a session summary as a safety net. Set 1 to ALSO blindly
                                 #     auto-capture every prompt (server LLM filters; noisier). Recall runs either way.
# End-of-session summary: on Stop, capture a compact session digest (task + outcome + files touched) so durable
# facts land even when nothing was captured per-prompt. The server's LLM extracts the lasting facts. Toggle off with 0.
export MEM0_SESSION_SUMMARY="${MEM0_SESSION_SUMMARY:-1}"
export MEM0_SUMMARY_MAX_CHARS="${MEM0_SUMMARY_MAX_CHARS:-2000}"  # cap on the outcome text posted at session end
# Session-start priming: the SessionStart hook injects a standing "mem0 is active" note (like CLAUDE.md) plus an
# optional digest of this project's stored memories so Claude has context from turn one. Per-prompt recall still
# pulls the specifics. MEM0_SESSION_DIGEST=0 keeps only the note; MEM0_DIGEST_LIMIT caps how many memories preface.
export MEM0_SESSION_DIGEST="${MEM0_SESSION_DIGEST:-1}"
export MEM0_DIGEST_LIMIT="${MEM0_DIGEST_LIMIT:-8}"
export MEM0_REDACT="${MEM0_REDACT:-1}"     # 1 = best-effort scrub obvious secrets (tokens, URL creds) before any send
export MEM0_SKIP_SELF="${MEM0_SKIP_SELF:-1}"  # 1 = don't CAPTURE prompts about mem0 itself (avoids meta-noise); recall unaffected
export MEM0_INSTRUCT="${MEM0_INSTRUCT:-1}"    # 1 = each turn, nudge Claude to call add_memory for durable new facts (agentic writes)
export MEM0_RECALL_LIMIT="${MEM0_RECALL_LIMIT:-6}"   # max memories injected per prompt
export MEM0_MIN_SCORE="${MEM0_MIN_SCORE:-0.5}"       # drop matches below this score. NOTE: this embedding model floors
                                 #     ~0.39 even for unrelated text, so 0.3 filtered nothing; ~0.5 keeps on-topic.
export MEM0_MAX_MEMO_CHARS="${MEM0_MAX_MEMO_CHARS:-500}"  # hard cap per recalled memory injected into context
export MEM0_DEBUG="${MEM0_DEBUG:-0}"       # 1 = append a one-line breadcrumb to MEM0_LOG when the hook self-disables
export MEM0_LOG="${MEM0_LOG:-$HOME/.claude/mem0/mem0.log}"

# Turn AUTO-DERIVE on (1) so NEW projects need ZERO config — the hook builds a per-repo
# user_id from the git repo itself. Set 0 to go back to explicit opt-in (file/env only).
export MEM0_AUTODERIVE="${MEM0_AUTODERIVE:-1}"

# Which key to auto-derive. Default "readable" gives human-friendly, automatic per-project names.
#   readable -> package.json "name" (if Node) -> "owner__repo" -> folder name   <-- DEFAULT
#               readable + automatic; CHANGES if you rename the package/repo (renamed = fresh pool).
#   github   -> "github-<numeric repo id>"  (unique + rename-safe + transfer-safe; needs gh once, then cached)
#   commit   -> "repo-<root-commit>"        (rename-safe but NOT unique: forks/templates collide; shallow-guarded)
#   name     -> "owner__repo"               (repo only; readable but CHANGES on rename)
#   pkg      -> package.json "name"          (Node only; readable but CHANGES on package rename)
# Regardless of key, captured memories also carry a readable metadata.project label
# (package.json name -> owner/repo -> folder) so you can tell projects apart when browsing.
export MEM0_REPO_KEY="${MEM0_REPO_KEY:-readable}"

# --- best-effort secret scrub (defense-in-depth; applied to BOTH capture and recall) ----
# Strips URL credentials (so pasting the token-bearing origin URL can't ship its PAT) and masks
# common token shapes. Precise patterns only — leaves ordinary prose untouched. Reads stdin.
_mem0_redact() {
  [ "${MEM0_REDACT:-1}" = "1" ] || { cat; return; }
  sed -E \
    -e 's#([a-zA-Z][a-zA-Z0-9+.-]*://)[^/@[:space:]]+@#\1#g' \
    -e 's#github_pat_[A-Za-z0-9_]{20,}#<redacted-token>#g' \
    -e 's#gh[pousr]_[A-Za-z0-9]{20,}#<redacted-token>#g' \
    -e 's#sk-[A-Za-z0-9_-]{20,}#<redacted-token>#g' \
    -e 's#AKIA[0-9A-Z]{16}#<redacted-aws-key>#g' \
    -e 's#xox[abprs]-[A-Za-z0-9-]{10,}#<redacted-slack>#g' \
    -e 's#eyJ[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{8,}#<redacted-jwt>#g'
}

# --- credential-safe helpers --------------------------------------------------
# Remote URLs may embed a token (https://TOKEN@host/owner/repo). We strip scheme + userinfo
# and keep only the host path; userinfo lives BEFORE the host so it can never reach output.
_mem0_owner_repo() {                 # -> "owner/repo" (for the GitHub API path)
  local url; url="$(git -C "$1" remote get-url origin 2>/dev/null)"; [ -n "$url" ] || return 1
  url="${url%.git}"
  printf '%s' "$url" \
    | sed -E 's#^[a-zA-Z][a-zA-Z0-9+.-]*://##' \
    | sed -E 's#^[^/@]*@##' \
    | sed -E 's#:#/#' \
    | awk -F/ 'NF>=2 { print $(NF-1)"/"$NF }'
}
_mem0_slug_remote() {                # -> "owner__repo" lowercased (the "name" strategy)
  _mem0_owner_repo "$1" | sed -E 's#/#__#g' | tr '[:upper:]' '[:lower:]' | sed -E 's#[^a-z0-9._-]#-#g'
}
_mem0_pkg_name() {                   # root package.json "name", else empty (Node projects)
  local root; root="$(git -C "$1" rev-parse --show-toplevel 2>/dev/null)" || root="$1"
  [ -f "$root/package.json" ] || { printf ''; return; }
  jq -r '.name // empty' "$root/package.json" 2>/dev/null
}
# Human-readable label for metadata (NOT the namespace key): pkg name -> owner/repo -> folder.
resolve_project_label() {
  local cwd="$1" n
  n="$(_mem0_pkg_name "$cwd")";   [ -n "$n" ] && { printf '%s' "$n"; return; }
  n="$(_mem0_owner_repo "$cwd")"; [ -n "$n" ] && { printf '%s' "$n"; return; }
  basename "$(git -C "$cwd" rev-parse --show-toplevel 2>/dev/null || printf '%s' "$cwd")"
}
# Sanitize an arbitrary label into a safe, lowercase namespace id (scoped "/" -> "__").
_mem0_sanitize_id() {
  tr '[:upper:]' '[:lower:]' | sed -E 's#/#__#g; s#[^a-z0-9._-]+#-#g; s#^-+##; s#-+$##'
}
# DEFAULT "readable" namespace: package.json name (Node) -> owner__repo -> folder name. Automatic,
# human-friendly, per-project. Not cached (so it tracks a renamed package/repo to a fresh pool).
_mem0_readable_id() {
  local cwd="$1" n
  n="$(_mem0_pkg_name "$cwd")";   [ -n "$n" ] && { printf '%s' "$n" | _mem0_sanitize_id; return; }
  n="$(_mem0_owner_repo "$cwd")"; [ -n "$n" ] && { printf '%s' "$n" | _mem0_sanitize_id; return; }
  basename "$(git -C "$cwd" rev-parse --show-toplevel 2>/dev/null || printf '%s' "$cwd")" | _mem0_sanitize_id
}
_mem0_github_id() {                  # -> numeric GitHub repo id, via gh (host-agnostic), else fail
  local or id; or="$(_mem0_owner_repo "$1")" || return 1; [ -n "$or" ] || return 1
  id="$(timeout 6 gh api "repos/$or" --jq '.id' 2>/dev/null)"
  case "$id" in (''|*[!0-9]*) return 1;; esac
  printf '%s' "$id"
}

# Per-repo user_id resolution. Most specific wins:
#   1. $MEM0_USER_ID env var               (forced override; NOTE: case-sensitive — mem0 treats
#                                            app.zynalgo.com and app.ZynAlgo.com as DIFFERENT namespaces)
#   2. pin file (first found): <repo-root>/.mem0-user  ·  <repo-root>/MEM0_USER_ID  ·  <repo-root>/.claude/mem0-user
#                                            (explicit human pin — file content IS the id; rename-safe; works even
#                                            outside git. Content "off"/"disabled"/"-"/empty => disable THIS repo.)
#   3. AUTO (MEM0_AUTODERIVE=1) per MEM0_REPO_KEY:
#        3a. <gitdir>/mem0-user-id cache    (memoized auto-derived GitHub id; only consulted when auto is on)
#        3b. github id / name / pkg / commit, with root-commit fallback when off-GitHub
#   4. otherwise (non-git with no pin, or auto off) -> empty -> hook skips
resolve_user_id() {
  local cwd="$1"
  [ -n "${MEM0_USER_ID:-}" ] && { printf '%s' "$MEM0_USER_ID"; return; }

  local root; root="$(git -C "$cwd" rev-parse --show-toplevel 2>/dev/null)" || root=""
  local base="${root:-$cwd}"
  # Explicit per-repo pin file (checked in order): a project-ROOT file ".mem0-user" / "MEM0_USER_ID",
  # else ".claude/mem0-user". File content IS the user_id. Empty/"off"/"disabled"/"-" disables this repo.
  local pinfile pin
  for pinfile in "$base/.mem0-user" "$base/MEM0_USER_ID" "$base/.claude/mem0-user"; do
    [ -f "$pinfile" ] || continue
    pin="$(tr -d '[:space:]' < "$pinfile")"
    case "$pin" in ''|off|disabled|-) printf ''; return;; esac   # explicit per-repo opt-out
    printf '%s' "$pin"; return
  done

  [ "${MEM0_AUTODERIVE:-1}" = "1" ] && [ -n "$root" ] || { printf ''; return; }

  local gitdir cache; gitdir="$(git -C "$cwd" rev-parse --absolute-git-dir 2>/dev/null)"
  cache="${gitdir:+$gitdir/mem0-user-id}"
  if [ -n "$cache" ] && [ -s "$cache" ]; then tr -d '[:space:]' < "$cache"; return; fi

  local result=""
  case "${MEM0_REPO_KEY:-readable}" in
    readable) result="$(_mem0_readable_id "$cwd")" ;;
    github)   local id; id="$(_mem0_github_id "$cwd")" && result="github-$id" ;;
    name)     result="$(_mem0_slug_remote "$cwd")" ;;
    pkg)      result="$(_mem0_pkg_name "$cwd" | _mem0_sanitize_id)" ;;
    commit)   : ;;
  esac
  if [ -z "$result" ]; then           # off-GitHub / gh unavailable -> stable root commit
    # Shallow clones don't contain the true root; max-parents=0 returns the grafted boundary (HEAD),
    # which drifts per clone and would split the namespace — refuse rather than key on an unstable id.
    if [ "$(git -C "$cwd" rev-parse --is-shallow-repository 2>/dev/null)" != "true" ]; then
      local rootc; rootc="$(git -C "$cwd" rev-list --max-parents=0 HEAD 2>/dev/null | head -1)"
      [ -n "$rootc" ] && result="repo-${rootc:0:12}"
    fi
  fi
  [ -n "$result" ] || { printf ''; return; }

  # Cache ONLY the authoritative GitHub id (stable+unique). Never freeze name/commit fallbacks.
  case "$result" in github-*) [ -n "$cache" ] && printf '%s\n' "$result" > "$cache" 2>/dev/null ;; esac
  printf '%s' "$result"
}
