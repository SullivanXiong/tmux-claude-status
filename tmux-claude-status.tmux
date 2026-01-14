#!/usr/bin/env bash
#
# tmux-claude-status v3.0
# Main plugin entry point
#
# Integrates with Claude Code's hooks API to display real-time
# status in tmux window tabs.

set -euo pipefail

CURRENT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
READER="$CURRENT_DIR/scripts/claude_state_reader.sh"

# Use window_id so the reader can resolve the active pane reliably
STATUS_INACTIVE="#($READER '#{window_id}' inactive)"
STATUS_ACTIVE="#($READER '#{window_id}' active)"

inject_before_window_name() {
  local fmt="$1"
  local insert="$2" # includes surrounding spaces

  # avoid double-inject
  if [[ "$fmt" == *"claude_state_reader.sh"* ]]; then
    echo "$fmt"
    return
  fi

  # Most formats contain #W or #{window_name}; inject before that.
  if [[ "$fmt" == *"#W"* ]]; then
    echo "${fmt/\#W/${insert}#W}"
    return
  fi

  if [[ "$fmt" == *"#{window_name}"* ]]; then
    # Use sed for #{window_name} to avoid bash brace expansion issues
    echo "$fmt" | sed "s/#{window_name}/${insert}#{window_name}/"
    return
  fi

  # fallback: append
  echo "${fmt}${insert}"
}

fmt="$(tmux show-option -gqv window-status-format)"
cur="$(tmux show-option -gqv window-status-current-format)"

new_fmt="$(inject_before_window_name "$fmt" " $STATUS_INACTIVE ")"
new_cur="$(inject_before_window_name "$cur" " $STATUS_ACTIVE ")"

tmux set-option -gq window-status-format "$new_fmt"
tmux set-option -gq window-status-current-format "$new_cur"

# Set up periodic cleanup of stale cache files (older than 7 days)
# This prevents accumulation of abandoned state files
CACHE_DIR="${CLAUDE_TMUX_STATUS_CACHE_DIR:-$HOME/.cache/tmux-claude-status}"
if [[ -d "$CACHE_DIR" ]]; then
  find "$CACHE_DIR" -name '*.json' -mtime +7 -delete 2>/dev/null &
fi
