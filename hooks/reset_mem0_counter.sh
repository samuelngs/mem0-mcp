#!/usr/bin/env bash
# Hook: PostToolUse (matcher: mcp__mem0__add_memory|mcp__mem0__update_memory)
# Resets tool call counter after a mem0 save.

set -uo pipefail

echo "0" > "$HOME/.mem0/.tool_call_count" 2>/dev/null || true

exit 0
