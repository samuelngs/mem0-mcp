#!/usr/bin/env bash
set -euo pipefail

MEM0_HOME="${MEM0_HOME:-$HOME/.mem0}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
TARGET="${MEM0_TARGET:-auto}"

usage() {
  cat <<EOF
Usage: $0 [--target auto|claude|codex|both]

Environment:
  MEM0_BASE_URL   mem0 server URL
  MEM0_API_KEY    mem0 API key
  MEM0_HOME       install directory (default: ~/.mem0)
  MEM0_TARGET     auto, claude, codex, or both
EOF
}

die() {
  echo "Error: $*" >&2
  exit 1
}

has_cmd() {
  command -v "$1" >/dev/null 2>&1
}

require_cmd() {
  has_cmd "$1" || die "$1 is required but not found."
}

validate_mem0_home() {
  [ -n "$MEM0_HOME" ] || die "MEM0_HOME cannot be empty."
  [ "$MEM0_HOME" != "/" ] || die "MEM0_HOME cannot be /."
}

parse_args() {
  while [ $# -gt 0 ]; do
    case "$1" in
      --target)
        [ $# -ge 2 ] || die "--target requires a value."
        TARGET="$2"
        shift 2
        ;;
      --target=*)
        TARGET="${1#*=}"
        shift
        ;;
      -h|--help)
        usage
        exit 0
        ;;
      *)
        usage
        die "unknown argument: $1"
        ;;
    esac
  done

  case "$TARGET" in
    auto|claude|codex|both) ;;
    *) die "--target must be auto, claude, codex, or both." ;;
  esac
}

select_targets() {
  CLAUDE_CLI=false
  CODEX_CLI=false
  INSTALL_CLAUDE=false
  INSTALL_CODEX=false

  has_cmd claude && CLAUDE_CLI=true
  has_cmd codex && CODEX_CLI=true

  case "$TARGET" in
    claude)
      INSTALL_CLAUDE=true
      ;;
    codex)
      INSTALL_CODEX=true
      ;;
    both)
      INSTALL_CLAUDE=true
      INSTALL_CODEX=true
      ;;
    auto)
      [ "$CLAUDE_CLI" = "true" ] && INSTALL_CLAUDE=true
      [ "$CODEX_CLI" = "true" ] && INSTALL_CODEX=true
      ;;
  esac

  if [ "$INSTALL_CLAUDE" = "false" ] && [ "$INSTALL_CODEX" = "false" ]; then
    echo "Warning: neither claude nor codex CLI was found. Files will be installed only."
  fi
}

prompt_config() {
  if [ -z "${MEM0_BASE_URL:-}" ]; then
    read -rp "mem0 server URL (e.g., https://mem0.example.com): " MEM0_BASE_URL
  fi

  if [ -z "${MEM0_API_KEY:-}" ]; then
    read -rp "mem0 API key: " MEM0_API_KEY
  fi

  [ -n "$MEM0_BASE_URL" ] || die "MEM0_BASE_URL is required."
  [ -n "$MEM0_API_KEY" ] || die "MEM0_API_KEY is required."
}

test_connection() {
  echo ""
  echo "Testing connection to $MEM0_BASE_URL..."

  local http_code
  http_code=$(MEM0_BASE_URL="$MEM0_BASE_URL" MEM0_API_KEY="$MEM0_API_KEY" python3 - <<'PY' 2>/dev/null
import os
import urllib.error
import urllib.request

base_url = os.environ["MEM0_BASE_URL"].rstrip("/")
api_key = os.environ["MEM0_API_KEY"]
req = urllib.request.Request(
    f"{base_url}/entities",
    headers={"X-API-Key": api_key, "Content-Type": "application/json"},
)
try:
    with urllib.request.urlopen(req, timeout=10) as resp:
        print(resp.status)
except urllib.error.HTTPError as exc:
    print(exc.code)
except Exception:
    print("0")
PY
)

  case "$http_code" in
    0) die "Cannot reach $MEM0_BASE_URL. Check URL and network." ;;
    401|403) die "Authentication failed. Check your API key." ;;
    *) echo "Connected (HTTP $http_code)." ;;
  esac
}

install_files() {
  echo ""
  echo "Installing to $MEM0_HOME..."
  mkdir -p "$MEM0_HOME/hooks"
  cp "$SCRIPT_DIR/mcp_bridge.py" "$MEM0_HOME/mcp_bridge.py"
  cp "$SCRIPT_DIR/hooks/"*.sh "$MEM0_HOME/hooks/"
  chmod +x "$MEM0_HOME/hooks/"*.sh
  echo "Files installed."
}

hooks_events_json() {
  local template_file="$1"

  jq --arg mem0_home "$MEM0_HOME" '
    def walk(f):
      . as $in
      | if type == "object" then
          reduce keys[] as $key ({}; . + {($key): ($in[$key] | walk(f))}) | f
        elif type == "array" then map(walk(f)) | f
        else f
        end;

    (if has("hooks") then .hooks else . end)
    | walk(if type == "string" then gsub("\\$HOME/\\.mem0"; $mem0_home) else . end)
  ' "$template_file"
}

