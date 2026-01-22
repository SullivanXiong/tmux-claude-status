#!/usr/bin/env bash
#
# Helper Functions
# Utility functions used by the plugin

# Get tmux option value
# Usage: get_tmux_option "@option-name" "default-value"
get_tmux_option() {
    local option="$1"
    local default_value="$2"
    local option_value

    option_value=$(tmux show-option -gqv "$option" 2>/dev/null)

    if [ -z "$option_value" ]; then
        echo "$default_value"
    else
        echo "$option_value"
    fi
}

# Debug logging
# Writes to log file if debug mode is enabled
# Usage: debug_log "message"
debug_log() {
    local debug_enabled
    debug_enabled=$(get_tmux_option "@claude-status-debug" "false")

    if [ "$debug_enabled" = "true" ]; then
        local timestamp
        timestamp=$(date '+%Y-%m-%d %H:%M:%S')
        local log_file="/tmp/tmux-claude-status-debug.log"
        echo "[$timestamp] $*" >> "$log_file"
    fi
}

# Check if command exists
# Usage: command_exists "jq"
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Parse JSON safely with jq
# Usage: parse_json "$json_string" ".field" "default"
parse_json() {
    local json="$1"
    local query="$2"
    local default="$3"

    if ! command_exists jq; then
        echo "$default"
        return 1
    fi

    echo "$json" | jq -r "$query // \"$default\"" 2>/dev/null || echo "$default"
}

# Get file or directory age in seconds
# Usage: file_age "/path/to/file"
file_age() {
    local file="$1"

    if [ ! -e "$file" ]; then
        echo "-1"
        return
    fi

    local now
    local file_time

    now=$(date +%s)

    # macOS vs Linux stat command
    if [[ "$OSTYPE" == "darwin"* ]]; then
        file_time=$(stat -f %m "$file" 2>/dev/null || echo "0")
    else
        file_time=$(stat -c %Y "$file" 2>/dev/null || echo "0")
    fi

    echo $((now - file_time))
}

# Clean up old cache files
# Usage: cleanup_cache "/path/to/cache/dir" max_age_seconds
cleanup_cache() {
    local cache_dir="$1"
    local max_age="${2:-86400}"  # Default 1 day

    if [ ! -d "$cache_dir" ]; then
        return
    fi

    find "$cache_dir" -name '*.json' -type f -mtime "+${max_age}" -delete 2>/dev/null || true
}

# Sanitize pane ID for use in filenames
# Removes % prefix and any other special characters
# Usage: sanitize_pane_id "%1"
sanitize_pane_id() {
    local pane_id="$1"
    echo "${pane_id//[^a-zA-Z0-9]/}"
}

# Atomic write to state file using mkdir-based locking for cross-platform support
# Usage: atomic_write_state "/path/to/state.json" '{"key":"value"}'
atomic_write_state() {
    local state_file="$1"
    local content="$2"
    local lock_dir="${state_file%.json}.lock"
    local debug_log="/tmp/claude-tmux-hook-debug.log"
    local max_wait=2  # Maximum 2 seconds
    local start_time=$(date +%s)
    local lock_acquired=0

    # Clean up stale locks (older than 5 seconds)
    if [ -d "$lock_dir" ]; then
        local lock_age=$(file_age "$lock_dir")
        if [ "$lock_age" -gt 5 ]; then
            rmdir "$lock_dir" 2>/dev/null || true
        fi
    fi

    # Try to acquire lock (mkdir is atomic)
    while [ $lock_acquired -eq 0 ]; do
        if mkdir "$lock_dir" 2>/dev/null; then
            lock_acquired=1
            break
        fi

        # Check timeout
        local now=$(date +%s)
        local elapsed=$((now - start_time))
        if [ $elapsed -ge $max_wait ]; then
            if [ "${CLAUDE_TMUX_STATUS_DEBUG:-0}" = "1" ]; then
                echo "[$(date +%Y-%m-%d\ %H:%M:%S)] ERROR: Failed to acquire lock for $state_file after ${max_wait}s" >> "$debug_log"
            fi
            return 1
        fi

        # Small random sleep to prevent thundering herd (1-50ms)
        sleep 0.0$(( (RANDOM % 50) + 1 ))
    done

    # Write to temp file and atomically move to final location
    local tmp="$(mktemp "${state_file}.tmp.XXXXXX")"
    echo "$content" > "$tmp"
    mv "$tmp" "$state_file"

    # Release lock
    rmdir "$lock_dir" 2>/dev/null || true

    return 0
}

# Structured error logging
# Usage: log_error "component" "error message" "optional context"
log_error() {
    local component="$1"
    local error="$2"
    local context="${3:-}"
    local debug_log="/tmp/claude-tmux-hook-debug.log"

    if [ "${CLAUDE_TMUX_STATUS_DEBUG:-0}" = "1" ]; then
        cat >> "$debug_log" <<EOF
[$(date +%Y-%m-%d\ %H:%M:%S)] ERROR [$component]
  Error: $error
  Context: $context
  TMUX_PANE=${TMUX_PANE:-UNSET}
  TMUX=${TMUX:-UNSET}
  Caller: $(caller 0)
EOF
    fi
}
