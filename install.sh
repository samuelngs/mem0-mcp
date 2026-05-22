#!/usr/bin/env bash
set -euo pipefail

MEM0_HOME="${MEM0_HOME:-$HOME/.mem0}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

echo "mem0 Claude Code Integration — Installer"
echo "=========================================="
echo ""

# Check prerequisites
if ! command -v python3 >/dev/null 2>&1; then
  echo "Error: python3 is required but not found."
  exit 1
fi

if ! command -v jq >/dev/null 2>&1; then
  echo "Error: jq is required but not found."
  echo "  macOS:  brew install jq"
  echo "  Linux:  apt install jq / yum install jq"
  exit 1
fi

if ! command -v claude >/dev/null 2>&1; then
  echo "Warning: claude CLI not found. You'll need to configure MCP manually."
  CLAUDE_CLI=false
else
  CLAUDE_CLI=true
fi

# Prompt for config
if [ -z "${MEM0_BASE_URL:-}" ]; then
  read -rp "mem0 server URL (e.g., https://mem0.example.com): " MEM0_BASE_URL
fi

if [ -z "${MEM0_API_KEY:-}" ]; then
  read -rp "mem0 API key: " MEM0_API_KEY
fi

if [ -z "$MEM0_BASE_URL" ] || [ -z "$MEM0_API_KEY" ]; then
  echo "Error: MEM0_BASE_URL and MEM0_API_KEY are required."
  exit 1
fi

# Test connectivity
echo ""
echo "Testing connection to $MEM0_BASE_URL..."
HTTP_CODE=$(python3 -c "
import json, urllib.request, urllib.error
req = urllib.request.Request(
    '${MEM0_BASE_URL}/entities',
    headers={'X-API-Key': '${MEM0_API_KEY}', 'Content-Type': 'application/json'},
)
try:
    with urllib.request.urlopen(req, timeout=10) as r:
        print(r.status)
except urllib.error.HTTPError as e:
    print(e.code)
except Exception as e:
    print('0')
" 2>/dev/null)

if [ "$HTTP_CODE" = "0" ]; then
  echo "Error: Cannot reach $MEM0_BASE_URL. Check URL and network."
  exit 1
elif [ "$HTTP_CODE" = "401" ] || [ "$HTTP_CODE" = "403" ]; then
  echo "Error: Authentication failed. Check your API key."
  exit 1
else
  echo "Connected (HTTP $HTTP_CODE)."
fi

# Copy files
echo ""
echo "Installing to $MEM0_HOME..."
mkdir -p "$MEM0_HOME/hooks"

cp "$SCRIPT_DIR/mcp_bridge.py" "$MEM0_HOME/mcp_bridge.py"
cp "$SCRIPT_DIR/hooks/"*.sh "$MEM0_HOME/hooks/"
chmod +x "$MEM0_HOME/hooks/"*.sh

echo "Files installed."

# Register MCP server
echo ""
if [ "$CLAUDE_CLI" = "true" ]; then
  echo "Registering mem0 MCP server..."
  claude mcp add mem0 --scope user \
    -e MEM0_BASE_URL="$MEM0_BASE_URL" \
    -e MEM0_API_KEY="$MEM0_API_KEY" \
    -- python3 "$MEM0_HOME/mcp_bridge.py"
  echo "MCP server registered globally."
else
  echo "Claude CLI not found. Add this to ~/.claude.json manually:"
  echo ""
  cat <<MCPEOF
  "mcpServers": {
    "mem0": {
      "type": "stdio",
      "command": "python3",
      "args": ["$MEM0_HOME/mcp_bridge.py"],
      "env": {
        "MEM0_BASE_URL": "$MEM0_BASE_URL",
        "MEM0_API_KEY": "$MEM0_API_KEY"
      }
    }
  }
MCPEOF
fi

# Configure hooks
echo ""
echo "Configuring Claude Code hooks..."

SETTINGS_FILE="$HOME/.claude/settings.json"
if [ ! -f "$SETTINGS_FILE" ]; then
  mkdir -p "$HOME/.claude"
  echo '{}' > "$SETTINGS_FILE"
fi

# Merge hooks into settings.json using jq
HOOKS_JSON=$(cat <<HOOKSEOF
{
  "SessionStart": [
    {
      "matcher": "startup|resume|compact",
      "hooks": [
        {
          "type": "command",
          "command": "$MEM0_HOME/hooks/on_session_start.sh",
          "statusMessage": "Loading mem0 context..."
        }
      ]
    }
  ],
  "UserPromptSubmit": [
    {
      "hooks": [
        {
          "type": "command",
          "command": "$MEM0_HOME/hooks/on_user_prompt.sh",
          "timeout": 5
        }
      ]
    }
  ],
  "PreToolUse": [
    {
      "matcher": "Write|Edit",
      "hooks": [
        {
          "type": "command",
          "command": "$MEM0_HOME/hooks/block_memory_write.sh"
        }
      ]
    },
    {
      "matcher": "Bash|Read|Edit|Write|Agent",
      "hooks": [
        {
          "type": "command",
          "command": "$MEM0_HOME/hooks/check_mem0_save_cadence.sh",
          "timeout": 3
        }
      ]
    }
  ],
  "PostToolUse": [
    {
      "matcher": "Agent|WebSearch|WebFetch",
      "hooks": [
        {
          "type": "command",
          "command": "$MEM0_HOME/hooks/on_post_research.sh",
          "timeout": 5
        }
      ]
    },
    {
      "matcher": "mcp__mem0__add_memory|mcp__mem0__update_memory",
      "hooks": [
        {
          "type": "command",
          "command": "$MEM0_HOME/hooks/reset_mem0_counter.sh",
          "timeout": 3
        }
      ]
    }
  ],
  "PreCompact": [
    {
      "hooks": [
        {
          "type": "command",
          "command": "$MEM0_HOME/hooks/on_pre_compact.sh",
          "statusMessage": "Preparing pre-compaction summary..."
        }
      ]
    }
  ],
  "Stop": [
    {
      "hooks": [
        {
          "type": "command",
          "command": "$MEM0_HOME/hooks/on_stop.sh",
          "timeout": 10
        }
      ]
    }
  ],
  "TaskCompleted": [
    {
      "hooks": [
        {
          "type": "command",
          "command": "$MEM0_HOME/hooks/on_task_completed.sh",
          "timeout": 10
        }
      ]
    }
  ]
}
HOOKSEOF
)

# Merge: add mem0 hook entries to each event, preserving existing hooks
MERGED=$(jq --argjson mem0hooks "$HOOKS_JSON" '
  .hooks = (.hooks // {}) |
  .hooks as $existing |
  reduce ($mem0hooks | keys[]) as $event (
    .;
    .hooks[$event] = (($existing[$event] // []) + $mem0hooks[$event])
  )
' "$SETTINGS_FILE")

echo "$MERGED" > "$SETTINGS_FILE"
echo "Hooks configured."

# Export env vars reminder
echo ""
echo "Add these to your shell profile (~/.zshrc, ~/.bashrc, etc.):"
echo ""
echo "  export MEM0_BASE_URL=\"$MEM0_BASE_URL\""
echo "  export MEM0_API_KEY=\"$MEM0_API_KEY\""
echo ""
echo "Installation complete. Restart Claude Code to activate."
