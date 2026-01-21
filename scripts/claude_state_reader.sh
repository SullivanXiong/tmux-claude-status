#!/usr/bin/env bash
set -euo pipefail

# Source helper functions
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/helpers.sh"

TARGET="${1:-}"        # can be a pane id (%3) OR a window id (@1)
MODE="${2:-inactive}"  # active|inactive

CACHE_DIR="${CLAUDE_TMUX_STATUS_CACHE_DIR:-$HOME/.cache/tmux-claude-status}"

# Resolve pane id if we were passed a window id
PANE_ID=""
if [[ "$TARGET" == @* ]]; then
  # target is a window id - search for a pane with an active Claude session
  # Check for state file existence rather than command name, since:
  # - cwf/other wrappers run as bash/zsh with Claude as subprocess
  # - Random node apps would falsely match "node" check
  # - State files only exist when Claude Code hooks create them

  # Get TMUX_SERVER_PID for state file path construction
  TMUX_SERVER_PID="unknown"
  if [[ -n "${TMUX:-}" ]]; then
    TMUX_SERVER_PID="${TMUX#*,}"
    TMUX_SERVER_PID="${TMUX_SERVER_PID%%,*}"
  fi

  while IFS= read -r pane; do
    pane_num="${pane#%}"
    state_file="$CACHE_DIR/tmux-${TMUX_SERVER_PID}-pane-${pane_num}.json"
    if [[ -f "$state_file" ]]; then
      PANE_ID="$pane"
      break
    fi
  done < <(tmux list-panes -t "$TARGET" -F '#{pane_id}' 2>/dev/null || true)

  # Fallback: if no Claude pane found, use the active pane (original behavior)
  if [[ -z "$PANE_ID" ]]; then
    PANE_ID="$(tmux display-message -p -t "$TARGET" '#{pane_id}' 2>/dev/null || true)"
  fi
else
  # assume pane id
  PANE_ID="$TARGET"
fi

[[ -n "$PANE_ID" ]] || exit 0

# Derive same filename as hook script (may be recalculated from above if window search)
PANE_NUM="${PANE_ID#%}"
TMUX_SERVER_PID="unknown"
if [[ -n "${TMUX:-}" ]]; then
  TMUX_SERVER_PID="${TMUX#*,}"
  TMUX_SERVER_PID="${TMUX_SERVER_PID%%,*}"
fi

STATE_FILE="$CACHE_DIR/tmux-${TMUX_SERVER_PID}-pane-${PANE_NUM}.json"
[[ -f "$STATE_FILE" ]] || exit 0

# Validate state file age (max 1 hour)
if command -v jq >/dev/null 2>&1; then
    updated=$(jq -r '.updated // 0' "$STATE_FILE" 2>/dev/null || echo 0)
    now=$(date +%s)
    age=$((now - updated))

    if [ "$age" -gt 3600 ]; then
        rm -f "$STATE_FILE" 2>/dev/null
        rm -rf "${STATE_FILE%.json}.lock" 2>/dev/null
        exit 0
    fi
fi

# Validate pane still exists in tmux
if ! tmux list-panes -a -F '#{pane_id}' 2>/dev/null | grep -q "^${PANE_ID}$"; then
    rm -f "$STATE_FILE" 2>/dev/null
    rm -rf "${STATE_FILE%.json}.lock" 2>/dev/null
    exit 0
fi

# State file exists = Claude session is active (hooks manage lifecycle)
# No need to check pane_current_command since cwf runs as bash/zsh but has Claude as subprocess

# Check if jq is available
if ! command -v jq >/dev/null 2>&1; then
  exit 0
fi

status="$(jq -r '.status // empty' "$STATE_FILE" 2>/dev/null || true)"
[[ -n "$status" ]] || exit 0

icon=""
color="default"
case "$status" in
  working) icon="..."; color="yellow" ;;
  ready)   icon="✔";   color="green"  ;;
  *) exit 0 ;;
esac

if [[ "$MODE" == "active" ]]; then
  # white/bold when current window
  printf "#[fg=white,bold]%s#[fg=default,nobold]" "$icon"
else
  printf "#[fg=%s]%s#[fg=default]" "$color" "$icon"
fi
