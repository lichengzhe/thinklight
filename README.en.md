# ThinkLight 🟢

**Know when your AI agent needs you without switching back to the terminal.**

ThinkLight turns the green LED beside your Mac's built-in camera into a status
light for Claude Code and Codex CLI:

| Light | Meaning |
| --- | --- |
| Steady | An agent is running |
| Blinking | A session is waiting for your input |
| Off | There are no active sessions |

[中文](README.md)

## When it is useful

When an agent task runs for several minutes, you will often move to an editor,
browser, or another workspace. ThinkLight lets you see its status in your
peripheral vision without repeatedly checking the terminal or adding popups,
sounds, or another window. Because the indicator sits outside the screen, it
remains visible when you change desktops or enter full screen.

It is particularly useful if you:

- regularly give Claude Code or Codex long-running tasks;
- keep several agent sessions open at once;
- want to know when to return without interrupting your current work.

With multiple sessions, the LED blinks as soon as any session needs attention.
It stays steady while all active sessions are running and turns off after every
session exits.

## Install

You need a Mac with a built-in camera and Xcode Command Line Tools (`swiftc`).

Install ThinkLight first:

```bash
git clone https://github.com/lichengzhe/thinklight.git
cd thinklight
./install.sh
```

This builds and installs the programs in `~/.local/bin`. On the first test,
macOS asks for camera access; after permission is granted, the LED stays on for
three seconds:

```bash
~/.local/bin/thinklight blink 3
```

Next, configure hooks for the agent you use. After that, the light follows your
sessions automatically; there is normally no need to run `thinklight on` or
`thinklight off` yourself.

### Claude Code

This repository also provides a Claude Code plugin marketplace:

```text
/plugin marketplace add lichengzhe/thinklight
/plugin install thinklight@thinklight
```

If you prefer not to use the plugin, merge these hooks into
`~/.claude/settings.json`:

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

ThinkLight starts blinking when a turn ends (`Stop`), the API fails
(`StopFailure`), or a permission prompt needs confirmation (`Notification`). It
returns to a steady light when you submit the next message.

### Codex CLI

Codex CLI 0.145 and later can configure the same hooks through the plugin:

```bash
codex plugin marketplace add https://github.com/lichengzhe/thinklight.git
codex plugin add thinklight@thinklight
codex   # confirm the hook trust prompt in an interactive session
```

## Command line

You normally do not need these commands after installing the hooks, but they
are useful for testing, troubleshooting, or integrating another tool:

```text
thinklight on               mark the current session as running
thinklight off [--force]    mark the turn as waiting; remove it when the session exits
                            at a terminal or with --force: clear state and turn off now
thinklight status           print on, blink, or off
thinklight blink [seconds]  turn on for the specified time, then turn off
thinklight check            read the camera hardware state reported by CoreMediaIO
thinklight update --check   check for a new version
thinklight update           update ThinkLight
```

ThinkLight checks for a new version in the background at most once every 24
hours and sends a macOS notification when one is available. The check contacts
this repository; installing an update requires running `thinklight update`.

## Privacy, resources, and compatibility

- **Camera frames:** ThinkLight needs camera permission to activate the hardware
  LED. It discards every captured frame in the callback, without image
  processing or disk storage.
- **Resource use:** Capture uses the low-resolution preset, with no encoding or
  video storage.
- **Video calls:** macOS allows multiple processes to share a camera, and
  ThinkLight has been tested alongside Zoom and Tencent Meeting. While another
  app is using the camera, however, the LED remains on, so it cannot display
  ThinkLight's three states on its own.
- **Camera selection:** ThinkLight uses only the Mac's built-in camera, not a
  Studio Display, Continuity Camera, or another external camera.
- **Unexpected exits:** ThinkLight checks each session's owner process once per
  second and removes state for processes that have exited. Claude Code currently
  has no hook for an Esc interrupt, so the LED may remain steady temporarily;
  it recovers when the turn ends, or you can run `thinklight off`.

## How it works

The ThinkLight Swift daemon starts an `AVCaptureSession` on the built-in camera.
macOS turns on the hardware-linked green indicator while the camera is actually
capturing and turns it off when capture stops. The daemon reads the state written
by each agent session, switches among steady, blinking, and off, and exits when
no sessions remain.

## License

MIT
