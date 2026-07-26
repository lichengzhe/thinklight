# ThinkLight (Claude Code plugin)

Turns the green LED beside your Mac's camera into a busy light for Claude Code:
lit while the agent works, dark when the turn is yours. macOS 14+ only.

Full documentation: <https://github.com/lichengzhe/thinklight>

## What it needs, and what it does with it

**The camera.** macOS wires that LED to the camera hardware, so the only way to
light it is to hold a capture session open. The daemon opens the built-in camera
(plus a Studio Display's camera while one is docked) at the lowest-resolution
preset and discards every frame inside the callback. No image processing, no
encoding, no disk writes, and capture stops entirely when no session is running.
macOS will ask you to grant camera access the first time.

**Four hooks, on every turn.** `UserPromptSubmit` lights the LED;
`Stop`, `StopFailure`, and `SessionEnd` put it out. They are deliberately
ungated — a busy light that only worked in some projects would not be a busy
light. What each one does is write or delete one file under
`~/.local/state/thinklight/sessions/`, containing the session id, the owning
pid, and (for Codex) the turn id and transcript path. **No prompt or response
content is read**, and no hook makes a network call.

**A fifth hook that only reads.** `SessionStart` runs
`scripts/version-check.sh`, which compares this plugin's version against the
version recorded by whichever installer put the programs in `~/.local/bin`. When
they differ it asks the CLI to post one macOS notification, once per version. It
reads two local files, writes nothing, installs nothing, and makes no network
call.

## Three commands, yours only

`/thinklight:unmute`, `/thinklight:mute`, and `/thinklight:config` control the
optional sound. Sound is off until you turn it on. All three are marked
`disable-model-invocation`, so Claude cannot trigger them on its own.

## The programs are installed separately

This plugin configures hooks and commands; it does not ship the binaries. Install
them first from the repository:

```bash
curl -fsSL https://raw.githubusercontent.com/lichengzhe/thinklight/main/get.sh | bash
```

## Network

The plugin's own hooks never reach the network. The separately installed CLI
checks this repository for a new version at most once every 24 hours via
`git ls-remote`, and sends a macOS notification when one exists; it downloads
nothing on its own. Nothing else contacts the network, and no usage data is
collected or transmitted.

## License

MIT. See `assets/CREDITS.md` in the repository for the provenance of the
optional default audio tracks, which are not covered by that license.
