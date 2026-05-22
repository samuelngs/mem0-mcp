#!/usr/bin/env bash
# Hook: SessionStart (matcher: startup|resume|compact)
# Bootstraps mem0 context + structured memory protocol.

set -uo pipefail

HOOKS_DIR="$(cd "$(dirname "$0")" && pwd)"

if [ -z "${MEM0_API_KEY:-}" ]; then
  exit 0
fi

if [ -z "${MEM0_BASE_URL:-}" ]; then
  exit 0
fi

. "$HOOKS_DIR/_identity.sh"

# Reset debounce state and tool call counter for new session
rm -f "$HOME/.mem0/.last_protocol_inject" 2>/dev/null || true
echo "0" > "$HOME/.mem0/.tool_call_count" 2>/dev/null || true

INPUT=$(cat)
SOURCE=$(echo "$INPUT" | jq -r '.source // "startup"' 2>/dev/null || echo "startup")

MEM0_COUNT="?"
if command -v python3 >/dev/null 2>&1; then
  MEM0_COUNT=$(python3 -c "
import json, os, urllib.request, urllib.error
api_key = os.environ.get('MEM0_API_KEY', '')
base_url = os.environ.get('MEM0_BASE_URL', '').rstrip('/')
user_id = os.environ.get('MEM0_RESOLVED_USER_ID', 'default')
if not base_url:
    print('?')
    raise SystemExit(0)
body = json.dumps({
    'query': 'project context',
    'filters': {'user_id': user_id},
    'limit': 100,
}).encode()
req = urllib.request.Request(
    f'{base_url}/search',
    data=body,
    headers={'X-API-Key': api_key, 'Content-Type': 'application/json'},
    method='POST',
)
try:
    with urllib.request.urlopen(req, timeout=5) as r:
        data = json.loads(r.read())
        results = data.get('results', data) if isinstance(data, dict) else data
        if isinstance(results, list):
            n = len(results)
            print(f'{n}+' if n >= 100 else str(n))
        else:
            print('?')
except Exception:
    print('?')
" 2>/dev/null || echo "?")
fi

echo "## Mem0 Active — Structured Memory Protocol"
echo ""
echo "\`user=$MEM0_RESOLVED_USER_ID | project=$MEM0_PROJECT_ID | branch=$MEM0_BRANCH | memories=$MEM0_COUNT\`"
echo ""
echo "Always include in every mem0 call:"
echo "- user_id: \`$MEM0_RESOLVED_USER_ID\`"
echo "- metadata.project_id: \`$MEM0_PROJECT_ID\`"
echo ""
echo "**Memory types:** research, problem, solution, plan, progress, pivot, outcome, anti_pattern"
echo "**Key rule:** ALWAYS search for \`anti_pattern\` memories before proposing any fix or solution."
echo "**Save rule:** Save at every phase transition, not just session end. Include WHY in every save."
echo ""

if [ "$SOURCE" = "startup" ]; then
  cat <<'EOF'
## Session Bootstrap

You have persistent memory via mem0 MCP tools. Before doing anything else:

1. Call `search_memories` with queries related to the current project to load context:
   - Search for recent progress, plans, decisions
   - Search for anti_patterns (failed approaches to avoid)
   - Search for user preferences and conventions
2. Review returned memories before starting work.
3. If the user's request relates to past work, search specifically for that context.

IMPORTANT: Do NOT skip this step. Always bootstrap context first.
EOF

elif [ "$SOURCE" = "resume" ]; then
  cat <<'EOF'
## Session Resumed

Before continuing:

1. Search mem0 for `progress` and `plan` memories related to current task
2. Search for `anti_pattern` memories to avoid repeating failed approaches
3. Search for any `pivot` memories — the plan may have changed

Resume from where the previous session left off.
EOF

elif [ "$SOURCE" = "compact" ]; then
  cat <<'EOF'
## Post-Compaction Recovery

Context was compacted. Recover by searching mem0:

1. Search "session state pre-compaction" — the full dump you saved before compaction
2. Search "progress [current task]" — where you left off
3. Search "anti_pattern" — what not to retry
4. Search "plan" — the implementation plan
5. Search "pivot" — any plan changes

Rebuild your context from these memories before continuing work.
EOF
fi

exit 0
