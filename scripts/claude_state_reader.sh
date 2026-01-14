#!/usr/bin/env bash
set -euo pipefail

TARGET="${1:-}"        # can be a pane id (%3) OR a window id (@1)
MODE="${2:-inactive}"  # active|inactive

CACHE_DIR="${CLAUDE_TMUX_STATUS_CACHE_DIR:-$HOME/.cache/tmux-claude-status}"

# Resolve pane id if we were passed a window id
PANE_ID=""
if [[ "$TARGET" == @* ]]; then
  # target is a window id - search for a Claude pane in this window
  # This allows showing Claude status even when focused on a different pane (e.g., terminal)
  while IFS= read -r pane; do
    pane_cmd="$(tmux display-message -p -t "$pane" '#{pane_current_command}' 2>/dev/null || true)"
    case "$pane_cmd" in
      claude|node)
        PANE_ID="$pane"
        break
        ;;
    esac
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

# Derive same filename as hook script
PANE_NUM="${PANE_ID#%}"
TMUX_SERVER_PID="unknown"
if [[ -n "${TMUX:-}" ]]; then
  TMUX_SERVER_PID="${TMUX#*,}"
  TMUX_SERVER_PID="${TMUX_SERVER_PID%%,*}"
fi

STATE_FILE="$CACHE_DIR/tmux-${TMUX_SERVER_PID}-pane-${PANE_NUM}.json"
[[ -f "$STATE_FILE" ]] || exit 0

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
