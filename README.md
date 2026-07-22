# ThinkLight 💡

**Turn your Mac's camera LED into an unfakeable "AI agent is working" status light.**

Green light on → your agent (Claude Code, Codex, …) is thinking.
Light off → it's your turn.

[中文文档](README.zh-CN.md)

## Why the camera LED?

The green LED next to your Mac's camera is wired to the camera sensor's power
at the hardware level. macOS provides no API to control the LED directly —
it is on if and only if the camera is actually capturing. That privacy
guarantee cuts both ways: it also makes the LED the one status indicator on
your machine that **no software can fake**. No menu-bar widget to hunt for,
no terminal to glance at — a physical light at eye level, visible from across
the room.

ThinkLight opens a minimal capture session on the built-in camera (lowest
preset, every frame discarded, nothing stored) to switch the LED on, and
kills the session to switch it off. Agent lifecycle hooks do the rest.

## Install

Requires macOS with Xcode Command Line Tools (`swiftc`).

```bash
git clone https://github.com/leecz/thinklight.git
cd thinklight
./install.sh                    # builds to ~/.local/bin
~/.local/bin/thinklight blink 3 # first run triggers the camera permission prompt
~/.local/bin/thinklight check   # FaceTime HD Camera should report RUNNING
```

## Usage

```
thinklight on              turn the LED on (spawns a tiny daemon)
thinklight off             turn it off
thinklight status          on | off
thinklight blink [secs]    on, wait, off
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
/plugin marketplace add leecz/thinklight
/plugin install thinklight@thinklight
```

## Codex CLI

Codex (≥ 0.145) uses the same hooks format, loaded via plugins:

```bash
codex plugin marketplace add https://github.com/leecz/thinklight.git
codex plugin add thinklight@thinklight
codex   # accept the hook trust prompt in the interactive session
```

Note: `codex exec` (non-interactive) does not fire `UserPromptSubmit`, so the
light is meaningful in interactive sessions only.

## How it works — and the pitfall

`thinklight-daemon` is ~60 lines of Swift: an `AVCaptureSession` on the
built-in camera (`.builtInWideAngleCamera` only — it will never grab your
Studio Display or Continuity iPhone camera) with a delegate that discards
every frame.

The non-obvious part: **a session with an input but no output never actually
starts capturing** — `session.isRunning` reports `true` while the camera
stays dark. You must attach an `AVCaptureVideoDataOutput`, even one that
throws every frame away. `thinklight check` reads
`kCMIODevicePropertyDeviceIsRunningSomewhere` via CoreMediaIO so you can
assert the hardware state instead of trusting the API or your eyes.

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

**Multiple agent sessions?** They share one LED and one pidfile; whichever
session stops last turns the light off. Precise per-session refcounting is a
possible future improvement.

**~2s latency from prompt to light** is the camera powering up. Normal.

## Roadmap

ThinkLight's core idea is `agent state → a physical light`. The built-in
camera LED is the first backend; planned/possible backends include:

- **Keyboard backlight** — pulse or toggle the MacBook keyboard backlight
  (CoreBrightness) as a subtler, silent indicator
- **External camera LEDs** — same capture-session trick on UVC webcams and
  the Studio Display camera (select a backend per display setup, e.g.
  clamshell mode where the built-in LED is hidden)
- **Display-based indicators** — brightness pulse or a screen-edge glow for
  setups with no controllable LED at all
- **Multi-state signaling** — blink patterns for "waiting for approval"
  (`Notification` hook) vs steady-on for "working"
- **Per-session refcounting** — accurate indication with multiple concurrent
  agent sessions

Contributions welcome.

## Disclaimer

ThinkLight is an independent open-source project, not affiliated with or
endorsed by Lenovo (whose ThinkPad keyboard light of the same name we
remember fondly) or Apple.

## License

MIT
