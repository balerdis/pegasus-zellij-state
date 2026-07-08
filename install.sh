#!/usr/bin/env bash
set -eu

repo_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
script_source_dir="$repo_dir/scripts"
state_config_dir="$HOME/.config/pegasus-zellij-state"
script_target_dir="$state_config_dir/scripts"
opencode_plugin_dir="$HOME/.config/opencode/plugins"
opencode_plugin_target="$opencode_plugin_dir/pegasus-zellij-state.ts"
stale_opencode_plugin_target="$opencode_plugin_dir/pegasus-zellij-state.js"
opencode_config="$HOME/.config/opencode/opencode.json"
opencode_plugin_url="file://$opencode_plugin_target"
stale_opencode_plugin_url="file://$stale_opencode_plugin_target"

mkdir -p "$script_target_dir" "$opencode_plugin_dir"

cp "$script_source_dir/agent-report.sh" "$script_target_dir/agent-report.sh"
cp "$script_source_dir/zellij-agent-report.sh" "$script_target_dir/zellij-agent-report.sh"
cp "$repo_dir/adapters/opencode/pegasus-zellij-state.ts" "$opencode_plugin_target"
rm -f "$stale_opencode_plugin_target"

chmod 0755 "$script_target_dir/agent-report.sh" "$script_target_dir/zellij-agent-report.sh"

if command -v node >/dev/null 2>&1; then
  OPENCODE_CONFIG="$opencode_config" \
    OPENCODE_PLUGIN_URL="$opencode_plugin_url" \
    STALE_OPENCODE_PLUGIN_URL="$stale_opencode_plugin_url" \
    node <<'NODE'
const fs = require("node:fs");

const configPath = process.env.OPENCODE_CONFIG;
const pluginUrl = process.env.OPENCODE_PLUGIN_URL;
const stalePluginUrl = process.env.STALE_OPENCODE_PLUGIN_URL;

let config = {
  "$schema": "https://opencode.ai/config.json",
  plugin: [],
};

if (fs.existsSync(configPath)) {
  config = JSON.parse(fs.readFileSync(configPath, "utf8"));
  if (!config || typeof config !== "object" || Array.isArray(config)) {
    throw new Error(`${configPath} must contain a JSON object`);
  }
  if (config.plugin === undefined) {
    config.plugin = [];
  }
  if (!Array.isArray(config.plugin)) {
    throw new Error(`${configPath} plugin field must be an array`);
  }
}

config.plugin = config.plugin.filter((entry) => entry !== stalePluginUrl);

if (!config.plugin.includes(pluginUrl)) {
  config.plugin.push(pluginUrl);
}

fs.writeFileSync(configPath, `${JSON.stringify(config, null, 2)}\n`);
NODE
else
  printf '%s\n' "Warning: node was not found; OpenCode plugin registration was skipped." >&2
fi

cat <<'EOF'
Installed Pegasus Zellij State.

Next steps:
- Restart OpenCode inside Zellij.
- Confirm ~/.config/opencode/opencode.json contains the Pegasus plugin entry.
- Verify ZELLIJ_PANE_ID is present: printf '%s\n' "$ZELLIJ_PANE_ID"
- To disable tab rollup: export PEGASUS_ZELLIJ_RENAME_TAB=0
EOF
