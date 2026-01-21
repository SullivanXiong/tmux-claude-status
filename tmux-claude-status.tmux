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

# Source helper functions
source "$CURRENT_DIR/scripts/helpers.sh"

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
    # Use sed with | delimiter to avoid issues with / in file paths
    echo "$fmt" | sed "s|#{window_name}|${insert}#{window_name}|"
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

# Initialize cache directory and clean stale files
init_cache() {
    local cache_dir="${CLAUDE_TMUX_STATUS_CACHE_DIR:-$HOME/.cache/tmux-claude-status}"
    mkdir -p "$cache_dir"

    # Get current pane IDs
    local current_panes=$(mktemp)
    tmux list-panes -a -F '#{pane_id}' 2>/dev/null > "$current_panes" || true

    # Clean orphaned files (older than 60 minutes OR pane no longer exists)
    find "$cache_dir" -name "tmux-*.json" -mmin +60 2>/dev/null | while read -r state_file; do
        # Extract pane_id from state file if possible
        if command -v jq >/dev/null 2>&1; then
            pane_id=$(jq -r '.pane_id // empty' "$state_file" 2>/dev/null || true)

            if [[ -n "$pane_id" ]]; then
                # Check if pane still exists
                if ! grep -q "^${pane_id}$" "$current_panes" 2>/dev/null; then
                    rm -f "$state_file" 2>/dev/null
                    rm -rf "${state_file%.json}.lock" 2>/dev/null
                fi
            fi
        else
            # If jq not available, just remove old files
            rm -f "$state_file" 2>/dev/null
        fi
    done

    # Clean any orphaned lock directories
    find "$cache_dir" -name "*.lock" -type d -mmin +60 -exec rmdir {} \; 2>/dev/null || true

    rm -f "$current_panes"
}

init_cache &
