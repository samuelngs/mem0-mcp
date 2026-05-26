#!/usr/bin/env bash
set -euo pipefail

MEM0_HOME="${MEM0_HOME:-$HOME/.mem0}"
TARGET="${MEM0_TARGET:-auto}"

usage() {
  cat <<EOF
Usage: $0 [--target auto|claude|codex|both] [--keep-files]

Environment:
  MEM0_HOME       install directory (default: ~/.mem0)
  MEM0_TARGET     auto, claude, codex, or both

By default, files are removed when no remaining Claude/Codex hook config
references MEM0_HOME. Use --keep-files to leave MEM0_HOME in place.
EOF
}

die() {
  echo "Error: $*" >&2
  exit 1
}

has_cmd() {
  command -v "$1" >/dev/null 2>&1
}

validate_mem0_home() {
  [ -n "$MEM0_HOME" ] || die "MEM0_HOME cannot be empty."
  [ "$MEM0_HOME" != "/" ] || die "MEM0_HOME cannot be /."
}

KEEP_FILES=false

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
      --keep-files)
        KEEP_FILES=true
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
  REMOVE_CLAUDE=false
  REMOVE_CODEX=false

  case "$TARGET" in
    claude)
      REMOVE_CLAUDE=true
      ;;
    codex)
      REMOVE_CODEX=true
      ;;
    both)
      REMOVE_CLAUDE=true
      REMOVE_CODEX=true
      ;;
    auto)
      if has_cmd claude || [ -f "$HOME/.claude/settings.json" ]; then
        REMOVE_CLAUDE=true
      fi
      if has_cmd codex || [ -f "$HOME/.codex/hooks.json" ]; then
        REMOVE_CODEX=true
      fi
      ;;
  esac
}

remove_claude_mcp() {
  [ "$REMOVE_CLAUDE" = "true" ] || return 0

  if has_cmd claude; then
    echo "Removing Claude MCP server..."
    claude mcp remove mem0 --scope user 2>/dev/null || true
    echo "Claude MCP server removed."
  else
    echo "Claude CLI not found; skipping Claude MCP removal."
  fi
}

remove_codex_mcp() {
  [ "$REMOVE_CODEX" = "true" ] || return 0

  if has_cmd codex; then
    echo "Removing Codex MCP server..."
    codex mcp remove mem0 2>/dev/null || true
    echo "Codex MCP server removed."
  else
    echo "Codex CLI not found; skipping Codex MCP removal."
  fi
}

remove_hooks_from_file() {
  local settings_file="$1"
  local label="$2"

  [ -f "$settings_file" ] || return 0

  if ! has_cmd jq; then
    echo "jq not found; skipping $label hook cleanup in $settings_file."
    return 0
  fi

  echo "Removing $label hooks from $settings_file..."
  local tmp_file
  tmp_file="${settings_file}.tmp"

  jq --arg mem0_home "$MEM0_HOME" '
    def is_mem0_command:
      ((.command // "") | contains($mem0_home))
      or ((.command // "") | test("/\\.mem0/"));

    .hooks = (
      .hooks // {}
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
    )
  ' "$settings_file" > "$tmp_file"
  mv "$tmp_file" "$settings_file"
  echo "$label hooks removed."
}

remove_hooks() {
  if [ "$REMOVE_CLAUDE" = "true" ]; then
    remove_hooks_from_file "$HOME/.claude/settings.json" "Claude"
  fi

  if [ "$REMOVE_CODEX" = "true" ]; then
    remove_hooks_from_file "$HOME/.codex/hooks.json" "Codex"
  fi
}

config_still_references_mem0() {
  local file
  for file in "$HOME/.claude/settings.json" "$HOME/.codex/hooks.json"; do
    [ -f "$file" ] || continue
    if grep -F "$MEM0_HOME" "$file" >/dev/null 2>&1 || grep -F "/.mem0/" "$file" >/dev/null 2>&1; then
      return 0
    fi
  done
  return 1
}

remove_files() {
  if [ "$KEEP_FILES" = "true" ]; then
    echo "Keeping $MEM0_HOME because --keep-files was set."
    return 0
  fi

  if config_still_references_mem0; then
    echo "Keeping $MEM0_HOME because another hook config still references it."
    return 0
  fi

  echo "Removing $MEM0_HOME..."
  rm -rf "$MEM0_HOME"
  echo "Files removed."
}

main() {
  parse_args "$@"
  validate_mem0_home
  select_targets

  echo "mem0 Agent Integration - Uninstaller"
  echo "====================================="
  echo ""

  if [ "$REMOVE_CLAUDE" = "false" ] && [ "$REMOVE_CODEX" = "false" ]; then
    echo "No Claude or Codex config found. Removing files only."
  fi

  remove_claude_mcp
  remove_codex_mcp
  remove_hooks
  remove_files

  echo ""
  echo "Uninstall complete. Remove MEM0_BASE_URL and MEM0_API_KEY from your shell profile if they are no longer used."
}

main "$@"
