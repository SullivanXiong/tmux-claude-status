#!/usr/bin/env bash
set -euo pipefail

# Debug logging (set CLAUDE_TMUX_STATUS_DEBUG=1 to enable)
DEBUG_LOG="/tmp/claude-tmux-hook-debug.log"
if [ "${CLAUDE_TMUX_STATUS_DEBUG:-0}" = "1" ]; then
  echo "[$(date +%H:%M:%S.%3N)] Hook called: $*" >> "$DEBUG_LOG"
  echo "  TMUX_PANE=$TMUX_PANE" >> "$DEBUG_LOG"
fi

# Usage: tmux-claude-status-hook.sh <EventName>
# Reads JSON from stdin (Claude Code hook input), but we only need it optionally.
EVENT="${1:-}"
INPUT="$(cat || true)"

# Must be running inside tmux for per-pane mapping
PANE_ID="${TMUX_PANE:-}"
if [[ -z "$PANE_ID" ]]; then
  [ "${CLAUDE_TMUX_STATUS_DEBUG:-0}" = "1" ] && echo "  ERROR: No TMUX_PANE" >> "$DEBUG_LOG"
  exit 0
fi

# Cache dir (override-able)
CACHE_DIR="${CLAUDE_TMUX_STATUS_CACHE_DIR:-$HOME/.cache/tmux-claude-status}"
mkdir -p "$CACHE_DIR"

# Safer filename than raw "%0"
PANE_NUM="${PANE_ID#%}"
TMUX_SERVER_PID="unknown"
if [[ -n "${TMUX:-}" ]]; then
  # TMUX is typically: socket_path,server_pid,session_id
  TMUX_SERVER_PID="${TMUX#*,}"
  TMUX_SERVER_PID="${TMUX_SERVER_PID%%,*}"
fi

STATE_FILE="$CACHE_DIR/tmux-${TMUX_SERVER_PID}-pane-${PANE_NUM}.json"
NOW="$(date +%s)"

status=""
case "$EVENT" in
  SessionStart)      status="ready"   ;;
  UserPromptSubmit)  status="working" ;;
  Stop)              status="ready"   ;;
  Notification)      status="ready"   ;;  # optional: treat as ready/waiting
  SessionEnd)
    [ "${CLAUDE_TMUX_STATUS_DEBUG:-0}" = "1" ] && echo "  SessionEnd: deleting $STATE_FILE" >> "$DEBUG_LOG"
    rm -f "$STATE_FILE"
    exit 0
    ;;
  *)
    # Unknown event: do nothing
    [ "${CLAUDE_TMUX_STATUS_DEBUG:-0}" = "1" ] && echo "  Unknown event: $EVENT" >> "$DEBUG_LOG"
    exit 0
    ;;
esac

# Best-effort session_id capture if jq exists (optional)
session_id=""
if command -v jq >/dev/null 2>&1; then
  session_id="$(printf '%s' "$INPUT" | jq -r '.session_id // empty' 2>/dev/null || true)"
fi

tmp="$(mktemp "${STATE_FILE}.tmp.XXXXXX")"
cat > "$tmp" <<EOF
{"pane_id":"$PANE_ID","status":"$status","event":"$EVENT","session_id":"$session_id","updated":$NOW}
EOF
mv "$tmp" "$STATE_FILE"

[ "${CLAUDE_TMUX_STATUS_DEBUG:-0}" = "1" ] && echo "  SUCCESS: wrote $status to $STATE_FILE" >> "$DEBUG_LOG"

# Optional: force faster UI update in tmux (safe if unsupported)
tmux refresh-client -S 2>/dev/null || true

exit 0
