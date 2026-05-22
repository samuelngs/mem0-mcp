#!/usr/bin/env bash
set -euo pipefail

MEM0_HOME="${MEM0_HOME:-$HOME/.mem0}"

echo "mem0 Claude Code Integration — Uninstaller"
echo "============================================"
echo ""

# Remove MCP server
if command -v claude >/dev/null 2>&1; then
  echo "Removing mem0 MCP server..."
  claude mcp remove mem0 --scope user 2>/dev/null || true
  echo "MCP server removed."
fi

# Remove hooks from settings.json
SETTINGS_FILE="$HOME/.claude/settings.json"
if [ -f "$SETTINGS_FILE" ] && command -v jq >/dev/null 2>&1; then
  echo "Removing hooks from settings.json..."
  jq '
    .hooks = (
      .hooks // {} |
      to_entries |
      map(
        .value = [.value[] | select(
          (.hooks // []) | all(.command | test("/.mem0/") | not)
        )] |
        select(.value | length > 0)
      ) |
      from_entries
    )
  ' "$SETTINGS_FILE" > "${SETTINGS_FILE}.tmp" && mv "${SETTINGS_FILE}.tmp" "$SETTINGS_FILE"
  echo "Hooks removed."
fi

# Remove files
echo "Removing $MEM0_HOME..."
rm -rf "$MEM0_HOME"
echo "Files removed."

echo ""
echo "Uninstall complete. Remove MEM0_BASE_URL and MEM0_API_KEY from your shell profile."
