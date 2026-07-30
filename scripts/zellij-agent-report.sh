#!/usr/bin/env bash
set -u

pane_id=${1:-}
state=${2:-}
message=${3:-}

case "$state" in
  working|blocked|idle|orchestrator-idle) ;;
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

first_existing_file() {
  for candidate in "$@"; do
    [ -n "$candidate" ] || continue
    if [ -f "$candidate" ]; then
      printf '%s' "$candidate"
      return 0
    fi
  done

  return 1
}

sound_file_for_state() {
  case "$1" in
    blocked)
      if [ -n "${PEGASUS_ZELLIJ_SOUND_BLOCKED:-}" ]; then
        first_existing_file "$PEGASUS_ZELLIJ_SOUND_BLOCKED" || true
        return 0
      fi

      first_existing_file \
        /usr/share/sounds/freedesktop/stereo/dialog-warning.oga \
        /usr/share/sounds/freedesktop/stereo/alarm-clock-elapsed.oga \
        /System/Library/Sounds/Funk.aiff || true
      ;;
    idle)
      if [ -n "${PEGASUS_ZELLIJ_SOUND_IDLE:-}" ]; then
        first_existing_file "$PEGASUS_ZELLIJ_SOUND_IDLE" || true
        return 0
      fi

      first_existing_file \
        /usr/share/sounds/freedesktop/stereo/complete.oga \
        /usr/share/sounds/freedesktop/stereo/message.oga \
        /System/Library/Sounds/Glass.aiff || true
      ;;
    orchestrator-idle)
      if [ -n "${PEGASUS_ZELLIJ_SOUND_ORCHESTRATOR_IDLE:-}" ]; then
        first_existing_file "$PEGASUS_ZELLIJ_SOUND_ORCHESTRATOR_IDLE" || true
        return 0
      fi

      first_existing_file \
        /usr/share/sounds/freedesktop/stereo/bell.oga \
        /usr/share/sounds/freedesktop/stereo/complete.oga \
        /System/Library/Sounds/Hero.aiff \
        /System/Library/Sounds/Glass.aiff || true
      ;;
  esac
}

play_sound() {
  [ "${PEGASUS_ZELLIJ_SOUND:-1}" != "0" ] || return 0
  if [ "$1" = "orchestrator-idle" ] && [ "${PEGASUS_ZELLIJ_SOUND_ORCHESTRATOR_IDLE_ENABLED:-1}" = "0" ]; then
    return 0
  fi

  sound_file=$(sound_file_for_state "$1")
  [ -n "$sound_file" ] || return 0

  if command -v paplay >/dev/null 2>&1; then
    paplay "$sound_file" >/dev/null 2>&1 &
  elif command -v canberra-gtk-play >/dev/null 2>&1; then
    canberra-gtk-play --file "$sound_file" >/dev/null 2>&1 &
  elif command -v aplay >/dev/null 2>&1; then
    aplay "$sound_file" >/dev/null 2>&1 &
  elif command -v afplay >/dev/null 2>&1; then
    afplay "$sound_file" >/dev/null 2>&1 &
  fi
}

normalize_pane_id() {
  case "$1" in
    terminal_*) printf '%s' "${1#terminal_}" ;;
    *) printf '%s' "$1" ;;
  esac
}

incoming_pane_id=$(normalize_pane_id "$pane_id")
current_process_pane_id=$(normalize_pane_id "${ZELLIJ_PANE_ID:-}")
target_pane_id=""
target_tab_id=""
tab_panes=""
cache_state="$state"

if [ "$state" = "orchestrator-idle" ]; then
  cache_state="idle"
fi

if ! command -v jq >/dev/null 2>&1; then
  exit 0
fi

panes_json=$(zellij action list-panes --json 2>/dev/null || true)

if [ -z "$panes_json" ]; then
  exit 0
fi

