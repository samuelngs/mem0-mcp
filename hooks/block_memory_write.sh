#!/usr/bin/env bash
# Hook: PreToolUse (matcher: Write|Edit)
# Blocks writes to MEMORY.md and auto-memory files, redirects to mem0.

set -euo pipefail

INPUT=$(cat)
FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // .tool_input.path // ""' 2>/dev/null || echo "")

if [ -z "$FILE_PATH" ]; then
  exit 0
fi

case "$FILE_PATH" in
  */MEMORY.md|*/.claude/memory/*|*/.claude/*/memory/*)
    echo "BLOCKED: Do not write to $FILE_PATH. Use the mem0 MCP \`add_memory\` tool instead to persist memories. This project uses mem0 for all memory storage." >&2
    exit 2
    ;;
  *)
    exit 0
    ;;
esac
