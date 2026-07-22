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

ThinkLight opens minimal capture sessions on both the Mac's built-in camera
and an attached Studio Display camera (lowest preset, every frame discarded,
nothing stored) to switch both LEDs on, and kills the sessions to switch them
off. Without a Studio Display, it automatically uses only the built-in camera.
Agent lifecycle hooks do the rest.

## Install

Requires macOS with Xcode Command Line Tools (`swiftc`).

```bash
git clone https://github.com/lichengzhe/thinklight.git
cd thinklight
./install.sh                    # builds to ~/.local/bin
~/.local/bin/thinklight blink 3 # first run triggers the camera permission prompt
~/.local/bin/thinklight check   # built-in and Studio Display cameras should report RUNNING
```

To upgrade later: `git pull && ./install.sh`. The hooks run the copy
installed in `~/.local/bin`, so a plugin update alone refreshes the repo
but not the installed binaries — re-run `install.sh` after updating.
No state migration is ever needed.

## Usage

```
thinklight on              register this session and turn the LED on
thinklight off [--force]   deregister this session; the LED goes off when the
                           last session leaves (--force, or a plain `off`
                           typed at a terminal: clear all sessions, off now)
thinklight status          on | off
thinklight blink [secs]    on, wait, off
thinklight pulse [times]   alternate both LEDs n times (default 3; blink one), then stay on
thinklight check           hardware-level truth via CoreMediaIO
```

## Claude Code

Add to `~/.claude/settings.json` (merge with existing settings):

```json
"hooks": {
  "UserPromptSubmit": [
    { "hooks": [{ "type": "command", "command": "$HOME/.local/bin/thinklight on", "timeout": 10, "async": true }] }
  ],
  "Stop": [
    { "hooks": [{ "type": "command", "command": "$HOME/.local/bin/thinklight off", "timeout": 10, "async": true }] }
  ],
  "SessionEnd": [
    { "hooks": [{ "type": "command", "command": "$HOME/.local/bin/thinklight off", "timeout": 10 }] }
  ]
}
```

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

`thinklight-daemon` opens a separate `AVCaptureSession` for the Mac's built-in
camera and the Apple Studio Display camera, each with an
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

**Multiple agents / sessions?** Fully supported. Claude Code and Codex
sessions all share one LED: each session registers a token under
`~/.local/state/thinklight` when a prompt starts and removes it when the
turn ends, and the light goes dark only when the **last** session finishes.
When one session stops while others are still working, the Mac and Studio
Display LEDs alternate three times before both stay on again (or the one
available LED blinks) — a glanceable "one of them is done".
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
- **Multi-state signaling** — blink patterns for "waiting for approval"
  (`Notification` hook) vs steady-on for "working"
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