target_pane_json=$(printf '%s' "$panes_json" | jq -c --arg pane_id "$incoming_pane_id" '
  map(select(((.is_plugin // false) | not) and ((.id | tostring) == $pane_id))) | first // empty
' 2>/dev/null || true)

if [ -z "$target_pane_json" ]; then
  exit 0
fi

target_pane_id=$(printf '%s' "$target_pane_json" | jq -r '.id | tostring' 2>/dev/null || true)
target_tab_id=$(printf '%s' "$target_pane_json" | jq -r '.tab_id | tostring' 2>/dev/null || true)

if [ -z "$target_pane_id" ] || [ -z "$target_tab_id" ] || [ "$target_tab_id" = "null" ]; then
  exit 0
fi

tab_panes=$(printf '%s' "$panes_json" | jq -r --arg tab_id "$target_tab_id" '
  .[]
  | select(((.is_plugin // false) | not) and (((.exited // false) | not)) and ((.tab_id | tostring) == $tab_id))
  | .id
  | tostring
' 2>/dev/null | sort -u || true)

safe_tab=$(printf '%s' "$target_tab_id" | tr -c 'A-Za-z0-9_.-' '_')
cache_dir="$runtime_root/$safe_session/$safe_tab"
mkdir -p "$cache_dir"

cache_file="$cache_dir/$target_pane_id.json"
previous_state=""
if [ -f "$cache_file" ]; then
  previous_state=$(jq -r '.state // empty' "$cache_file" 2>/dev/null || true)
fi

jq -n \
  --arg pane_id "$target_pane_id" \
  --arg tab_id "$target_tab_id" \
  --arg state "$cache_state" \
  --arg message "$message" \
  --arg timestamp "$(date +%s)" \
  '{pane_id: $pane_id, tab_id: $tab_id, state: $state, message: $message, updated_at: ($timestamp | tonumber)}' \
  > "$cache_file" 2>/dev/null || true

case "$state:$previous_state" in
  blocked:blocked) ;;
  blocked:*) play_sound blocked ;;
  idle:working) play_sound idle ;;
  orchestrator-idle:working) play_sound orchestrator-idle ;;
esac

for state_file in "$cache_dir"/*.json; do
  [ -f "$state_file" ] || continue
  cached_pane_id=$(basename "$state_file" .json)
  pane_still_active=0
  while IFS= read -r active_pane_id; do
    [ -n "$active_pane_id" ] || continue
    if [ "$active_pane_id" = "$cached_pane_id" ]; then
      pane_still_active=1
      break
    fi
  done <<EOF
$tab_panes
EOF
  [ "$pane_still_active" -eq 1 ] || rm -f "$state_file"
done

case "$cache_state" in
  working) pane_title="◉ OC | working" ;;
  blocked) pane_title="◆ OC | blocked" ;;
  idle) pane_title="○ OC | idle" ;;
esac

if ! zellij action rename-pane --pane-id "$target_pane_id" "$pane_title" >/dev/null 2>&1; then
  if [ -n "$current_process_pane_id" ] && [ "$target_pane_id" = "$current_process_pane_id" ]; then
    zellij action rename-pane "$pane_title" >/dev/null 2>&1 || true
  fi
fi

if [ "${PEGASUS_ZELLIJ_RENAME_TAB:-1}" = "0" ]; then
  exit 0
fi

blocked_count=0
working_count=0
idle_count=0

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

if [ "$blocked_count" -gt 0 ]; then
  tab_title="◆ OC | blocked ($blocked_count)"
elif [ "$working_count" -gt 0 ]; then
  tab_title="◉ OC | working ($working_count)"
elif [ "$idle_count" -gt 0 ]; then
  tab_title="○ OC | idle"
else
  tab_title="○ OC | idle"
fi

rename_tab_help=$(zellij action rename-tab --help 2>&1 || true)
case "$rename_tab_help" in
  *--tab-id*)
    zellij action rename-tab --tab-id "$target_tab_id" "$tab_title" >/dev/null 2>&1 || true
    ;;
  *)
    if [ -n "$current_process_pane_id" ] && [ "$target_pane_id" = "$current_process_pane_id" ]; then
      zellij action rename-tab "$tab_title" >/dev/null 2>&1 || true
    fi
    ;;
esac
