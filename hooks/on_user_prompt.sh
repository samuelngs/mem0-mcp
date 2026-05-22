#!/usr/bin/env bash
# Hook: UserPromptSubmit
# Injects structured mem0 memory protocol with retrieval enforcement.
# Debounced: full protocol every 3 min, one-liner reminder between.

set -uo pipefail

INPUT=$(cat)
PROMPT=$(echo "$INPUT" | jq -r '.prompt // ""' 2>/dev/null || echo "")

if [ ${#PROMPT} -lt 20 ]; then
  exit 0
fi

if [ -z "${MEM0_API_KEY:-}" ]; then
  exit 0
fi

HOOKS_DIR="$(cd "$(dirname "$0")" && pwd)"
. "$HOOKS_DIR/_identity.sh"

STATE_FILE="$HOME/.mem0/.last_protocol_inject"
NOW=$(date +%s)
LAST=$(cat "$STATE_FILE" 2>/dev/null || echo 0)
DIFF=$((NOW - LAST))

if [ $DIFF -lt 180 ]; then
  cat <<EOF
mem0: MUST search anti_patterns before proposing fixes. Save at phase transitions (research/problem/solution/plan/progress/pivot/outcome/anti_pattern). user_id="$MEM0_RESOLVED_USER_ID" project_id="$MEM0_PROJECT_ID"
EOF
  exit 0
fi

echo "$NOW" > "$STATE_FILE" 2>/dev/null || true

cat <<EOF
## mem0 Structured Memory Protocol

**RETRIEVE before acting** (run 2-4 parallel search_memories, user_id="$MEM0_RESOLVED_USER_ID"):

| When | Search for |
|------|-----------|
| Before proposing any fix | "failed approaches [topic]" — anti_patterns FIRST |
| Before implementing | "implementation plan [topic]" + "progress [topic]" |
| When debugging | "error [symptom]" + "anti_pattern [area]" |
| Starting new task | "decisions [area]" + "conventions [area]" |

**SAVE at each phase transition** (add_memory, user_id="$MEM0_RESOLVED_USER_ID", metadata.project_id="$MEM0_PROJECT_ID"):

| Phase | metadata.type | What to save |
|-------|--------------|--------------|
| Research done | \`research\` | Key findings, sources, relevant code/docs discovered |
| Problem identified | \`problem\` | Error messages, symptoms, reproduction steps, affected files |
| Solution proposed | \`solution\` | Approach chosen, WHY this over alternatives, trade-offs |
| Plan created | \`plan\` | Ordered steps, dependencies between them, risks |
| After each major step | \`progress\` | What's done, what's next, current blockers |
| Approach changed | \`pivot\` | What changed, WHY, what was wrong with old approach |
| Work completed | \`outcome\` | Files changed, what works now, how it was verified |
| Approach failed | \`anti_pattern\` | What was tried, exact failure mode, WHY it didn't work |

**Enforcement rules:**
1. MUST search for \`anti_pattern\` memories before proposing any solution — learn from past failures
2. MUST save \`anti_pattern\` immediately when an approach fails — don't wait for session end
3. MUST save \`progress\` after completing each major implementation step
4. MUST save \`pivot\` when changing approach mid-task — capture WHY
5. Use \`infer=False\` for structured summaries to preserve formatting verbatim
6. Include reasoning (WHY) in every save — bare facts without reasoning are low-value
7. Skip saves only for trivial acknowledgements or continuations
EOF

exit 0
