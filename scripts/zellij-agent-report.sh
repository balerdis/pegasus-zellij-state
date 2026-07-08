#!/usr/bin/env bash
set -u

pane_id=${1:-}
state=${2:-}
message=${3:-}

case "$state" in
  working|blocked|idle) ;;
  *) exit 0 ;;
esac

if [ -z "$pane_id" ]; then
  exit 0
fi

if [ -z "${ZELLIJ_PANE_ID:-}" ] && [ -z "${ZELLIJ:-}" ]; then
  exit 0
fi

if ! command -v zellij >/dev/null 2>&1; then
  exit 0
fi

runtime_root="${XDG_RUNTIME_DIR:-/tmp}/pegasus-zellij-state"
session_name=${ZELLIJ_SESSION_NAME:-default}
safe_session=$(printf '%s' "$session_name" | tr -c 'A-Za-z0-9_.-' '_')
tab_key="current"
tab_panes=""

if command -v jq >/dev/null 2>&1; then
  current_tab_json=$(zellij action current-tab-info --json 2>/dev/null || true)
  if [ -n "$current_tab_json" ]; then
    parsed_tab_key=$(printf '%s' "$current_tab_json" | jq -r '(.tab_index // .position // .id // .name // "current") | tostring' 2>/dev/null || true)
    if [ -n "$parsed_tab_key" ] && [ "$parsed_tab_key" != "null" ]; then
      tab_key=$parsed_tab_key
    fi
    tab_panes=$(printf '%s' "$current_tab_json" | jq -r '.. | objects | (.pane_id? // .id? // empty) | tostring' 2>/dev/null | sort -u || true)
  fi
fi

safe_tab=$(printf '%s' "$tab_key" | tr -c 'A-Za-z0-9_.-' '_')
cache_dir="$runtime_root/$safe_session/$safe_tab"
mkdir -p "$cache_dir"

cache_file="$cache_dir/$pane_id.json"
if command -v jq >/dev/null 2>&1; then
  jq -n \
    --arg pane_id "$pane_id" \
    --arg state "$state" \
    --arg message "$message" \
    --arg timestamp "$(date +%s)" \
    '{pane_id: $pane_id, state: $state, message: $message, updated_at: ($timestamp | tonumber)}' \
    > "$cache_file" 2>/dev/null || true
fi

case "$state" in
  working) pane_title="◉ OpenCode working" ;;
  blocked) pane_title="◆ OpenCode blocked" ;;
  idle) pane_title="○ OpenCode idle" ;;
esac

zellij action rename-pane "$pane_title" >/dev/null 2>&1 || true

if [ "${PEGASUS_ZELLIJ_RENAME_TAB:-1}" = "0" ]; then
  exit 0
fi

if ! command -v jq >/dev/null 2>&1; then
  exit 0
fi

blocked_count=0
working_count=0
idle_count=0

if [ -n "$tab_panes" ]; then
  while IFS= read -r active_pane_id; do
    [ -n "$active_pane_id" ] || continue
    state_file="$cache_dir/$active_pane_id.json"
    [ -f "$state_file" ] || continue
    cached_state=$(jq -r '.state // empty' "$state_file" 2>/dev/null || true)
    case "$cached_state" in
      blocked) blocked_count=$((blocked_count + 1)) ;;
      working) working_count=$((working_count + 1)) ;;
      idle) idle_count=$((idle_count + 1)) ;;
    esac
  done <<EOF
$tab_panes
EOF
else
  for state_file in "$cache_dir"/*.json; do
    [ -f "$state_file" ] || continue
    cached_state=$(jq -r '.state // empty' "$state_file" 2>/dev/null || true)
    case "$cached_state" in
      blocked) blocked_count=$((blocked_count + 1)) ;;
      working) working_count=$((working_count + 1)) ;;
      idle) idle_count=$((idle_count + 1)) ;;
    esac
  done
fi

if [ "$blocked_count" -gt 0 ]; then
  tab_title="◆ OpenCode blocked ($blocked_count)"
elif [ "$working_count" -gt 0 ]; then
  tab_title="◉ OpenCode working ($working_count)"
elif [ "$idle_count" -gt 0 ]; then
  tab_title="○ OpenCode idle"
else
  tab_title="○ OpenCode idle"
fi

zellij action rename-tab "$tab_title" >/dev/null 2>&1 || true
