#!/usr/bin/env bash
set -euo pipefail

repo_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
backend="$repo_dir/scripts/zellij-agent-report.sh"
temp_dir=$(mktemp -d)
trap 'rm -rf "$temp_dir"' EXIT
mock_bin="$temp_dir/bin"
mkdir -p "$mock_bin"
sound_file="$temp_dir/orchestrator.oga"
sound_log="$temp_dir/sounds.log"
: > "$sound_file"

cat > "$mock_bin/zellij" <<'EOF'
#!/usr/bin/env bash
if [ "$1" = "action" ] && [ "$2" = "list-panes" ]; then
  printf '%s\n' '[{"id":7,"tab_id":3,"is_plugin":false,"exited":false}]'
fi
EOF
cat > "$mock_bin/paplay" <<'EOF'
#!/usr/bin/env bash
[ "$1" = "$PEGASUS_ZELLIJ_SOUND_ORCHESTRATOR_IDLE" ] && printf '%s\n' "$1" >> "$PLAYER_LOG"
EOF
chmod +x "$mock_bin/zellij" "$mock_bin/paplay"

run_report() {
  env PATH="$mock_bin:$PATH" ZELLIJ=mock ZELLIJ_SESSION_NAME=test \
    XDG_RUNTIME_DIR="$temp_dir/runtime" PLAYER_LOG="$sound_log" \
    PEGASUS_ZELLIJ_SOUND_ORCHESTRATOR_IDLE="$sound_file" \
    "$backend" 7 "$1" test
}

assert_sound_count() {
  actual=$(wc -l < "$sound_log" | tr -d ' ')
  [ "$actual" = "$1" ] || {
    printf 'expected %s special sounds, got %s\n' "$1" "$actual" >&2
    exit 1
  }
}

# Root working -> idle: special tone once; cache stays normal idle.
run_report working
run_report orchestrator-idle
assert_sound_count 1
cache_file="$temp_dir/runtime/pegasus-zellij-state/test/3/7.json"
[ "$(jq -r '.state' "$cache_file")" = "idle" ]
run_report orchestrator-idle
assert_sound_count 1

# A blocked -> idle transition must not announce completion.
: > "$sound_log"
run_report working
run_report blocked
run_report orchestrator-idle
assert_sound_count 0

# Both controls suppress the special sound.
: > "$sound_log"
env PATH="$mock_bin:$PATH" ZELLIJ=mock ZELLIJ_SESSION_NAME=global-off \
  XDG_RUNTIME_DIR="$temp_dir/runtime" PLAYER_LOG="$sound_log" PEGASUS_ZELLIJ_SOUND=0 \
  PEGASUS_ZELLIJ_SOUND_ORCHESTRATOR_IDLE="$sound_file" "$backend" 7 working test
env PATH="$mock_bin:$PATH" ZELLIJ=mock ZELLIJ_SESSION_NAME=global-off \
  XDG_RUNTIME_DIR="$temp_dir/runtime" PLAYER_LOG="$sound_log" PEGASUS_ZELLIJ_SOUND=0 \
  PEGASUS_ZELLIJ_SOUND_ORCHESTRATOR_IDLE="$sound_file" "$backend" 7 orchestrator-idle test
assert_sound_count 0

env PATH="$mock_bin:$PATH" ZELLIJ=mock ZELLIJ_SESSION_NAME=special-off \
  XDG_RUNTIME_DIR="$temp_dir/runtime" PLAYER_LOG="$sound_log" \
  PEGASUS_ZELLIJ_SOUND_ORCHESTRATOR_IDLE_ENABLED=0 \
  PEGASUS_ZELLIJ_SOUND_ORCHESTRATOR_IDLE="$sound_file" "$backend" 7 working test
env PATH="$mock_bin:$PATH" ZELLIJ=mock ZELLIJ_SESSION_NAME=special-off \
  XDG_RUNTIME_DIR="$temp_dir/runtime" PLAYER_LOG="$sound_log" \
  PEGASUS_ZELLIJ_SOUND_ORCHESTRATOR_IDLE_ENABLED=0 \
  PEGASUS_ZELLIJ_SOUND_ORCHESTRATOR_IDLE="$sound_file" "$backend" 7 orchestrator-idle test
assert_sound_count 0

printf '%s\n' 'orchestrator idle backend smoke tests passed'
