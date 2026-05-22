#!/usr/bin/env bash
# Hook: PreToolUse (matcher: Bash|Read|Edit|Write|Agent)
# Tracks tool calls since last mem0 save. Warns when threshold exceeded.
# Resets counter when mem0 tools are detected via separate PostToolUse hook.

set -uo pipefail

if [ -z "${MEM0_API_KEY:-}" ]; then
  exit 0
fi

STATE_FILE="$HOME/.mem0/.tool_call_count"
WARN_THRESHOLD=15
HARD_THRESHOLD=30

COUNT=$(cat "$STATE_FILE" 2>/dev/null || echo 0)
COUNT=$((COUNT + 1))
echo "$COUNT" > "$STATE_FILE" 2>/dev/null || true

if [ "$COUNT" -ge "$HARD_THRESHOLD" ]; then
  HOOKS_DIR="$(cd "$(dirname "$0")" && pwd)"
  . "$HOOKS_DIR/_identity.sh" 2>/dev/null || true
  cat <<EOF
⚠️ $COUNT tool calls since last mem0 save. You are likely losing context that should be persisted.

STOP and save now. Use add_memory with user_id="$MEM0_RESOLVED_USER_ID", metadata.project_id="$MEM0_PROJECT_ID".

Save whichever applies: progress, outcome, anti_pattern, research, solution, pivot.
EOF
elif [ "$COUNT" -ge "$WARN_THRESHOLD" ]; then
  cat <<EOF
mem0 reminder: $COUNT tool calls without saving. If you've completed a step, made a decision, or hit a failure — save it now before context is lost.
EOF
fi

exit 0