merge_hooks() {
  local settings_file="$1"
  local hooks_json="$2"

  if [ ! -f "$settings_file" ]; then
    mkdir -p "$(dirname "$settings_file")"
    echo '{}' > "$settings_file"
  fi

  local tmp_file
  tmp_file="${settings_file}.tmp"

  jq --arg mem0_home "$MEM0_HOME" --argjson mem0hooks "$hooks_json" '
    def is_mem0_command:
      ((.command // "") | contains($mem0_home))
      or ((.command // "") | test("/\\.mem0/"));

    .hooks = (.hooks // {}) |
    .hooks = (
      .hooks
      | to_entries
      | map(
          .value = [
            .value[]
            | .hooks = [(.hooks // [])[] | select(is_mem0_command | not)]
            | select((.hooks // []) | length > 0)
          ]
          | select(.value | length > 0)
        )
      | from_entries
    ) |
    .hooks as $existing |
    reduce ($mem0hooks | keys[]) as $event (
      .;
      .hooks[$event] = (($existing[$event] // []) + $mem0hooks[$event])
    )
  ' "$settings_file" > "$tmp_file"
  mv "$tmp_file" "$settings_file"
}

register_claude_mcp() {
  [ "$INSTALL_CLAUDE" = "true" ] || return 0

  echo ""
  if [ "$CLAUDE_CLI" = "true" ]; then
    echo "Registering Claude MCP server..."
    claude mcp add mem0 --scope user \
      -e MEM0_BASE_URL="$MEM0_BASE_URL" \
      -e MEM0_API_KEY="$MEM0_API_KEY" \
      -- python3 "$MEM0_HOME/mcp_bridge.py"
    echo "Claude MCP server registered globally."
    return 0
  fi

  echo "Claude CLI not found. Add this to ~/.claude.json manually:"
  cat <<EOF
  "mcpServers": {
    "mem0": {
      "type": "stdio",
      "command": "python3",
      "args": ["$MEM0_HOME/mcp_bridge.py"],
      "env": {
        "MEM0_BASE_URL": "$MEM0_BASE_URL",
        "MEM0_API_KEY": "$MEM0_API_KEY"
      }
    }
  }
EOF
}

register_codex_mcp() {
  [ "$INSTALL_CODEX" = "true" ] || return 0

  echo ""
  if [ "$CODEX_CLI" = "true" ]; then
    echo "Registering Codex MCP server..."
    codex mcp add mem0 \
      --env MEM0_BASE_URL="$MEM0_BASE_URL" \
      --env MEM0_API_KEY="$MEM0_API_KEY" \
      -- python3 "$MEM0_HOME/mcp_bridge.py"
    echo "Codex MCP server registered."
    return 0
  fi

  echo "Codex CLI not found. Add this to ~/.codex/config.toml manually:"
  cat <<EOF
[mcp_servers.mem0]
command = "python3"
args = ["$MEM0_HOME/mcp_bridge.py"]

[mcp_servers.mem0.env]
MEM0_BASE_URL = "$MEM0_BASE_URL"
MEM0_API_KEY = "$MEM0_API_KEY"
EOF
}

configure_claude_hooks() {
  [ "$INSTALL_CLAUDE" = "true" ] || return 0

  echo ""
  echo "Configuring Claude Code hooks..."
  merge_hooks "$HOME/.claude/settings.json" "$(hooks_events_json "$SCRIPT_DIR/examples/claude/hooks.json")"
  echo "Claude hooks configured."
}

configure_codex_hooks() {
  [ "$INSTALL_CODEX" = "true" ] || return 0

  echo ""
  echo "Configuring Codex hooks..."
  merge_hooks "$HOME/.codex/hooks.json" "$(hooks_events_json "$SCRIPT_DIR/examples/codex/hooks.json")"
  echo "Codex hooks configured."
}

print_next_steps() {
  echo ""
  echo "Add these to your shell profile (~/.zshrc, ~/.bashrc, etc.):"
  echo ""
  echo "  export MEM0_BASE_URL=\"$MEM0_BASE_URL\""
  echo "  export MEM0_API_KEY=\"$MEM0_API_KEY\""
  echo ""

  if [ "$INSTALL_CLAUDE" = "true" ] && [ "$INSTALL_CODEX" = "true" ]; then
    echo "Installation complete. Restart Claude Code and Codex to activate."
  elif [ "$INSTALL_CLAUDE" = "true" ]; then
    echo "Installation complete. Restart Claude Code to activate."
  elif [ "$INSTALL_CODEX" = "true" ]; then
    echo "Installation complete. Restart Codex to activate."
  else
    echo "Installation complete. Configure your agent MCP client manually to activate."
  fi
}

main() {
  parse_args "$@"

  echo "mem0 Agent Integration - Installer"
  echo "==================================="
  echo ""

  require_cmd python3
  require_cmd jq
  validate_mem0_home
  select_targets
  prompt_config
  test_connection
  install_files
  register_claude_mcp
  register_codex_mcp
  configure_claude_hooks
  configure_codex_hooks
  print_next_steps
}

main "$@"
