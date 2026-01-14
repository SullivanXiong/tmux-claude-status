# Quick Start Guide

Get tmux-claude-status v3.0 running in 3 minutes!

## Prerequisites

```bash
# Install jq if not already installed
brew install jq  # macOS
# OR
sudo apt install jq  # Linux
```

## Installation Steps

### 1. Configure Claude Code Hooks

Edit or create `~/.claude/settings.json`:

```json
{
  "hooks": {
    "SessionStart": [
      { "hooks": [{ "type": "command", "command": "~/repos/dotfiles/tmux-plugins/tmux-claude-status/hooks/tmux-claude-status-hook.sh SessionStart" }] }
    ],
    "UserPromptSubmit": [
      { "hooks": [{ "type": "command", "command": "~/repos/dotfiles/tmux-plugins/tmux-claude-status/hooks/tmux-claude-status-hook.sh UserPromptSubmit" }] }
    ],
    "Stop": [
      { "hooks": [{ "type": "command", "command": "~/repos/dotfiles/tmux-plugins/tmux-claude-status/hooks/tmux-claude-status-hook.sh Stop" }] }
    ],
    "Notification": [
      { "hooks": [{ "type": "command", "command": "~/repos/dotfiles/tmux-plugins/tmux-claude-status/hooks/tmux-claude-status-hook.sh Notification" }] }
    ],
    "SessionEnd": [
      { "hooks": [{ "type": "command", "command": "~/repos/dotfiles/tmux-plugins/tmux-claude-status/hooks/tmux-claude-status-hook.sh SessionEnd" }] }
    ]
  }
}
```

**Note**: If you have other settings (like `includeCoAuthoredBy`, `permissions`, etc.), keep them! Just add the `"hooks"` block.

**Important**: Hooks are loaded when Claude starts. After editing settings.json:
- Restart Claude Code, OR
- Run `/hooks` to review hook configuration

### 2. Load Plugin in tmux

Add to your `~/.tmux.conf`:

```bash
# Load tmux-claude-status (place AFTER TPM)
run-shell ~/repos/dotfiles/tmux-plugins/tmux-claude-status/tmux-claude-status.tmux
```

### 3. Reload tmux

```bash
tmux source-file ~/.tmux.conf
```

### 4. Test It!

```bash
# Start Claude in a tmux window
claude

# You should see in the window tab:
# [1] ✔ claude      (initially ready)

# Submit a prompt
# [1] ... claude    (while processing)

# When Claude finishes
# [1] ✔ claude      (ready again)
```

## Troubleshooting

### Not seeing status?

```bash
# 1. Check hooks are configured
claude
# Then run: /hooks
# Should list tmux-claude-status-hook.sh for each event

# 2. Check state files are created
ls -lah ~/.cache/tmux-claude-status/
cat ~/.cache/tmux-claude-status/*.json | jq .

# 3. Verify you're in tmux
echo $TMUX_PANE
# Should output something like: %47

# 4. Check jq is installed
which jq
jq --version

# 5. Test hook manually
echo '{"session_id":"test"}' | \
  ~/repos/dotfiles/tmux-plugins/tmux-claude-status/hooks/tmux-claude-status-hook.sh UserPromptSubmit

# Then check cache file created
ls -lah ~/.cache/tmux-claude-status/
```

### Status stuck on "working"?

```bash
# Restart Claude Code
# Exit (Ctrl+D) and start again

# Or manually trigger Stop event
echo '{}' | ~/repos/dotfiles/tmux-plugins/tmux-claude-status/hooks/tmux-claude-status-hook.sh Stop
```

### Hooks not firing?

1. **Restart Claude** - Hooks load at startup
2. **Check settings.json syntax**:
   ```bash
   cat ~/.claude/settings.json | jq .
   # Should not show errors
   ```
3. **Verify hook script exists and is executable**:
   ```bash
   ls -l ~/repos/dotfiles/tmux-plugins/tmux-claude-status/hooks/tmux-claude-status-hook.sh
   # Should show -rwxr-xr-x
   ```

## Migration from v2.0

If upgrading from v2.0 (statusline-based):

1. **Remove old statusline**:
   ```bash
   rm ~/.claude/statusline.sh
   ```

2. **Remove statusLine from settings.json** - Delete the entire block:
   ```json
   "statusLine": {
     "type": "command",
     "command": "~/.claude/statusline.sh",
     "padding": 0
   }
   ```

3. **Add hooks** - Use the configuration in Step 1 above

4. **Restart Claude** - Hooks load at startup

Same tmux window tab UX, cleaner implementation!

## Customization

Hooks-based v3.0 has a simplified design. For customization options (icons, colors), see [README.md](README.md#configuration).

## Full Documentation

- See [README.md](README.md) for complete documentation
- See [../../INSTALLATION.md](../../INSTALLATION.md) for dotfiles installation guide

## What's New in v3.0?

- ✅ **No UI clutter** - Hooks don't show text in Claude's status line
- ✅ **Event-driven** - Deterministic state changes, not token inference
- ✅ **Instant updates** - Status changes immediately on events
- ✅ **Official API** - Uses Claude's hooks system (designed for this)

v2.0 worked but was a hack. v3.0 uses the right tool for the job.
