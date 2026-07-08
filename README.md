# Pegasus Zellij State

Show OpenCode agent state directly in your Zellij pane and tab titles.

Pegasus Zellij State is a small OpenCode + Zellij integration for developers who run multiple AI coding agents across tabs and panes. It makes agent status visible at the terminal-multiplexer level, so you can see when an agent is working, waiting for you, or idle without hunting through every pane.

## What you get

| State | Meaning | Pane title | Tab title |
| --- | --- | --- | --- |
| `working` | OpenCode is processing, streaming, or running tools. | `◉ OpenCode working` | `◉ OC \| working (n)` |
| `blocked` | OpenCode is waiting for permission, confirmation, or an answer. | `◆ OpenCode blocked` | `◆ OC \| blocked (n)` |
| `idle` | OpenCode is done or inactive. | `○ OpenCode idle` | `○ OC \| idle` |

Tab titles roll up the strongest known state in the current tab:

```text
blocked > working > idle
```

That means if one pane in a tab needs your attention, the tab shows it.

## Why this exists

OpenCode can work across long-running conversations, tool calls, permission prompts, and background-like waiting states. When you use Zellij heavily, especially one project or agent per tab, the important question is simple:

> Which agent needs me right now?

This repo answers that by connecting OpenCode events to native Zellij title actions.

It intentionally does **not** include tmux, Ghostty, Claude, Codex, Python hook merging, or multi-agent installer complexity. This is a focused project: **OpenCode state in Zellij**.

## How it works

```text
OpenCode events
  ↓
OpenCode plugin
  ↓
working / blocked / idle
  ↓
agent-report.sh
  ↓
Zellij pane + tab title updates
```

The OpenCode plugin only activates when OpenCode is running inside Zellij. It checks `ZELLIJ_PANE_ID` or `ZELLIJ` before reporting anything.

## Quick install

From this repository:

```bash
./install.sh
```

The installer:

1. copies scripts to `~/.config/pegasus-zellij-state/scripts/`;
2. copies the OpenCode plugin to `~/.config/opencode/plugins/pegasus-zellij-state.ts`;
3. registers the plugin in `~/.config/opencode/opencode.json` using a `file://` plugin entry;
4. preserves existing OpenCode configuration and plugins.

Then quit and restart OpenCode **inside Zellij**. OpenCode loads plugins at startup, so an already-running OpenCode session will not pick up the new plugin or configuration changes.

## Requirements

- `bash`
- `jq`
- `zellij`
- `opencode`
- Node.js available to OpenCode for plugin execution

Runtime scripts fail safely as no-ops when required tools or Zellij environment variables are missing.

## OpenCode event mapping

OpenCode has many event names. Pegasus Zellij State keeps the UI vocabulary small:

| OpenCode event | Reported state |
| --- | --- |
| `chat.message` | `working` |
| `session.status` with `idle` | `idle` |
| `session.status` with `active`, `busy`, `pending`, `running`, `streaming`, `working`, or `retry` | `working` |
| `tool.execute.before`, `tool.execute.after` | `working` |
| `permission.asked`, `question.asked`, `permission.ask` | `blocked` |
| `permission.replied`, `question.replied`, `question.rejected`, `session.compacted` | `working` |
| `session.idle`, `session.deleted` | `idle` |

The plugin reports state through:

```bash
~/.config/pegasus-zellij-state/scripts/agent-report.sh "$ZELLIJ_PANE_ID" "$state" "$message"
```

## Zellij behavior

Pane titles are updated with native Zellij actions.

Tab rollup is enabled by default because this project is designed for people who use Zellij tabs heavily. The backend resolves the reporting pane through `zellij action list-panes --json`, scopes cached state by that pane's `tab_id`, and rolls up only non-plugin, non-exited panes in the same tab. Stale cache files for panes that no longer exist in that tab are removed during reporting.

The backend stores per-pane state under:

```bash
${XDG_RUNTIME_DIR:-/tmp}/pegasus-zellij-state
```

To disable tab renaming for a session:

```bash
PEGASUS_ZELLIJ_RENAME_TAB=0 opencode
```

Or export it before starting OpenCode:

```bash
export PEGASUS_ZELLIJ_RENAME_TAB=0
```

## Manual smoke test

Run this inside a Zellij pane:

```bash
~/.config/pegasus-zellij-state/scripts/agent-report.sh "$ZELLIJ_PANE_ID" working "manual test"
~/.config/pegasus-zellij-state/scripts/agent-report.sh "$ZELLIJ_PANE_ID" blocked "manual test"
~/.config/pegasus-zellij-state/scripts/agent-report.sh "$ZELLIJ_PANE_ID" idle "manual test"
```

If pane/tab names change, the Zellij backend works. If manual reporting works but OpenCode does not update titles, restart OpenCode and confirm the plugin is registered.

After install or uninstall, restart OpenCode. Plugin files and `opencode.json` are loaded at startup.

## Troubleshooting

Check that OpenCode is running inside Zellij:

```bash
printf '%s\n' "$ZELLIJ_PANE_ID"
```

Check dependencies:

```bash
command -v zellij
command -v jq
```

Confirm OpenCode is configured to load the plugin:

```bash
node -e 'const fs=require("node:fs"); const cfg=JSON.parse(fs.readFileSync(process.env.HOME+"/.config/opencode/opencode.json","utf8")); console.log(cfg.plugin || [])'
```

Inspect cached state:

```bash
ls -la "${XDG_RUNTIME_DIR:-/tmp}/pegasus-zellij-state"
```

Enable plugin event debugging when a permission prompt is not reflected in the tab title:

```bash
PEGASUS_ZELLIJ_STATE_DEBUG=1 opencode
```

Then reproduce the issue and inspect:

```bash
tail -n 100 ~/.cache/pegasus-zellij-state/events.log
```

Debug logging is opt-in and should be disabled during normal use.

Read the current Zellij tab info:

```bash
zellij action list-panes --json | jq .
```

`current-tab-info` is not used for cache scope because it only describes the focused tab. Tab state is scoped by `tab_id` from `list-panes`, which prevents idle or stale panes in other tabs from inflating the current tab rollup.

Modern Zellij versions support targeting tab renames by `--tab-id`; Pegasus uses that when available. If an older Zellij build only supports renaming the focused tab, tab rename is best-effort and driven by the reporting pane context. Pane renames target the resolved pane id with `rename-pane --pane-id` when supported.

## Uninstall

```bash
./uninstall.sh
```

The uninstaller removes:

- installed Pegasus scripts;
- the installed OpenCode plugin file;
- only the Pegasus plugin entry from `~/.config/opencode/opencode.json`.

It does not delete unrelated OpenCode configuration or other plugins.

## Project scope

This repository is intentionally small. It is not a full terminal-state framework.

Included:

- OpenCode plugin;
- Zellij pane title updates;
- Zellij tab rollup;
- install/uninstall scripts.

Not included:

- tmux support;
- Ghostty title integration;
- Claude/Codex hooks;
- pi integration;
- Python hook merging;
- multi-agent installer logic.
