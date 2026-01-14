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

# Get file age in seconds
# Usage: file_age "/path/to/file"
file_age() {
    local file="$1"

    if [ ! -f "$file" ]; then
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
