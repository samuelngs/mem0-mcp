# mem0 Claude Code Integration

Persistent, structured memory for Claude Code using self-hosted [mem0](https://github.com/mem0ai/mem0).

Replaces Claude Code's built-in file-based memory with a centralized mem0 server that persists across sessions, projects, and machines. Includes an MCP bridge (9 tools, 1:1 with cloud mem0) and lifecycle hooks that enforce structured memory throughout every session.

## What It Does

**MCP Bridge** — A zero-dependency Python stdio server that translates Claude Code MCP tool calls to the mem0 OSS REST API. Drop-in replacement for cloud `mcp.mem0.ai`.

**Lifecycle Hooks** — Shell scripts wired into Claude Code events that enforce a structured memory protocol:

| Hook | Event | Purpose |
|------|-------|---------|
| `on_session_start.sh` | SessionStart | Bootstrap context from mem0, load anti-patterns |
| `on_user_prompt.sh` | UserPromptSubmit | Inject retrieval/save protocol (debounced) |
| `on_post_research.sh` | PostToolUse | Remind to save research after Agent/WebSearch |
| `block_memory_write.sh` | PreToolUse | Block writes to MEMORY.md, redirect to mem0 |
| `on_pre_compact.sh` | PreCompact | Force full context dump before compaction |
| `on_stop.sh` | Stop | Structured outcome save + gap detection |
| `on_task_completed.sh` | TaskCompleted | Extract learnings from completed tasks |

## Memory Types

The hooks enforce 8 structured memory types:

| Type | When to Save | What to Include |
|------|-------------|-----------------|
| `research` | After code exploration or web search | Key findings, sources, relevant code |
| `problem` | When a problem is identified | Error messages, symptoms, repro steps |
| `solution` | When proposing a fix | Approach chosen, WHY, alternatives considered |
| `plan` | When creating implementation steps | Ordered steps, dependencies, risks |
| `progress` | After each major step | What's done, what's next, blockers |
| `pivot` | When changing approach | What changed, WHY previous approach failed |
| `outcome` | When work is completed | Files changed, verification, open items |
| `anti_pattern` | When an approach fails | What was tried, exact failure, WHY it broke |

**Key enforcement:** Claude MUST search for `anti_pattern` memories before proposing any solution.

## Prerequisites

- Self-hosted [mem0](https://github.com/mem0ai/mem0) server (OSS version)
- [Claude Code](https://docs.anthropic.com/en/docs/claude-code) CLI
- Python 3.8+
- jq

## Quick Install

```bash
git clone https://github.com/samuelngs/mem0-claude-code.git
cd mem0-claude-code

export MEM0_BASE_URL=https://mem0.example.com
export MEM0_API_KEY=your-api-key

./install.sh
```

The installer will:
1. Copy files to `~/.mem0/`
2. Register the MCP server globally via `claude mcp add --scope user`
3. Merge hooks into `~/.claude/settings.json`
4. Test connectivity to your mem0 server

## Manual Install

### 1. Copy files

```bash
mkdir -p ~/.mem0/hooks
cp mcp_bridge.py ~/.mem0/
cp hooks/*.sh ~/.mem0/hooks/
chmod +x ~/.mem0/hooks/*.sh
```

### 2. Register MCP server

```bash
claude mcp add mem0 --scope user \
  -e MEM0_BASE_URL=https://mem0.example.com \
  -e MEM0_API_KEY=your-api-key \
  -- python3 ~/.mem0/mcp_bridge.py
```

### 3. Add hooks to settings.json

Merge the contents of [`examples/settings-hooks.json`](examples/settings-hooks.json) into the `hooks` section of `~/.claude/settings.json`. Preserve any existing hooks.

### 4. Export env vars

Add to your shell profile (`~/.zshrc`, `~/.bashrc`):

```bash
export MEM0_BASE_URL=https://mem0.example.com
export MEM0_API_KEY=your-api-key
```

### 5. Restart Claude Code

## Configuration

### Environment Variables

| Variable | Required | Description |
|----------|----------|-------------|
| `MEM0_BASE_URL` | Yes | URL of your mem0 server |
| `MEM0_API_KEY` | Yes | API key for authentication |
| `MEM0_USER_ID` | No | Override auto-detected user ID (defaults to `$USER`) |
| `MEM0_PROJECT_ID` | No | Override auto-detected project ID (defaults to git remote slug) |

### Project Mapping

To override project IDs per directory, create `~/.mem0/project_map.json`:

```json
{
  "/path/to/project-a": "my-project-a",
  "/path/to/project-b": "my-project-b"
}
```

### Auto-Detection

Without overrides, identity and project are resolved automatically:

- **User ID**: `MEM0_USER_ID` env var → `$USER` → `"default"`
- **Project ID**: `MEM0_PROJECT_ID` env var → `project_map.json` → git remote slug (`owner-repo`) → directory basename
- **Branch**: `git branch --show-current` → `"unknown"`

## How It Works

### Session Lifecycle

```
SessionStart
  ├── Bootstrap: fetch memory count, inject protocol
  ├── startup: "Search mem0 for context before starting"
  ├── resume: "Search for progress, anti_patterns, pivots"
  └── compact: "Recover from compaction via mem0 search"
      │
UserPromptSubmit (every prompt, debounced 3 min)
  ├── Full protocol: retrieval table + save table + enforcement rules
  └── Short reminder: "Search anti_patterns. Save at transitions."
      │
PostToolUse (after Agent/WebSearch/WebFetch)
  └── "Save research findings to mem0 NOW"
      │
PreToolUse (Write|Edit to MEMORY.md)
  └── BLOCKED → "Use mem0 add_memory instead"
      │
PreCompact
  └── "CRITICAL: Save full session state to mem0"
      │
Stop
  └── "Save structured outcome + gap check"
      │
TaskCompleted
  └── "Extract learnings from this task"
```

### mem0 OSS API Notes

This bridge targets the mem0 OSS REST API (not the cloud API):

- No `/v1/` prefix — endpoints are `/memories`, `/search`, `/entities`
- Auth via `X-API-Key` header (not `Authorization: Token`)
- Search requires `user_id` inside `filters` dict, not as top-level parameter
- The bridge handles this translation automatically

## Uninstall

```bash
./uninstall.sh
```

Or manually:
```bash
claude mcp remove mem0 --scope user
rm -rf ~/.mem0
# Remove mem0 hooks from ~/.claude/settings.json
# Remove MEM0_* exports from shell profile
```

## License

MIT
