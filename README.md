# tmux-claude-status

Real-time Claude Code status monitoring in tmux window tabs using official hooks API.

## Features

- **Event-driven** - Uses Claude Code's official hooks system for deterministic state changes
- **No UI clutter** - Hooks run silently, no visible text in Claude's status line
- **Per-window tracking** - Each tmux window shows its own Claude instance status
- **Simple states** - Working (`...`) or Ready (`✔`) - no complex token analysis needed
- **Instant updates** - Status changes immediately when events fire
- **Low overhead** - Hooks run only on actual events, not continuous polling
- **TPM compatible** - Works as a standard tmux plugin

## Status Indicators

| Icon | Meaning | When Shown |
|------|---------|------------|
| `...` | Working | Claude is processing your prompt, generating response, or using tools |
| `✔` | Ready | Claude finished and is waiting for your next prompt |
| (empty) | No Claude | No Claude running in this pane, or pane switched to another command |

### Colors

- **Active tab**: White bold (high visibility)
- **Inactive, working**: Yellow `...`
- **Inactive, ready**: Green `✔`

## Prerequisites

1. **tmux** 3.0+
2. **jq** - JSON processor
   ```bash
   # macOS
   brew install jq

   # Linux
   sudo apt install jq     # Debian/Ubuntu
   sudo pacman -S jq       # Arch
   ```
3. **Claude Code CLI** with hooks configured

## Installation

### Option 1: TPM (Recommended)

