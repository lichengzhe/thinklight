---
name: unmute
description: Turn on ThinkLight's sound cues — a track loops while the agent works, a chime plays once when it is your turn
disable-model-invocation: true
---

The switch has already been flipped by the command below; its output is the
resulting configuration.

!`~/.local/bin/thinklight unmute 2>&1 || echo "thinklight: CLI not found at ~/.local/bin/thinklight — install it from https://github.com/lichengzhe/thinklight"`

Report that result to the user in one line, and do not run any commands of your
own. If a track is reported missing, say where to put it.

The daemon re-reads the switch every second, so this turn is already audible:
the loop started when the command ran, and the chime plays when this turn ends.
Mention that only if a track was actually found.
