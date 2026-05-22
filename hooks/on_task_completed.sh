#!/usr/bin/env bash
# Hook: TaskCompleted
# Reminds Claude to extract learnings from completed tasks.

set -euo pipefail

HOOKS_DIR="$(cd "$(dirname "$0")" && pwd)"
. "$HOOKS_DIR/_identity.sh" || true

INPUT=$(cat)
TASK_SUBJECT=$(echo "$INPUT" | jq -r '.task_subject // "unknown task"' 2>/dev/null || echo "unknown task")

cat <<EOF
Task completed: "$TASK_SUBJECT"

Extract key learnings from this completed task and store them using the mem0 \`add_memory\` tool:

1. What strategy worked well? -> Store with metadata \`{"type": "task_learning"}\`
2. Were there failed approaches? -> Store with metadata \`{"type": "anti_pattern"}\`
3. Any architectural decisions? -> Store with metadata \`{"type": "decision"}\`
4. New conventions established? -> Store with metadata \`{"type": "convention"}\`

Include \`"project_id": "$MEM0_PROJECT_ID"\` in metadata for all memories.
Only store genuinely useful learnings — skip if trivial.
EOF

exit 0