If you use [Tmux Plugin Manager](https://github.com/tmux-plugins/tpm):

**Add to your `~/.tmux.conf`:**
```bash
set -g @plugin 'SullivanXiong/tmux-claude-status'
```

**Install the plugin:**
- In tmux: `Ctrl+A` then `I` (capital i) to install plugins
- Or from command line: `~/.tmux/plugins/tpm/bin/install_plugins`

The plugin will be installed to `~/.tmux/plugins/tmux-claude-status/`.

### Option 2: Manual Installation

Clone the repository:
```bash
git clone https://github.com/SullivanXiong/tmux-claude-status.git ~/.tmux/plugins/tmux-claude-status
```

**Add to your `~/.tmux.conf`:**
```bash
run-shell ~/.tmux/plugins/tmux-claude-status/tmux-claude-status.tmux
```

**Reload tmux configuration:**
```bash
tmux source-file ~/.tmux.conf
```

### Configure Claude Code Hooks

Claude Code's hooks system runs commands on specific lifecycle events. Configure it to track state.

**Edit or create `~/.claude/settings.json`:**
```json
{
  "hooks": {
    "SessionStart": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "~/.tmux/plugins/tmux-claude-status/hooks/tmux-claude-status-hook.sh SessionStart"
          }
        ]
      }
    ],
    "UserPromptSubmit": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "~/.tmux/plugins/tmux-claude-status/hooks/tmux-claude-status-hook.sh UserPromptSubmit"
          }
        ]
      }
    ],
    "Stop": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "~/.tmux/plugins/tmux-claude-status/hooks/tmux-claude-status-hook.sh Stop"
          }
        ]
      }
    ],
    "Notification": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "~/.tmux/plugins/tmux-claude-status/hooks/tmux-claude-status-hook.sh Notification"
          }
        ]
      }
    ],
    "SessionEnd": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "~/.tmux/plugins/tmux-claude-status/hooks/tmux-claude-status-hook.sh SessionEnd"
          }
        ]
      }
    ]
  }
}
```

**Note:** If you installed manually to a different location, adjust the paths accordingly.

**Important**: After updating settings.json, restart Claude Code or run `/hooks` to review hook configuration.

### Test It

```bash
# Start Claude in a tmux window
claude

# Watch the window tab - status should appear!
# You should see: [1] ✔ claude-session   (initially ready)

# Submit a prompt
# Status changes to: [1] ... claude-session  (while processing)

# When Claude finishes
# Status returns to: [1] ✔ claude-session   (ready again)
```

## How It Works

### Architecture

```
┌──────────────────────┐
│   Claude Code        │ Lifecycle events
│   (SessionStart,     │
│    UserPromptSubmit, │
│    Stop, etc.)       │
└──────────┬───────────┘
           │ Triggers hook
           ▼
┌──────────────────────┐
│  hooks/              │ Event handler
│  tmux-claude-        │ - UserPromptSubmit → "working"
│  status-hook.sh      │ - Stop → "ready"
└──────────┬───────────┘ - SessionEnd → delete state
           │
           ▼
┌──────────────────────┐
│  ~/.cache/           │ State files per pane
│  tmux-claude-status/ │ (keyed by tmux server + pane)
│  *.json              │
└──────────┬───────────┘
           │
           ▼
┌──────────────────────┐
│  scripts/            │ Reads cache, formats display
│  claude_state_       │ - Checks pane is running Claude
│  reader.sh           │ - Resolves window_id to active pane
└──────────┬───────────┘ - Returns formatted status
           │
           ▼
┌──────────────────────┐
│  Tmux window tabs    │ [1] ... claude  [2] ✔ done
└──────────────────────┘
```

### Event-Driven State Tracking

The plugin uses Claude Code's official hooks API for deterministic state changes:

| Hook Event | State Transition | tmux Display |
|------------|------------------|--------------|
| `SessionStart` | → ready | `✔` (green) |
| `UserPromptSubmit` | → working | `...` (yellow) |
| `Stop` | → ready | `✔` (green) |
| `Notification` | → ready | `✔` (green) |
| `SessionEnd` | → (delete state) | (empty) |

**Why hooks?** Claude's hooks system is designed for automation and runs on actual lifecycle events. This is far more reliable than:
- Token delta inference (what v2.0 did)
- Process observation (what v1.0 attempted)
- Polling-based heuristics

Hooks fire exactly when they should, giving you clean state transitions with zero guesswork.

## Debugging

The plugin includes comprehensive debug logging to help troubleshoot issues. Enable it with:

```bash
export CLAUDE_TMUX_STATUS_DEBUG=1
claude  # Start Claude with debugging enabled
```

Debug logs are written to `/tmp/claude-tmux-hook-debug.log` and include:
- Hook invocation events (SessionStart, UserPromptSubmit, Stop, etc.)
- Pane ID resolution attempts and fallbacks
- State file operations (reads, writes, lock acquisitions)
- Error conditions (failed locks, missing panes, stale files)

**View debug logs in real-time:**
```bash
tail -f /tmp/claude-tmux-hook-debug.log
```

**Example debug output:**
```
[12:37:21.3N] Hook called: SessionStart
  TMUX_PANE=UNSET
  Fallback 1: resolved PANE_ID=%50
  SUCCESS: wrote ready to /Users/.../tmux-1205-pane-50.json
```

### State File Validation

The plugin automatically validates and cleans up stale state files:

1. **Age validation**: Files older than 1 hour are automatically removed
2. **Pane existence**: Files for panes that no longer exist are cleaned up
3. **Lock cleanup**: Stale lock directories (>60 minutes) are removed

This prevents issues from:
- Crashed Claude sessions leaving orphaned files
- Pane splits/closes creating stale references
- System restarts with leftover cache

**Manual cleanup:**
```bash
# Remove all state files
rm -rf ~/.cache/tmux-claude-status/*.json

# Remove lock directories
rm -rf ~/.cache/tmux-claude-status/*.lock

# Restart tmux plugin
tmux source-file ~/.tmux.conf
```

## Troubleshooting

### Status not showing

1. **Check hooks are configured:**
   ```bash
   # Start Claude and run:
   /hooks

   # You should see tmux-claude-status-hook.sh listed for each event
   ```

2. **Check hook script is executable:**
   ```bash
   ls -l ~/.tmux/plugins/tmux-claude-status/hooks/tmux-claude-status-hook.sh
   # Should show -rwxr-xr-x

   chmod +x ~/.tmux/plugins/tmux-claude-status/hooks/tmux-claude-status-hook.sh
   ```

3. **Check state files are being created:**
   ```bash
   ls -lah ~/.cache/tmux-claude-status/
   # Should show .json files while Claude is running

   cat ~/.cache/tmux-claude-status/*.json | jq .
   # Should show: {"pane_id":"%47","status":"working","event":"UserPromptSubmit",...}
   ```

4. **Verify you're in a tmux pane:**
   ```bash
   echo $TMUX_PANE
   # Should output something like: %47

   # Hooks only work when Claude is running inside tmux
   ```

5. **Check jq is installed:**
   ```bash
   which jq
   jq --version
   ```

### Status stuck on "working"

If the status never changes back to ready after Claude finishes:

1. **Check hook fired:**
   ```bash
   # Look at the updated timestamp in the state file
   cat ~/.cache/tmux-claude-status/*.json | jq '.updated'

   # Compare to current time:
   date +%s

   # If updated is old, the Stop hook may not have fired
   ```

2. **Restart Claude:**
   ```bash
   # Exit and restart Claude Code
   # This triggers SessionEnd (cleanup) and SessionStart (reset)
   ```

3. **Manually test hook:**
   ```bash
   echo '{"session_id":"test"}' | \
     ~/.tmux/plugins/tmux-claude-status/hooks/tmux-claude-status-hook.sh Stop

   # Check state file updated to "ready"
   cat ~/.cache/tmux-claude-status/*.json | jq '.status'
   ```

### Plugin not loading

1. **Check load order in `.tmux.conf`:**
   ```bash
   grep -n "claude-status\|tpm" ~/.tmux.conf
   ```

   Plugin MUST load AFTER TPM (if using themes):
   ```bash
   run '~/.tmux/plugins/tpm/tpm'
   run-shell ~/.tmux/plugins/tmux-claude-status/tmux-claude-status.tmux
   ```

2. **Check file permissions:**
   ```bash
   ls -l ~/.tmux/plugins/tmux-claude-status/*.tmux
   ls -l ~/.tmux/plugins/tmux-claude-status/scripts/*.sh
   ls -l ~/.tmux/plugins/tmux-claude-status/hooks/*.sh
   ```

3. **Test plugin manually:**
   ```bash
   ~/.tmux/plugins/tmux-claude-status/tmux-claude-status.tmux

   # Check window formats updated:
   tmux show-option -gv window-status-format
   # Should contain: claude_state_reader.sh
   ```

### Hooks not firing

1. **Enable debug mode** to see what's happening:
   ```bash
   export CLAUDE_TMUX_STATUS_DEBUG=1
   claude

   # In another terminal, watch the debug log
   tail -f /tmp/claude-tmux-hook-debug.log
   ```

2. **Restart Claude Code** - Hooks are loaded at startup:
   ```bash
   # Exit Claude (Ctrl+D)
   # Start again
   claude

   # Check hooks loaded
   /hooks
   ```

3. **Check settings.json syntax:**
   ```bash
   # Validate JSON
   cat ~/.claude/settings.json | jq .
   # Should not show syntax errors
   ```

4. **Check hook paths are correct:**
   ```bash
   # Verify the path in settings.json exists
   ls -l ~/.tmux/plugins/tmux-claude-status/hooks/tmux-claude-status-hook.sh
   ```

### Status showing incorrect state

If the status shows "working" when Claude is ready, or vice versa:

1. **Check for stale state files:**
   ```bash
   # List state files with ages
   ls -lah ~/.cache/tmux-claude-status/*.json

   # View current state
   cat ~/.cache/tmux-claude-status/*.json | jq .

   # Files older than 1 hour are automatically removed on next read
   ```

2. **Verify pane ID matches:**
   ```bash
   # Get your current pane ID
   echo $TMUX_PANE

   # Check if state file exists for this pane
   ls ~/.cache/tmux-claude-status/tmux-*-pane-${TMUX_PANE#%}.json
   ```

3. **Test hook execution manually:**
   ```bash
   export CLAUDE_TMUX_STATUS_DEBUG=1

   # Simulate different events
   echo '{}' | ~/.tmux/plugins/tmux-claude-status/hooks/tmux-claude-status-hook.sh SessionStart
   echo '{}' | ~/.tmux/plugins/tmux-claude-status/hooks/tmux-claude-status-hook.sh UserPromptSubmit
   echo '{}' | ~/.tmux/plugins/tmux-claude-status/hooks/tmux-claude-status-hook.sh Stop

   # Check debug log
   cat /tmp/claude-tmux-hook-debug.log
   ```

### Running in wrapper scripts

If Claude is launched via a wrapper script (like `cwf`), the plugin uses fallback pane resolution:

1. **Fallback 1**: Queries tmux directly for pane ID
2. **Fallback 2**: Matches by TTY if direct query fails

This is logged when `CLAUDE_TMUX_STATUS_DEBUG=1`:
```
TMUX_PANE=UNSET
Fallback 1: resolved PANE_ID=%50
```

If fallback resolution fails, check debug logs for errors:
```bash
tail -f /tmp/claude-tmux-hook-debug.log | grep ERROR
```

## Performance

- **Update latency**: Instant (event-driven, not polled)
- **CPU overhead**: Minimal (hooks run only on events, not continuously)
- **Memory**: Negligible (small JSON files, ~100 bytes per pane)
- **Disk I/O**: ~100 bytes written per state change per pane

## Comparison: v1.0 vs v2.0 vs v3.0

### v1.0 (External Observation - Failed)

- Used `ps` to check process state → Doesn't work with Node.js event loop
- Used `lsof` to check stdin → Can't distinguish blocked vs waiting
- Used time windows in `history.jsonl` → Caused flashing between states
- Result: **Unreliable, frequent flashing**

### v2.0 (Statusline API - Hacky)

- Used `/statusline` API for internal state access
- Analyzed token deltas to infer state (tokens_out ↑ = generating, etc.)
- Needed 3-second grace period to prevent flashing during tool calls
- **Problem**: Cluttered Claude's UI with visible status text
- Result: **Worked, but was a hack - statusline isn't meant for IPC**

### v3.0 (Hooks API - Official)

- Uses official hooks system designed for automation
- Deterministic state changes based on actual events
- No token analysis, no grace periods, no inference needed
- No UI clutter - hooks are silent
- Instant state transitions
- Result: **Clean, reliable, officially supported**

## Migration from v2.0

If you're upgrading from v2.0 (statusline-based):

### Changes

1. **Remove statusline**: Delete `~/.claude/statusline.sh` and remove `"statusLine"` block from settings.json
2. **Add hooks**: Configure hooks block as shown in installation (Step 2)
3. **Restart Claude**: Hooks load at startup, run `/hooks` to verify
4. **Same UX**: tmux tabs still show `...` / `✔` in the same position

### Breaking Changes

- **No fine-grained states**: v2.0 showed "generating", "thinking", "loading" - v3.0 only shows "working" vs "ready"
- **No token/cost display**: v3.0 focuses on simple status indicator only
- **Different cache location**: v3.0 uses `~/.cache/tmux-claude-status/` instead of plugin's cache/ directory

### Benefits

- ✅ No visible text in Claude's status line
- ✅ Deterministic state tracking (not token inference)
- ✅ Instant state changes (no polling delay)
- ✅ Uses officially supported API (hooks, not statusline)

## File Structure

```
~/.tmux/plugins/tmux-claude-status/
├── tmux-claude-status.tmux      # Main entry point (TPM compatible)
├── hooks/
│   └── tmux-claude-status-hook.sh  # Event handler for Claude hooks
├── scripts/
│   ├── claude_state_reader.sh   # Reads state, formats display
│   └── helpers.sh               # Utility functions (legacy, mostly unused)
├── LICENSE                      # MIT License
└── README.md                    # This file
```

**State cache (generated at runtime):**
```
~/.cache/tmux-claude-status/
└── *.json                       # Per-pane state files (created automatically)
```

**Note:** The cache directory is created automatically when Claude Code hooks fire. You don't need to create it manually.

## Why v3.0?

The v2.0 plugin revealed a key insight: **Claude's `/statusline` API is designed for UI rendering, not IPC**. Using it as a state signal works, but it's a hack:

- The status text is visible in Claude's UI (clutters the display)
- Requires parsing Claude's internal JSON to infer state from token deltas
- Needs grace periods and heuristics to avoid flashing

**Claude's hooks system solves this properly** - it's designed for automation and integration. Hooks:
- Run on actual lifecycle events (UserPromptSubmit, Stop, etc.)
- Are completely silent (no UI rendering)
- Provide deterministic state transitions (no inference needed)
- Are officially supported for this exact use case

v3.0 uses the right tool for the job.

## Related Documentation

- [Claude Code Hooks Docs](https://code.claude.com/docs/en/hooks.md)
- [QUICKSTART Guide](./QUICKSTART.md)
- [GitHub Repository](https://github.com/SullivanXiong/tmux-claude-status)

## Credits

- Built with [Claude Code's hooks API](https://code.claude.com/docs/en/hooks.md)
- Inspired by [samleeney/claude-tmux-status](https://github.com/samleeney/claude-tmux-status) (also uses hooks)
- Learned from v1.0's external observation and v2.0's statusline challenges

## License

MIT License - See [LICENSE](./LICENSE) file for details.
