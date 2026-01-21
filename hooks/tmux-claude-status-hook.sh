#!/usr/bin/env bash
set -euo pipefail

# Source helper functions
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../scripts/helpers.sh"

# Debug logging (set CLAUDE_TMUX_STATUS_DEBUG=1 to enable)
DEBUG_LOG="/tmp/claude-tmux-hook-debug.log"
if [ "${CLAUDE_TMUX_STATUS_DEBUG:-0}" = "1" ]; then
  echo "[$(date +%H:%M:%S.%3N)] Hook called: $*" >> "$DEBUG_LOG"
  echo "  TMUX_PANE=${TMUX_PANE:-UNSET}" >> "$DEBUG_LOG"
fi

# Usage: tmux-claude-status-hook.sh <EventName>
# Reads JSON from stdin (Claude Code hook input), but we only need it optionally.
EVENT="${1:-}"
INPUT="$(cat || true)"

# Must be running inside tmux for per-pane mapping
# 3-layer pane ID resolution with fallbacks
PANE_ID="${TMUX_PANE:-}"

# Fallback 1: Query tmux directly
if [[ -z "$PANE_ID" ]] && [[ -n "${TMUX:-}" ]]; then
    PANE_ID="$(tmux display-message -p '#{pane_id}' 2>/dev/null || true)"
    [ "${CLAUDE_TMUX_STATUS_DEBUG:-0}" = "1" ] && [[ -n "$PANE_ID" ]] && echo "  Fallback 1: resolved PANE_ID=$PANE_ID" >> "$DEBUG_LOG"
fi

# Fallback 2: Match by TTY
if [[ -z "$PANE_ID" ]] && [[ -n "${TMUX:-}" ]]; then
    MY_TTY="$(tty 2>/dev/null || true)"
    if [[ -n "$MY_TTY" ]]; then
        PANE_ID="$(tmux list-panes -a -F '#{pane_id} #{pane_tty}' 2>/dev/null | \
                   grep "$MY_TTY" | awk '{print $1}' | head -1 || true)"
        [ "${CLAUDE_TMUX_STATUS_DEBUG:-0}" = "1" ] && [[ -n "$PANE_ID" ]] && echo "  Fallback 2: resolved PANE_ID=$PANE_ID via TTY=$MY_TTY" >> "$DEBUG_LOG"
    fi
fi

# Log failure if unresolved
if [[ -z "$PANE_ID" ]]; then
    log_error "pane_resolution" "Could not resolve TMUX_PANE" "TMUX_PANE=${TMUX_PANE:-}, TMUX=${TMUX:-}, PPID=$PPID"
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

# Write state atomically with flock
STATE_JSON="{\"pane_id\":\"$PANE_ID\",\"status\":\"$status\",\"event\":\"$EVENT\",\"session_id\":\"$session_id\",\"updated\":$NOW}"

if atomic_write_state "$STATE_FILE" "$STATE_JSON"; then
    [ "${CLAUDE_TMUX_STATUS_DEBUG:-0}" = "1" ] && echo "  SUCCESS: wrote $status to $STATE_FILE" >> "$DEBUG_LOG"
else
    log_error "state_write" "Failed to write state atomically" "STATE_FILE=$STATE_FILE, status=$status, event=$EVENT"
fi

# Optional: force faster UI update in tmux (safe if unsupported)
tmux refresh-client -S 2>/dev/null || true

exit 0
