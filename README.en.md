# ThinkLight 🟢

**Know when your AI agent needs you without switching back to the terminal.**

ThinkLight turns the green LED beside your Mac's built-in camera into a status
light for Claude Code and Codex CLI:

| Light | Meaning |
| --- | --- |
| On | An agent is running |
| Off | No agent is running — finished, or waiting for your input |

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

With multiple sessions, the LED stays on as long as any session is still
running, and turns off once they have all finished.

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
  "Stop": [
    { "hooks": [{ "type": "command", "command": "$HOME/.local/bin/thinklight off", "timeout": 10 }] }
  ]
}
```

The light turns on when you submit a message (`UserPromptSubmit`) and turns off
when the turn ends (`Stop`). If a session exits or crashes, the daemon clears
its state within a second. A pending permission prompt counts as running, so
the light stays on.

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
thinklight off [--force]    deregister the current session
                            at a terminal or with --force: clear state and turn off now
thinklight status           print on or off
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
  app is using the camera, however, the LED remains on, so it cannot reflect
  ThinkLight's state on its own.
- **Camera selection:** ThinkLight uses only the Mac's built-in camera, not a
  Studio Display, Continuity Camera, or another external camera.
- **Unexpected exits:** ThinkLight checks each session's owner process once per
  second and removes state for processes that have exited. Claude Code currently
  has no hook for an Esc interrupt, so the LED may remain on temporarily; it
  turns off when the next turn ends, or you can run `thinklight off`.

## How it works

The ThinkLight Swift daemon starts an `AVCaptureSession` on the built-in camera.
macOS turns on the hardware-linked green indicator while the camera is actually
capturing and turns it off when capture stops. Once a second the daemon checks
the sessions registered by each agent: while any is still running it keeps
capturing (light on); when none remain it stops and exits (light off).

## License

MIT
