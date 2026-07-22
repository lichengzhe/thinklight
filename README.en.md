# ThinkLight 🟢

**The Mac camera LED, repurposed as your AI-agent status light.**

**Steady**: agents are working — go do something else. **Blinking**: a session
is waiting on you. **Off**: everything's done.

[中文](README.md)

## Why

Agents run for minutes. You switch away, then keep switching back to check.
ThinkLight puts the answer in your peripheral vision: no popups, no sounds,
no terminal to watch — one glance tells you whether to return.

The camera LED is the perfect vehicle: eye-level, visible across the room,
and wired to the capture hardware — macOS offers no API to fake it. It is lit
if and only if the camera is really capturing. **A lit LED cannot lie.**

## Install

Requires macOS with Xcode Command Line Tools (`swiftc`).

```bash
git clone https://github.com/lichengzhe/thinklight.git
cd thinklight
./install.sh                    # builds to ~/.local/bin
~/.local/bin/thinklight blink 3 # first run asks camera permission, lights up 3s
```

ThinkLight notifies you when an update lands (one background check per 24h,
never auto-installs); `thinklight update` upgrades in one step.

## Usage

```
thinklight on              mark this session "working"
thinklight off [--force]   turn ended: mark "waiting for you"; session gone: drop it
                           (plain `off` at a terminal / --force: clear all, off now)
thinklight status          on | blink | off
thinklight blink [secs]    on, wait, off
thinklight check           hardware-level truth via CoreMediaIO
thinklight update [--check] update / check for updates
```

## Claude Code

One-line plugin install (this repo is its own marketplace):

```
/plugin marketplace add lichengzhe/thinklight
/plugin install thinklight@thinklight
```

Or merge into `~/.claude/settings.json` by hand:

```json
"hooks": {
  "UserPromptSubmit": [
    { "hooks": [{ "type": "command", "command": "$HOME/.local/bin/thinklight on", "timeout": 10 }] }
  ],
  "PostToolUse": [
    { "hooks": [{ "type": "command", "command": "$HOME/.local/bin/thinklight on", "timeout": 10 }] }
  ],
  "Notification": [
    { "matcher": "permission_prompt", "hooks": [{ "type": "command", "command": "$HOME/.local/bin/thinklight off", "timeout": 10 }] }
  ],
  "Stop": [
    { "hooks": [{ "type": "command", "command": "$HOME/.local/bin/thinklight off", "timeout": 10 }] }
  ],
  "StopFailure": [
    { "hooks": [{ "type": "command", "command": "$HOME/.local/bin/thinklight off", "timeout": 10 }] }
  ],
  "SessionEnd": [
    { "hooks": [{ "type": "command", "command": "$HOME/.local/bin/thinklight off", "timeout": 3 }] }
  ]
}
```

Strict semantics: **steady = working; blinking = a session awaits you** — turn
finished (`Stop`), API failed (`StopFailure`), or stuck at a permission prompt
(`Notification`); **off = no sessions left at all**.

## Codex CLI

Codex (≥ 0.145) uses the same hook format, wired via the plugin:

```bash
codex plugin marketplace add https://github.com/lichengzhe/thinklight.git
codex plugin add thinklight@thinklight
codex   # confirm the hook trust prompt in an interactive session
```

## How it works

A Swift daemon opens one frame-discarding `AVCaptureSession` on the built-in
camera — the LED is lit exactly while the session captures. Every second the
daemon reconciles per-session tokens (sweeping any whose host process died):
someone waiting → blink 1s lit / 1s dark; nobody left → light off, exit.
Multiple sessions, crashes, power loss — the LED always reflects reality.
Built-in camera only, so macOS never draws the external-camera green icon
in your menu bar.

## FAQ

**Video calls?** Unaffected — macOS shares the camera across processes; Zoom
and friends work normally. **Privacy?** Every frame is discarded in the
callback, never read or stored. **Power?** Lowest preset, no encoding, no
I/O — negligible. **Light still on after Esc?** Claude Code has no interrupt
hook; it recovers when the turn ends, or run `thinklight off`.

## License

MIT
