# ThinkLight 🟢

**A silent, glanceable status light for AI agents — powered by your Mac's
camera LED.**

Green light on → your agent (Claude Code, Codex, …) is still working.
Light off → it's done. Your turn.

[中文文档](README.md)

## Why?

Agents run long. You switch to other work — and then keep interrupting
yourself to check whether they're finished. ThinkLight moves that answer
into your peripheral vision: no notification to dismiss, no sound, no window
to keep visible. One glance. Light on: keep doing what you're doing.
Light off: the run is over.

The camera LED happens to be perfect for this. It sits at eye level, visible
from across the room, and it's wired to the camera sensor's power at the
hardware level — macOS provides no API to control it directly; it is on if
and only if the camera is actually capturing.

ThinkLight treats the Mac's built-in camera and an attached Studio Display
camera as two status-light slots. The first active session takes the built-in
LED, the second takes the Studio Display LED, and further sessions go to the
less-used side. Each LED goes dark only when its last assigned session ends.
Without a Studio Display, every session shares the built-in LED.

## Install

Requires macOS with Xcode Command Line Tools (`swiftc`).

```bash
git clone https://github.com/lichengzhe/thinklight.git
cd thinklight
./install.sh                    # builds to ~/.local/bin
~/.local/bin/thinklight blink 3 # first run requests permission and lights an LED for 3s
```

ThinkLight checks `main` once every 24 hours in the background and sends a
macOS notification when an update is available; it never installs updates
automatically. Run `thinklight update --check` to check manually, or
`thinklight update` to fast-forward a clean `main` checkout, rebuild, and
preserve the current session state. `git pull && ./install.sh` still works.

## Usage

```
thinklight on              register this session and assign a status LED
thinklight off [--force]   deregister this session; its LED goes off when the
                           last assigned session leaves (--force, or plain `off`
                           typed at a terminal: clear all sessions, off now)
thinklight status          on | off
thinklight blink [secs]    on, wait, off
thinklight check           hardware-level truth via CoreMediaIO
thinklight update --check  check whether an update is available
thinklight update          safely update the source and reinstall
```

## Claude Code

Add to `~/.claude/settings.json` (merge with existing settings):

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

This makes the light's meaning strict: **on = the agent is working, ignore it;
off = it needs you** — the run finished (`Stop`), the API failed
(`StopFailure`), or it is sitting at a permission prompt waiting for your
approval (`Notification`). After you approve, the light comes back on as soon
as the next tool call completes (`PostToolUse`).

Or install as a plugin — this repo is also a plugin marketplace:

```
/plugin marketplace add lichengzhe/thinklight
/plugin install thinklight@thinklight
```

## Codex CLI

Codex (≥ 0.145) uses the same hooks format, loaded via plugins:

```bash
codex plugin marketplace add https://github.com/lichengzhe/thinklight.git
codex plugin add thinklight@thinklight
codex   # accept the hook trust prompt in the interactive session
```

Note: `codex exec` (non-interactive) does not fire `UserPromptSubmit`, so the
light is meaningful in interactive sessions only.

## How it works

`thinklight-daemon` can open an independent `AVCaptureSession` for either the
Mac's built-in camera or the Apple Studio Display camera, each with an
`AVCaptureVideoDataOutput` that discards every frame — a session needs an
output before it actually starts capturing and lights the LED. Other external
cameras and Continuity Camera iPhones are excluded.
`thinklight check` reads `kCMIODevicePropertyDeviceIsRunningSomewhere` via
CoreMediaIO to confirm the hardware state of the light.

## FAQ

**Does it interfere with video calls?**
No. macOS allows multiple processes to share the camera; Zoom / Meet /
Tencent Meeting open it normally while ThinkLight holds it, and each side is
unaffected when the other exits. (During a call the LED is on anyway, so the
indicator is temporarily meaningless.)

**Privacy?** Frames are discarded inside the capture callback; nothing is
read, processed, or written. The menu bar will show the standard green
"camera in use" indicator attributed to your terminal — that's the OS honesty
this project is built on.

**Power?** Lowest session preset, no encoding, no I/O. Negligible.

**Light still on after pressing Esc?** Claude Code currently fires no hook
event on a user interrupt, so the light stays on until that session's next
turn ends or the session exits. A manual `thinklight off` clears it
immediately.

**Multiple agents / sessions?** Fully supported. Each session registers or
refreshes a token under `~/.local/state/thinklight` when a prompt is submitted
and each time a tool call completes, and deregisters when the turn ends, the
API fails, or it is waiting for permission approval. With a Studio Display, the first active session takes the built-in
LED, the second takes the Studio Display LED, and further sessions go to the
side with fewer active sessions (built-in wins ties). Each LED is independently
reference-counted and goes dark when its last assigned session finishes.
Without a Studio Display—or after it is disconnected—every session
automatically shares the built-in LED.
Tokens are verified against live processes on every call, so a crashed
session can never leave the LED stuck on; and a plain `thinklight off`
typed by a human always wins immediately.

**~2s latency from prompt to light** is the camera powering up. Normal.

## Roadmap

ThinkLight's core idea is `agent state → physical lights`. The built-in and
Studio Display camera LEDs are the first backend; planned/possible backends
include:

- **Keyboard backlight** — pulse or toggle the MacBook keyboard backlight
  (CoreBrightness) as a subtler, silent indicator
- **Other external camera LEDs** — extend the same capture-session trick to
  third-party UVC webcams, with backend selection per setup
- **Display-based indicators** — brightness pulse or a screen-edge glow for
  setups with no controllable LED at all
- **Multi-state signaling** — "waiting for approval turns the light off" is
  built in (`Notification` hook); blink patterns for richer states could
  follow
- **Windows support** — most laptop webcam LEDs are likewise hardwired to
  capture; the same hold-the-camera trick should port via Media Foundation,
  with vendor keyboard-backlight SDKs as further backends

Contributions welcome.

## Disclaimer

ThinkLight is an independent open-source project, not affiliated with or
endorsed by Lenovo (whose ThinkPad keyboard light of the same name we
remember fondly) or Apple.

## License

MIT
