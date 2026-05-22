#!/usr/bin/env bash
# Resolves MEM0_RESOLVED_USER_ID, MEM0_PROJECT_ID, MEM0_BRANCH.
# Sourced by other hook scripts.

_mem0_resolve_identity() {
  if [ -n "${MEM0_USER_ID:-}" ]; then
    printf '%s' "$MEM0_USER_ID"
    return
  fi
  printf '%s' "${USER:-default}"
}

MEM0_RESOLVED_USER_ID="$(_mem0_resolve_identity)"
export MEM0_RESOLVED_USER_ID

_mem0_resolve_project_id() {
  if [ -n "${MEM0_PROJECT_ID:-}" ]; then
    printf '%s' "$MEM0_PROJECT_ID"
    return
  fi
  _mem0_map="$HOME/.mem0/project_map.json"
  if [ -f "$_mem0_map" ] && command -v jq >/dev/null 2>&1; then
    _mem0_mapped=$(jq -r --arg cwd "$PWD" '.[$cwd] // empty' "$_mem0_map" 2>/dev/null)
    if [ -n "$_mem0_mapped" ]; then
      printf '%s' "$_mem0_mapped"
      return
    fi
  fi
  _mem0_remote_url=$(git remote get-url origin 2>/dev/null)
  if [ -n "$_mem0_remote_url" ]; then
    _mem0_slug="${_mem0_remote_url%.git}"
    _mem0_slug="${_mem0_slug#https://}"
    _mem0_slug="${_mem0_slug#http://}"
    _mem0_slug="${_mem0_slug#ssh://}"
    _mem0_slug="${_mem0_slug#git://}"
    _mem0_slug="${_mem0_slug#git@}"
    _mem0_slug="${_mem0_slug/://}"
    _mem0_owner=$(printf '%s' "$_mem0_slug" | awk -F'/' '{print $(NF-1)}')
    _mem0_repo=$(printf '%s' "$_mem0_slug" | awk -F'/' '{print $NF}')
    _mem0_slug="${_mem0_owner}-${_mem0_repo}"
    _mem0_slug="${_mem0_slug//\//-}"
    _mem0_slug="${_mem0_slug//:/-}"
    if [ -n "$_mem0_slug" ]; then
      printf '%s' "$_mem0_slug"
      return
    fi
  fi
  printf '%s' "$(basename "$PWD")"
}

_mem0_resolve_branch() {
  git branch --show-current 2>/dev/null || printf 'unknown'
}

MEM0_PROJECT_ID="$(_mem0_resolve_project_id)"
MEM0_BRANCH="$(_mem0_resolve_branch)"
export MEM0_PROJECT_ID
export MEM0_BRANCH
