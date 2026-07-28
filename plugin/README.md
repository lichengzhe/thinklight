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

**A fifth hook that installs the programs.** `SessionStart` runs
`scripts/version-check.sh`, which compares this plugin's version against the
version recorded in `~/.local/state/thinklight/version`. When they match — the
usual case — it reads two files and stops. When the programs are missing or older
than this plugin, it hands off to `scripts/install-programs.sh` in the background:
that downloads `get.sh` and the release tarball for this plugin's exact version
from this repository's GitHub Releases, installs `thinklight`,
`thinklight-daemon`, and `thinklight-check` into `~/.local/bin`, and posts one
macOS notification saying what it did. It tries once per plugin version, and
never touches an install that came from a source checkout — there
`thinklight update` stays in charge and you get the old notification instead.

Turn it off with `thinklight config bootstrap off`, or `THINKLIGHT_NO_BOOTSTRAP=1`
before anything is installed; then install the programs yourself with the line
below.

## Commands, yours only

`/thinklight:unmute`, `/thinklight:mute`, and `/thinklight:config` control the
optional sound; `/thinklight:theme-current` reports which sound theme is
installed. Sound is off until you turn it on. All four are marked
`disable-model-invocation`, so Claude cannot trigger them on its own.

Installing or resetting a sound theme — a shared `loop`/`done` pair with a name
and a license attached — is CLI-only: `thinklight theme install
<package.zip|dir>` and `thinklight theme reset`. Installing takes a file path
to the package, which does not fit a slash command; `theme current`, the one
part of that worth a shortcut, is the skill above.

## Installing the programs yourself

Nothing about the automatic install is required. Run this before or after adding
the plugin and the `SessionStart` hook will find its work already done:

```bash
curl -fsSL https://raw.githubusercontent.com/lichengzhe/thinklight/main/get.sh | bash
```

## Network

Two things reach the network, both from this repository and neither carrying
anything about you. The `SessionStart` hook downloads the release described above,
once per plugin version, and only while the programs are missing or behind. The
installed CLI then checks for a newer version at most once every 24 hours via
`git ls-remote` and notifies you; it downloads nothing on its own, and
`thinklight config update-check off` stops it. The four busy-light hooks never
make a network call. No usage data is collected or transmitted.

## License

MIT. See `assets/CREDITS.md` in the repository for the provenance of the
optional default audio tracks, which are not covered by that license.
