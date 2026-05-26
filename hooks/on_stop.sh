#!/usr/bin/env bash
# Hook: Stop
# Forces structured outcome save + gap detection before session ends.

set -euo pipefail

HOOKS_DIR="$(cd "$(dirname "$0")" && pwd)"
. "$HOOKS_DIR/_identity.sh" || true

INPUT=$(cat)
STOP_HOOK_ACTIVE=$(echo "$INPUT" | jq -r '.stop_hook_active // false' 2>/dev/null || echo "false")

if [ "$STOP_HOOK_ACTIVE" = "true" ]; then
  exit 0
fi

REASON=$(cat <<EOF
## Session End — Structured Memory Save Required

Before finishing, you MUST store a structured outcome using add_memory with \`infer=False\`:

\`\`\`
add_memory(
  messages=[{"role":"user","content":"<structured summary below>"}],
  user_id="$MEM0_RESOLVED_USER_ID",
  metadata={"type": "outcome", "project_id": "$MEM0_PROJECT_ID", "branch": "$MEM0_BRANCH"},
  infer=False
)
\`\`\`

### Required structure:

\`\`\`
## Session Outcome

### Problem
[What was the user trying to solve]

### Solution Implemented
[What approach was taken and WHY]

### What Changed
[Files created/modified with brief description of each change]

### What Was Tried and Didn't Work
[Failed approaches — if not already saved as anti_patterns, save them separately NOW]

### Verification
[How the solution was verified — tests, manual checks, etc.]

### Open Items
[Anything unfinished, known issues, next steps]
\`\`\`

### Gap check — also save these if not already stored this session:
1. Any failed approaches? → save each as \`type=anti_pattern\`
2. Key decisions made? → save as \`type=decision\`
3. Significant plan changes? → save as \`type=pivot\`
4. User preferences learned? → save as \`type=user_preference\`

If nothing notable happened this session, skip. Only store genuinely useful context.
Always include \`project_id: "$MEM0_PROJECT_ID"\` in metadata.
EOF
)

jq -n --arg reason "$REASON" '{
  "continue": true,
  "decision": "block",
  "reason": $reason
}'

exit 0
