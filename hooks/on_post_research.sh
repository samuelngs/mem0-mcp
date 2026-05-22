#!/usr/bin/env bash
# Hook: PostToolUse (matcher: Agent|WebSearch|WebFetch)
# After research-type tools, remind to save findings to mem0.

set -uo pipefail

if [ -z "${MEM0_API_KEY:-}" ]; then
  exit 0
fi

HOOKS_DIR="$(cd "$(dirname "$0")" && pwd)"
. "$HOOKS_DIR/_identity.sh" 2>/dev/null || true

INPUT=$(cat)
TOOL_NAME=$(echo "$INPUT" | jq -r '.tool_name // ""' 2>/dev/null || echo "")

cat <<EOF
Research via \`$TOOL_NAME\` complete. If findings are non-trivial, save to mem0 NOW:

\`\`\`
add_memory(
  messages="<key findings, what was discovered, relevant details>",
  user_id="$MEM0_RESOLVED_USER_ID",
  metadata={"type": "research", "project_id": "$MEM0_PROJECT_ID", "source": "$TOOL_NAME"},
  infer=False
)
\`\`\`

Don't defer — research context degrades fast after compaction.
EOF

exit 0
