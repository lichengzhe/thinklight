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
- run agents over ssh, on a build box or another Mac;
- want to stay focused without missing the handoff.

With multiple sessions, the light stays on while any of them is still working,
and goes out once they have all finished. Sessions
[on a machine you ssh into](#agents-on-another-machine) count among them.

## Install

You need a Mac with a built-in camera, running macOS 14 or later. The machine
running the agent does not have to be that Mac.

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

Paste this into Claude Code, Codex, or another coding agent that **can use the
terminal of the machine you want set up** — the Mac with the light, or a server
you ssh into:

```text
Please install and configure ThinkLight here: https://github.com/lichengzhe/thinklight.
First read README.md, get.sh, and plugin/scripts/install-programs.sh to confirm the installation
scope. Prefer the plugin: run `claude plugin marketplace add lichengzhe/thinklight` and
`claude plugin install thinklight@thinklight` for Claude Code, and the codex plugin equivalents for
Codex CLI, falling back to hooks in ~/.claude/settings.json only if the plugin route fails. The
plugin installs the programs itself at session start; if they are not in ~/.local/bin yet, run
get.sh (or clone the repository and run install.sh to build from source). Verify with
~/.local/bin/thinklight blink 3 and ~/.local/bin/thinklight check. Stop and tell me exactly what to
click when macOS asks for camera access or Codex asks me to trust the hooks.
If this machine is not a Mac, or you are working inside an ssh session, the light is on the Mac I
connect from: the same plugin install is all this machine needs, and what verifies it here is
~/.local/bin/thinklight tunnel status rather than blink and check. If that reports no tunnel, tell
me to run `thinklight tunnel setup` on the Mac and reconnect — it edits ~/.ssh/config there, so do
not attempt it yourself from here. When finished, report the install location, hook configuration,
and verification results. Do not change unrelated settings.
```

You still need to personally approve macOS camera access and Codex hook trust,
and `thinklight tunnel setup` stays yours to run: it writes to your
`~/.ssh/config`, which is not an agent's call to make.

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

**Build from source.** Needs the Xcode Command Line Tools (`swiftc`). A source
install tracks `main` rather than published releases, and `thinklight update`
follows it there; the plugin recognises one and keeps its hands off it:

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
thinklight theme install P  install a sound theme from a zip or a directory (see below)
thinklight theme current    print the installed theme's name, author, license, and source
thinklight theme reset      restore the bundled default tracks, replacing any you placed by hand
thinklight tunnel setup [H] carry this Mac's light into ssh sessions, to every host or only the named ones
thinklight tunnel status    say which light a session on this machine would turn on
thinklight update --check   check for a new version
thinklight update           update ThinkLight
```

ThinkLight checks for a new version in the background at most once every 24
hours and sends a macOS notification when one is available. Both the check and
`thinklight update` follow the install they are asked about: a prebuilt install
compares its version against the latest published release and updates by running
`get.sh` again, a source install compares its revision against `main` over
`git ls-remote` and updates with `git pull` and `install.sh`. Either way,
installing the update is a command you run. No usage data is collected or
transmitted. Turn the check off with `thinklight config update-check off` —
`thinklight update --check` keeps working afterwards, since a check you asked for
is not a background one.

The plugin closes the other gap by itself. It updates while the programs in
`~/.local/bin` do not, so the two could drift into a combination nobody chose:
new hooks calling an old CLI. At session start it compares the two versions and,
when the programs are missing or older, downloads and installs the programs for
its own version, then notifies you. Newer programs are left alone so Claude and
Codex cannot downgrade a shared install while their plugin updates arrive at
different times. It tries once per plugin version, says what it did, and steps
aside in the two cases where the decision is not its to make: a source install
keeps `thinklight update` in charge, and `thinklight config bootstrap off`
reduces it to reporting the gap the way it used to.

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

Replacing one file at a time is fine for your own tracks; a **sound theme** is
for sharing both at once with a name and a license attached. It is a zip or a
directory containing `loop.<ext>` and `done.<ext>` plus an optional
`theme.json` with `name`, `title`, `author`, `license`, and `source`.
`thinklight theme install lofi-rain.zip` checks that both tracks are present
and in a format macOS can decode before it touches anything under
`~/.local/share/thinklight/`, so a bad package changes nothing; a good one
replaces whatever was there — old tracks in a different format do not linger
behind the new ones — and reloads sound if it was already on, so the theme is
audible in the same turn that installed it. `thinklight theme current` prints
the installed theme's metadata. A `theme.json` that is missing or fails to
parse does not block the install — the tracks are what matter, and
`theme current` just reports the name as unknown.

`thinklight theme reset` always restores the bundled default tracks, even over
ones you swapped in by hand — that is what "reset" means, and running it is
how you ask for the built-in loop and chime back.

Volume follows system volume; ThinkLight does not adjust it separately. Starting
a new turn cuts off a completion chime that is still playing — "your turn" goes
stale the instant the next turn begins. `thinklight blink` runs through the same
on/off path, so once sound is on that diagnostic plays too.

## Agents on another machine

The light is on your Mac. The agent frequently is not: you ssh into a build box,
or into another Mac, and run Claude Code there. Its hooks run there too, where
there is no LED anybody is looking at.

ThinkLight sends those turns back down the ssh connection you already have open.
On the Mac with the light, once:

```bash
thinklight tunnel setup              # any host you ssh into
thinklight tunnel setup build gpu    # or only these
```

Name the hosts the way you type them — `ssh build` is matched on `build`, not on
whatever `HostName` it resolves to. That adds a block to `~/.ssh/config`
publishing the daemon's socket as a loopback port on whatever you connect to. On that machine, install the plugin exactly the
way you installed it here — it works out that there is no camera to serve and
installs nothing that needs one, no daemon and no binaries, just the CLI.

There is nothing further to configure, and nothing to declare about which machine
is which. Every session asks one question and gets it right on its own:

> **Is there a tunnel? Then the light is at the other end of it. Otherwise it is
> the one on this machine.**

| Where you are sitting | Where the agent runs | Which light comes on |
| --- | --- | --- |
| At your Mac | On that same Mac | That Mac's — unchanged, no tunnel involved |
| At your Mac | On a Linux server, over ssh | Your Mac's |
| At your Mac | On another Mac, over ssh | **Yours**, not the one nobody is watching |

`thinklight tunnel status`, run on either machine, answers the question out loud.

The light goes out the moment the connection ends — a dropped ssh, a closed lid,
a killed agent. No pid from over there means anything here, so the connection
itself is what the daemon holds onto, and losing it is the signal rather than a
timeout somebody had to guess at.

### What this costs the machine running the agent

Nothing is compiled, nothing is granted, nothing runs in the background, and
nothing needs root. It has no daemon, no camera, and no sound: the CLI opens a
loopback port, writes one line, and holds it for the turn.

While your ssh session is up, that port exists on the far side and belongs to
your own sshd process. Anyone else logged into that machine could connect to it —
all they could do is turn your light on or off, but on a shared host it is worth
knowing.

### The edges

- **VS Code Remote, Cursor, JetBrains** all read `~/.ssh/config`, so they carry
  the light too. **mosh does not**: it has no port forwarding at all.
- **tmux.** If you detach and let the ssh session close, the light goes out even
  though the agent is still working — the tunnel went with your session. That is
  the intended reading (you are not there), but it can surprise.
- **Several ssh sessions to one host.** The second one finds the port taken,
  prints one warning, and shares the first one's tunnel. Only when two *different*
  Macs connect to the same server does this matter: every session's light lands on
  whichever Mac connected first.
- **You, at a Mac somebody is also ssh'd into.** A local turn on that Mac follows
  the same rule and reports up the tunnel. Rare, and "there is a person watching
  at the other end" is a fair reading of it, but it is the price of the rule.
- **Two hops.** A → B → C carries no light to A yet; the middle machine would
  have to relay, and it does not.

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
- **Sessions from another machine:** the tunnel carries a session id, a turn id,
  and the name of the machine — no prompt content, no responses, no file paths.
  It is not a network service either: ssh binds the far end to `127.0.0.1` for the
  life of your session, and this Mac's end is a Unix socket in your own state
  directory, readable and writable by nobody but you.
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

A session on another machine cannot write into that state directory, so it speaks
to the daemon over a Unix socket instead, which `thinklight tunnel setup` hands to
ssh as a `RemoteForward`. The hook on the far side finds the forwarded port,
checks that what answers is really the daemon, and holds the connection open for
the rest of the turn. That connection is the session: the daemon's token lives
exactly as long as it does, which is why a dropped ssh puts the light out with
nothing to detect and nothing to wait for. The far side needs no daemon of its
own, and a machine with no tunnel never notices any of this — it takes the same
path it always did.

Sound hangs off that same state transition, so it needs no second state machine:
the daemon holds two `AVAudioPlayer`s — the loop (`numberOfLoops = -1`, seamless
repeat) and the chime — starting the loop on dark → lit, and on lit → dark
stopping it and playing the chime once. The same tick re-reads the switch
`unmute` writes, so the setting lands within a second; the players are built on
that switch rather than on the light's own transition, since decoding at a turn
boundary would push the cue past the moment it exists to mark. Muted, the daemon
touches no audio API at all, and a missing track costs one stderr line rather
than the run — the light should not stop working just because there is no sound.

## Contact

Bugs and feature requests are best filed as
[issues](https://github.com/lichengzhe/thinklight/issues). For anything else,
scan to add me on WeChat:

<img src="docs/wechat-qr.png" alt="WeChat QR code" width="140">

## License

MIT
