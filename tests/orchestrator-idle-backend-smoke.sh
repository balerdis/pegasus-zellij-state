#!/usr/bin/env bash
set -euo pipefail

repo_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
backend="$repo_dir/scripts/zellij-agent-report.sh"
temp_dir=$(mktemp -d)
trap 'rm -rf "$temp_dir"' EXIT
mock_bin="$temp_dir/bin"
mkdir -p "$mock_bin"
sound_file="$temp_dir/attention.oga"
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
[ "$1" = "$PEGASUS_ZELLIJ_SOUND_IDLE" ] && printf '%s\n' "$1" >> "$PLAYER_LOG"
EOF
chmod +x "$mock_bin/zellij" "$mock_bin/paplay"

run_report() {
  env PATH="$mock_bin:$PATH" ZELLIJ=mock ZELLIJ_SESSION_NAME=test \
    XDG_RUNTIME_DIR="$temp_dir/runtime" PLAYER_LOG="$sound_log" \
    PEGASUS_ZELLIJ_SOUND_IDLE="$sound_file" \
    "$backend" 7 "$1" test
}

assert_sound_count() {
  actual=$(wc -l < "$sound_log" | tr -d ' ')
  [ "$actual" = "$1" ] || {
    printf 'expected %s attention sounds, got %s\n' "$1" "$actual" >&2
    exit 1
  }
}

# Root working -> idle: attention sound once; cache stays normal idle.
run_report working
run_report orchestrator-idle
assert_sound_count 1
cache_file="$temp_dir/runtime/pegasus-zellij-state/test/3/7.json"
[ "$(jq -r '.state' "$cache_file")" = "idle" ]
run_report orchestrator-idle
assert_sound_count 1

# A child or unknown working -> ordinary idle transition is silent.
: > "$sound_log"
run_report working
run_report idle
assert_sound_count 0

# Entering blocked plays the attention sound once; repeats and blocked -> idle are silent.
: > "$sound_log"
run_report blocked
assert_sound_count 1
run_report blocked
run_report idle
run_report idle
assert_sound_count 1

# Global sound disable suppresses every attention transition.
: > "$sound_log"
env PATH="$mock_bin:$PATH" ZELLIJ=mock ZELLIJ_SESSION_NAME=global-off \
  XDG_RUNTIME_DIR="$temp_dir/runtime" PLAYER_LOG="$sound_log" PEGASUS_ZELLIJ_SOUND=0 \
  PEGASUS_ZELLIJ_SOUND_IDLE="$sound_file" "$backend" 7 working test
env PATH="$mock_bin:$PATH" ZELLIJ=mock ZELLIJ_SESSION_NAME=global-off \
  XDG_RUNTIME_DIR="$temp_dir/runtime" PLAYER_LOG="$sound_log" PEGASUS_ZELLIJ_SOUND=0 \
  PEGASUS_ZELLIJ_SOUND_IDLE="$sound_file" "$backend" 7 orchestrator-idle test
env PATH="$mock_bin:$PATH" ZELLIJ=mock ZELLIJ_SESSION_NAME=global-off-blocked \
  XDG_RUNTIME_DIR="$temp_dir/runtime" PLAYER_LOG="$sound_log" PEGASUS_ZELLIJ_SOUND=0 \
  PEGASUS_ZELLIJ_SOUND_IDLE="$sound_file" "$backend" 7 blocked test
assert_sound_count 0

printf '%s\n' 'orchestrator idle backend smoke tests passed'
