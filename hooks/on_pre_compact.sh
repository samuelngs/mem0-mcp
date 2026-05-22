#!/usr/bin/env bash
# Hook: PreCompact
# Last chance to capture full context before compaction.
# Forces save of ALL memory types that apply.

set -euo pipefail

HOOKS_DIR="$(cd "$(dirname "$0")" && pwd)"
. "$HOOKS_DIR/_identity.sh" || true

cat <<EOF
## CRITICAL: Pre-Compaction — Full Memory Dump Required

Context compaction is imminent. You are about to lose conversation history. You MUST save everything relevant NOW.

### Step 1: Store comprehensive session state

Call \`add_memory\` with \`infer=False\`, user_id="$MEM0_RESOLVED_USER_ID":

\`\`\`
add_memory(
  messages=[{"role":"user","content":"<full session state below>"}],
  user_id="$MEM0_RESOLVED_USER_ID",
  metadata={"type": "session_state", "source": "pre-compaction", "project_id": "$MEM0_PROJECT_ID", "branch": "$MEM0_BRANCH"},
  infer=False
)
\`\`\`

**Session state MUST include ALL of:**

\`\`\`
## Session State (Pre-Compaction)

### Original Goal
[What the user asked for]

### Research Findings
[What was discovered during investigation — code, docs, external sources]

### Problem Statement
[Current problem being solved, error messages, symptoms]

### Solution & Reasoning
[Approach chosen and WHY — alternatives considered and why rejected]

### Implementation Plan
[Ordered steps, which are done, which remain]

### Current Progress
[Exactly where work stands RIGHT NOW — last completed step, next step]

### What Was Tried and Failed
[Each failed approach with WHY it failed — critical for post-compaction]

### Files Created or Modified
[Every file path with what changed]

### Key Decisions
[Architectural choices, trade-offs, constraints]

### Plan Changes
[Any pivots from original plan — what changed and WHY]

### Important Context
[User preferences, coding patterns, environment quirks, anything that prevents redundant questions]
\`\`\`

### Step 2: Save unstored learnings as separate memories

Each with \`infer=False\`, user_id="$MEM0_RESOLVED_USER_ID", metadata.project_id="$MEM0_PROJECT_ID":

- Failed approaches not yet saved → \`type=anti_pattern\` (MOST IMPORTANT — these prevent re-trying dead ends)
- Successful strategies → \`type=task_learning\`
- Architecture decisions → \`type=decision\`
- New conventions → \`type=convention\`

### Step 3: Acknowledge

Tell the user session state has been saved to mem0 and you're ready for compaction.

Do this NOW. Do not skip any section. Quality of this save determines whether you can continue effectively after compaction.
EOF

exit 0
