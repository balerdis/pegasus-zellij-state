#!/usr/bin/env bash
set -u

state_config_dir="$HOME/.config/pegasus-zellij-state"
script_target_dir="$state_config_dir/scripts"
opencode_config="$HOME/.config/opencode/opencode.json"
opencode_plugin_ts_target="$HOME/.config/opencode/plugins/pegasus-zellij-state.ts"
opencode_plugin_js_target="$HOME/.config/opencode/plugins/pegasus-zellij-state.js"
opencode_plugin_ts_url="file://$opencode_plugin_ts_target"
opencode_plugin_js_url="file://$opencode_plugin_js_target"

rm -f "$script_target_dir/agent-report.sh" "$script_target_dir/zellij-agent-report.sh"
rm -f "$opencode_plugin_ts_target" "$opencode_plugin_js_target"

if [ -f "$opencode_config" ]; then
  if command -v node >/dev/null 2>&1; then
    OPENCODE_CONFIG="$opencode_config" \
      OPENCODE_PLUGIN_TS_URL="$opencode_plugin_ts_url" \
      OPENCODE_PLUGIN_JS_URL="$opencode_plugin_js_url" \
      node <<'NODE'
const fs = require("node:fs");

const configPath = process.env.OPENCODE_CONFIG;
const pluginUrls = new Set([process.env.OPENCODE_PLUGIN_TS_URL, process.env.OPENCODE_PLUGIN_JS_URL]);

const config = JSON.parse(fs.readFileSync(configPath, "utf8"));
if (!config || typeof config !== "object" || Array.isArray(config)) {
  throw new Error(`${configPath} must contain a JSON object`);
}

if (Array.isArray(config.plugin)) {
  config.plugin = config.plugin.filter((entry) => !pluginUrls.has(entry));
  fs.writeFileSync(configPath, `${JSON.stringify(config, null, 2)}\n`);
}
NODE
  else
    printf '%s\n' "Warning: node was not found; OpenCode plugin deregistration was skipped." >&2
  fi
fi

rmdir "$script_target_dir" 2>/dev/null || true
rmdir "$state_config_dir" 2>/dev/null || true

cat <<'EOF'
Uninstalled Pegasus Zellij State.

The Pegasus plugin entry was removed from OpenCode configuration when possible.
EOF
