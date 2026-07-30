# Pegasus Zellij State

Show OpenCode agent state directly in your Zellij pane and tab titles.

Pegasus Zellij State is a small OpenCode + Zellij integration for developers who run multiple AI coding agents across tabs and panes. It makes agent status visible at the terminal-multiplexer level, so you can see when an agent is working, waiting for you, or idle without hunting through every pane.

## What you get

| State | Meaning | Pane title | Tab title |
| --- | --- | --- | --- |
| `working` | OpenCode is processing, streaming, or running tools. | `◉ OpenCode working` | `◉ OC \| working (n)` |
| `blocked` | OpenCode is waiting for permission, confirmation, or an answer. Plays an attention sound on transition into blocked. | `◆ OpenCode blocked` | `◆ OC \| blocked (n)` |
| `idle` | OpenCode is done or inactive. Plays a done sound only when transitioning from working to idle. | `○ OpenCode idle` | `○ OC \| idle` |

When OpenCode reports that a known root/orchestrator session completes, Pegasus plays a distinct, more noticeable completion sound instead of the normal idle tone. It uses OpenCode's session hierarchy (`parentID`): subagent completion never triggers this sound.

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
working / blocked / idle / orchestrator-idle
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
- optional sound player: `paplay`, `canberra-gtk-play`, `aplay`, or `afplay`

Runtime scripts fail safely as no-ops when required tools or Zellij environment variables are missing.

Sound support is also best-effort. If no supported player or default sound file exists, titles still update and playback is skipped silently.

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

## Sound behavior

Sounds are handled by the Zellij backend script, not the OpenCode plugin. They are enabled by default when both a supported player and a usable sound file are present.

Playback is intentionally quiet about failures:

- `blocked` plays only when a pane transitions into `blocked`, not on repeated blocked reports.
- `idle` plays only when a pane transitions from `working` to `idle`.
- `idle` does not play when a pane transitions from `blocked` to `idle`.
- A known root/orchestrator `working` → `idle` transition plays the distinct orchestrator completion sound instead of the normal idle tone. Repeated idle reports and `blocked` → `idle` do not replay it.
- OpenCode sessions are treated as root only after explicit session information confirms an empty or absent `parentID`; unknown sessions stay on the normal idle behavior.
- Title updates do not wait for sound playback to finish.

Supported players are tried in this order:

1. `paplay`
2. `canberra-gtk-play`
3. `aplay`
4. `afplay`

Default blocked sound candidates:

```text
/usr/share/sounds/freedesktop/stereo/dialog-warning.oga
/usr/share/sounds/freedesktop/stereo/alarm-clock-elapsed.oga
/System/Library/Sounds/Funk.aiff
```

Default idle sound candidates:

```text
/usr/share/sounds/freedesktop/stereo/complete.oga
/usr/share/sounds/freedesktop/stereo/message.oga
/System/Library/Sounds/Glass.aiff
```

Default root/orchestrator idle sound candidates:

```text
/usr/share/sounds/freedesktop/stereo/bell.oga
/usr/share/sounds/freedesktop/stereo/complete.oga
/System/Library/Sounds/Hero.aiff
/System/Library/Sounds/Glass.aiff
```

Disable all sounds:

```bash
export PEGASUS_ZELLIJ_SOUND=0
```

Override sound files:

```bash
export PEGASUS_ZELLIJ_SOUND_BLOCKED=/path/to/blocked-sound.oga
export PEGASUS_ZELLIJ_SOUND_IDLE=/path/to/idle-sound.oga
export PEGASUS_ZELLIJ_SOUND_ORCHESTRATOR_IDLE=/path/to/orchestrator-done.oga
```

Disable only the root/orchestrator completion sound (normal blocked and idle sounds remain enabled):

```bash
export PEGASUS_ZELLIJ_SOUND_ORCHESTRATOR_IDLE_ENABLED=0
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
command -v paplay || command -v canberra-gtk-play || command -v aplay || command -v afplay
```

Check default sound files:

```bash
for file in \
  /usr/share/sounds/freedesktop/stereo/dialog-warning.oga \
  /usr/share/sounds/freedesktop/stereo/alarm-clock-elapsed.oga \
  /usr/share/sounds/freedesktop/stereo/complete.oga \
  /usr/share/sounds/freedesktop/stereo/message.oga \
  /usr/share/sounds/freedesktop/stereo/bell.oga \
  /System/Library/Sounds/Funk.aiff \
  /System/Library/Sounds/Hero.aiff \
  /System/Library/Sounds/Glass.aiff; do
  [ -f "$file" ] && printf 'found: %s\n' "$file"
done
```

Run a title-only smoke test without audio:

```bash
PEGASUS_ZELLIJ_SOUND=0 ~/.config/pegasus-zellij-state/scripts/agent-report.sh "$ZELLIJ_PANE_ID" working "manual test"
PEGASUS_ZELLIJ_SOUND=0 ~/.config/pegasus-zellij-state/scripts/agent-report.sh "$ZELLIJ_PANE_ID" blocked "manual test"
PEGASUS_ZELLIJ_SOUND=0 ~/.config/pegasus-zellij-state/scripts/agent-report.sh "$ZELLIJ_PANE_ID" idle "manual test"
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
