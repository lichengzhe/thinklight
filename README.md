# ThinkLight 🟢

**English** | [中文](README.zh.md)

**The 🟢 above your MacBook screen, turned into an AI busy light. Zero screen
space — switch apps, go full screen, and still know the moment the AI is done.**

ThinkLight uses the green LED beside the Mac's built-in camera to show the
status of Claude Code and Codex CLI, with optional sound to match:

| State | Light | Sound (off by default) |
| --- | --- | --- |
| The AI is working — go do something else | On | A track loops |
| It's done — your turn | Off | A chime plays once |

> **Setup is one plugin install** — [two commands in Claude Code](#claude-code),
> and it fetches the rest itself.

## Why it helps

Working with an agent is a relay: you hand off a task and the baton is with
the AI; when it finishes, the baton comes back to you. But once a task runs
for a few minutes you switch to something else, and the only way to know the
baton is back is to keep switching to the terminal to check.

ThinkLight puts that signal in your peripheral vision. While the light is on,
the AI is still busy — stay focused on your own work. When it goes out, it is
your turn: review the result, give feedback, hand off the next task. No
popups — and unlike desktop pets and status widgets, it costs zero screen real
estate: the light sits outside your screen, visible across desktops and full
screen.

When you are away from the screen, you can add [sound](#sound-optional-off-by-default)
on top — off by default, turned on with `thinklight unmute`.

It is particularly useful if you:

- regularly hand long-running tasks to Claude Code or Codex;
- keep several agent sessions open at once;
- want to stay focused without missing the handoff.

With multiple sessions, the light stays on while any of them is still working,
and goes out once they have all finished.

## Install

You need a Mac with a built-in camera, running macOS 14 or later.

There are two pieces — the **plugin**, which tells the light when your agent
starts and stops, and the **programs**, which hold the camera so the LED comes on
— but you only install one. On its first session the plugin fetches the programs
that match it into `~/.local/bin` and tells you it did; later plugin updates
bring them along the same way. [Anything about that you would rather do
yourself](#installing-the-programs-yourself) still works, and turning it off is
one command.

### Claude Code

Two commands, and nothing after them:

```text
/plugin marketplace add lichengzhe/thinklight
/plugin install thinklight@thinklight
```

That configures the hooks and adds `/thinklight:unmute`, `/thinklight:mute`, and
`/thinklight:config` for the optional [sound](#sound-optional-off-by-default).
All three are yours to invoke only; Claude never triggers them on its own.

Start a session and the plugin installs the programs in the background —
precompiled universal binaries (Apple Silicon and Intel) from
[Releases](https://github.com/lichengzhe/thinklight/releases) — then posts a
notification when they are in place. The first time the light comes on, macOS asks
for camera access; allow it and the LED follows your agent from then on. To see
the whole thing work at once:

```bash
~/.local/bin/thinklight blink 3   # the LED lights for three seconds
```

### Codex CLI

Codex CLI 0.145 and later installs the same hooks, with the same programs
arriving the same way:

```bash
codex plugin marketplace add https://github.com/lichengzhe/thinklight.git
codex plugin add thinklight@thinklight
codex   # confirm the hook trust prompt in an interactive session
```

### Let an agent install it

Paste this into Claude Code, Codex, or another coding agent that is **running
on this Mac and can use its terminal**:

```text
Please install and configure ThinkLight on this Mac: https://github.com/lichengzhe/thinklight.
First read README.md, get.sh, and plugin/scripts/install-programs.sh to confirm the installation
scope. Prefer the plugin: run `claude plugin marketplace add lichengzhe/thinklight` and
`claude plugin install thinklight@thinklight` for Claude Code, and the codex plugin equivalents for
Codex CLI, falling back to hooks in ~/.claude/settings.json only if the plugin route fails. The
plugin installs the programs itself at session start; if they are not in ~/.local/bin yet, run
get.sh (or clone the repository and run install.sh to build from source). Verify with
~/.local/bin/thinklight blink 3 and ~/.local/bin/thinklight check. Stop and tell me exactly what to
click when macOS asks for camera access or Codex asks me to trust the hooks. When finished, report
the install location, hook configuration, and verification results. Do not change unrelated settings.
```

You still need to personally approve macOS camera access and Codex hook trust.

### Installing the programs yourself

Any of these leaves the plugin nothing to fetch. The automatic install only ever
runs while `~/.local/bin` is missing the programs or holding older ones, so
installing them first — by any route below — is all it takes to opt out in
practice. To rule it out for good, `thinklight config bootstrap off`, or
`THINKLIGHT_NO_BOOTSTRAP=1` in the environment your agent starts in if nothing is
installed yet.

**Prebuilt, in one line.** The same download the plugin would have done:

```bash
curl -fsSL https://raw.githubusercontent.com/lichengzhe/thinklight/main/get.sh | bash
```

**Build from source.** With the Xcode Command Line Tools (`swiftc`) installed,
this also enables `thinklight update` and its update notifications, which the
prebuilt path does not have. The plugin recognises a source install and keeps its
hands off it:

```bash
git clone https://github.com/lichengzhe/thinklight.git
cd thinklight
./install.sh
```

**Programs by hand.** Download the tarball from Releases, clear the download
quarantine with `xattr -d com.apple.quarantine`, and put the three programs in
`~/.local/bin`.

### Hooks without the plugin

Skipping the plugin costs you the `/thinklight:*` commands, automatic hook
updates, and the automatic program install above — the programs are then yours to
install and update. The hooks themselves are four lines in
`~/.claude/settings.json`:

```json
"hooks": {
  "UserPromptSubmit": [
    { "hooks": [{ "type": "command", "command": "$HOME/.local/bin/thinklight on", "timeout": 10 }] }
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

However they are installed, the light turns on when you submit a message
(`UserPromptSubmit`) and turns off when the turn ends normally (`Stop`), an API
request fails (`StopFailure`), or the session ends (`SessionEnd`). If a session
exits or crashes, the daemon clears its state within a second. A pending
permission prompt counts as running, so the light stays on.

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
thinklight version          print the installed programs' version
thinklight config           print every setting: sound, tracks, bootstrap, update check
thinklight config KEY VALUE change one setting: sound, bootstrap, or update-check, on or off
thinklight unmute           turn sound on (installs the default tracks on first use)
thinklight mute             turn sound off, keeping the tracks in place
thinklight update --check   check for a new version
thinklight update           update ThinkLight
```

ThinkLight checks for a new version in the background at most once every 24
hours and sends a macOS notification when one is available. The check contacts
this repository over `git ls-remote`; installing an update requires running
`thinklight update`. No usage data is collected or transmitted. Turn the check off
with `thinklight config update-check off` — `thinklight update --check` keeps
working afterwards, since a check you asked for is not a background one.

The plugin closes the other gap by itself. It updates while the programs in
`~/.local/bin` do not, so the two could drift into a combination nobody chose:
new hooks calling an old CLI. At session start it compares the two versions and,
when they differ, downloads and installs the programs for its own version, then
notifies you. It tries once per plugin version, says what it did, and steps aside
in the two cases where the decision is not its to make: a source install keeps
`thinklight update` in charge, and `thinklight config bootstrap off` reduces it to
reporting the gap the way it used to.

## Sound (optional, off by default)

The LED only reports where you can see it. When you hand off a task and leave
the screen, sound covers that gap.

```bash
thinklight unmute      # a track loops while the agent works, a chime marks your turn
thinklight mute        # silent again; the LED keeps working
thinklight config      # which of the two is in effect, and which tracks are installed
```

Inside Claude Code the plugin offers the same three as `/thinklight:unmute`,
`/thinklight:mute`, and `/thinklight:config`. The switch takes effect within a
second, so `/thinklight:unmute` is audible in the very turn that runs it.

The first `unmute` copies the two default tracks into
`~/.local/share/thinklight/`: `loop` repeats while the agent works, `done` plays
once when it finishes. To use your own, replace either file — any format macOS
can decode works (FLAC, MP3, WAV, AAC, …) and the extension does not have to
match; only the names `loop` and `done` matter. Run `thinklight mute && thinklight
unmute` to pick up a replacement. A later `unmute` never overwrites a track you
chose, and deleting one is how you get the bundled default back — installing or
updating ThinkLight touches neither those files nor the switch. (Set
`THINKLIGHT_SHARE_DIR` to keep them somewhere else.)

Volume follows system volume; ThinkLight does not adjust it separately. Starting
a new turn cuts off a completion chime that is still playing — "your turn" goes
stale the instant the next turn begins. `thinklight blink` runs through the same
on/off path, so once sound is on that diagnostic plays too.

## Privacy, resources, and compatibility

- **Camera frames:** ThinkLight needs camera permission to activate the hardware
  LED. It discards every captured frame in the callback, without image
  processing or disk storage.
- **Network:** Two things reach out, both to this repository. The plugin's
  session-start hook downloads and installs the programs for its own version when
  `~/.local/bin` does not have them — once per plugin version, with a
  notification saying so, and switchable off with `thinklight config bootstrap
  off`. The installed CLI then checks for a newer version at most once a day and
  only notifies. Neither carries anything about you or your prompts.
- **Resource use:** Capture uses the low-resolution preset, with no encoding or
  video storage. The daemon waits for the next session while idle, but camera
  capture is fully stopped.
- **Sound:** Tracks play entirely locally, with no network access; while sound is
  on each track is opened and buffered for playback rather than decoded into
  memory whole. While muted — the default — the daemon performs no audio setup
  at all.
- **Video calls:** macOS allows multiple processes to share a camera, and
  ThinkLight has been tested alongside Zoom and Tencent Meeting. While another
  app is using the camera, however, the LED remains on, so it cannot reflect
  ThinkLight's state on its own.
- **Camera selection:** ThinkLight uses the Mac's built-in camera, and when a
  Studio Display is connected its camera LED lights in sync — one 🟢 per
  display (docking is re-checked once a second while the light is on, so a
  display plugged in mid-run joins about a second later). Continuity
  Camera and other external webcams are left alone.
- **Indicator attribution:** The daemon is launched through launchd, so macOS
  attributes the camera use to `thinklight-daemon` itself. Only the small green
  dot on the Control Center icon appears — no extra green camera pill in the
  menu bar.
- **Unexpected exits and interrupts:** ThinkLight checks each session's owner
  process once per second and removes state for processes that have exited.
  Because a Codex Ctrl+C interrupt does not run the `Stop` hook, the daemon also
  detects that turn's terminal event in the local transcript and clears its
  state. Claude Code currently has no hook for an Esc interrupt, so the LED may
  remain on temporarily; it turns off when the next turn ends, or you can run
  `thinklight off`.

## How it works

The ThinkLight Swift daemon starts an `AVCaptureSession` on each status camera
(the built-in one, plus a Studio Display's while docked).
macOS turns on the hardware-linked green indicator while the camera is actually
capturing and turns it off when capture stops. Once a second the daemon checks
the sessions registered by each agent: while any is still running it keeps
capturing (light on); when none remain it stops capture and waits for the next
session (light off). Codex tokens also carry transcript and turn metadata so
the daemon can recognize a Ctrl+C-interrupted turn that never ran `Stop`.
Keeping the idle daemon resident avoids losing a new start signal while an old
process is exiting.

Sound hangs off that same state transition, so it needs no second state machine:
the daemon holds two `AVAudioPlayer`s — the loop (`numberOfLoops = -1`, seamless
repeat) and the chime — starting the loop on dark → lit, and on lit → dark
stopping it and playing the chime once. The same tick re-reads the switch
`unmute` writes, so the setting lands within a second; the players are built on
that switch rather than on the light's own transition, since decoding at a turn
boundary would push the cue past the moment it exists to mark. Muted, the daemon
touches no audio API at all, and a missing track costs one stderr line rather
than the run — the light should not stop working just because there is no sound.

## License

MIT
