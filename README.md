# mem0 Agent Integration

Persistent, structured memory for Claude Code and Codex using self-hosted [mem0](https://github.com/mem0ai/mem0).

This project provides a shared MCP bridge for the mem0 OSS REST API plus agent-specific hook examples. Claude Code gets the full lifecycle hook protocol. Codex support uses the same MCP bridge and a conservative hook set for the currently verified Codex events.

## What It Does

**MCP Bridge** — A zero-dependency Python stdio server that translates MCP tool calls to the mem0 OSS REST API. It is intended as a self-hosted replacement for the cloud `mcp.mem0.ai` endpoint.

**Lifecycle Hooks** — Shell scripts that inject or remind the agent about a structured memory protocol:

| Hook | Claude Code | Codex | Purpose |
|------|-------------|-------|---------|
| `on_session_start.sh` | SessionStart | SessionStart | Bootstrap context from mem0, load anti-patterns |
| `on_user_prompt.sh` | UserPromptSubmit | UserPromptSubmit | Inject retrieval/save protocol, debounced |
| `on_stop.sh` | Stop | Stop | Structured outcome save + gap detection |
| `on_post_research.sh` | PostToolUse | Not installed by default | Remind to save research after Agent/WebSearch |
| `block_memory_write.sh` | PreToolUse | Not installed by default | Block writes to MEMORY.md, redirect to mem0 |
| `on_pre_compact.sh` | PreCompact | Not installed by default | Force full context dump before compaction |
| `on_task_completed.sh` | TaskCompleted | Not installed by default | Extract learnings from completed tasks |

Codex may support additional hook events in future versions; the installer only configures the events verified in current local Codex builds.

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

**Key enforcement:** the agent must search for `anti_pattern` memories before proposing a fix or solution.

## Prerequisites

- Self-hosted [mem0](https://github.com/mem0ai/mem0) server, OSS version
- Python 3.8+
- jq
- At least one supported agent CLI:
  - [Claude Code](https://docs.anthropic.com/en/docs/claude-code)
  - Codex CLI

## Quick Install

```bash
git clone https://github.com/samuelngs/mem0-integration.git
cd mem0-integration

export MEM0_BASE_URL=https://mem0.example.com
export MEM0_API_KEY=your-api-key

./install.sh
```

By default, `./install.sh` uses `--target auto` and installs for whichever supported CLIs are available.

Target one or both agents explicitly:

```bash
./install.sh --target claude
./install.sh --target codex
./install.sh --target both
```

The installer will:

1. Copy files to `~/.mem0/`
2. Register the mem0 MCP server with Claude Code and/or Codex
3. Merge agent-specific hooks into the right settings file
4. Test connectivity to your mem0 server

## Manual Install

### 1. Copy files

```bash
mkdir -p ~/.mem0/hooks
cp mcp_bridge.py ~/.mem0/
cp hooks/*.sh ~/.mem0/hooks/
chmod +x ~/.mem0/hooks/*.sh
```

### 2. Register MCP

For Claude Code:

```bash
claude mcp add mem0 --scope user \
  -e MEM0_BASE_URL=https://mem0.example.com \
  -e MEM0_API_KEY=your-api-key \
  -- python3 ~/.mem0/mcp_bridge.py
```

For Codex:

```bash
codex mcp add mem0 \
  --env MEM0_BASE_URL=https://mem0.example.com \
  --env MEM0_API_KEY=your-api-key \
  -- python3 ~/.mem0/mcp_bridge.py
```

### 3. Add hooks

For Claude Code, merge the contents of [`examples/claude/hooks.json`](examples/claude/hooks.json) into the `hooks` section of `~/.claude/settings.json`. Preserve any existing hooks.

For Codex, merge the contents of [`examples/codex/hooks.json`](examples/codex/hooks.json) into `~/.codex/hooks.json`. Preserve any existing hooks.

Example MCP config for Claude Code is available at [`examples/claude/mcp.json`](examples/claude/mcp.json).

### 4. Export env vars

Add to your shell profile (`~/.zshrc`, `~/.bashrc`):

```bash
export MEM0_BASE_URL=https://mem0.example.com
export MEM0_API_KEY=your-api-key
```

### 5. Restart your agent

Restart Claude Code and/or Codex so the MCP server and hooks are loaded.

## Configuration

### Environment Variables

| Variable | Required | Description |
|----------|----------|-------------|
| `MEM0_BASE_URL` | Yes | URL of your mem0 server |
| `MEM0_API_KEY` | Yes | API key for authentication |
| `MEM0_USER_ID` | No | Override auto-detected user ID, defaults to `$USER` |
| `MEM0_PROJECT_ID` | No | Override auto-detected project ID, defaults to git remote slug |
| `MEM0_TARGET` | No | Installer target: `auto`, `claude`, `codex`, or `both` |

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

- **User ID**: `MEM0_USER_ID` env var -> `$USER` -> `"default"`
- **Project ID**: `MEM0_PROJECT_ID` env var -> `project_map.json` -> git remote slug (`owner-repo`) -> directory basename
- **Branch**: `git branch --show-current` -> `"unknown"`

## How It Works

### Claude Code Lifecycle

```text
SessionStart
  Bootstrap context, inject protocol, reset counters

UserPromptSubmit
  Inject full or short retrieval/save protocol

PostToolUse
  Remind to save research findings

PreToolUse
  Block MEMORY.md writes and track save cadence

PreCompact
  Force full session state save

Stop
  Request structured outcome save

TaskCompleted
  Request completed-task learnings
```

### Codex Lifecycle

```text
SessionStart
  Bootstrap context and inject the protocol

UserPromptSubmit
  Inject full or short retrieval/save protocol

Stop
  Request structured outcome save
```

Codex still gets the full `mem0` MCP tool set. The difference is hook coverage, not memory capability.

### mem0 OSS API Notes

This bridge targets the mem0 OSS REST API, not the cloud API:

- No `/v1/` prefix; endpoints are `/memories`, `/search`, `/entities`
- Auth via `X-API-Key` header
- Search requires `user_id` inside `filters`, not as a top-level parameter
- The bridge handles this translation automatically

## Examples Layout

```text
examples/
  claude/
    hooks.json
    mcp.json
  codex/
    hooks.json
```

## Uninstall

By default, `./uninstall.sh` uses `--target auto` and removes whichever Claude/Codex config it finds:

```bash
./uninstall.sh
```

Target one or both agents explicitly:

```bash
./uninstall.sh --target claude
./uninstall.sh --target codex
./uninstall.sh --target both
```

The uninstaller removes MCP registration and hooks for the selected agents. It removes `~/.mem0` only when no remaining Claude/Codex hook config references it. Use `--keep-files` to always leave `~/.mem0` in place.

## License

MIT
