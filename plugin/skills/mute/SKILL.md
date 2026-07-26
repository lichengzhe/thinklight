---
name: mute
description: Silence ThinkLight's sound cues and leave the camera LED working as usual
disable-model-invocation: true
---

Sound has already been switched off by the command below; its output is the
resulting configuration. The track files are left in place, so `/thinklight:unmute`
brings back the same ones.

!`~/.local/bin/thinklight mute 2>&1 || echo "thinklight: CLI not found at ~/.local/bin/thinklight — install it from https://github.com/lichengzhe/thinklight"`

Report that result to the user in one line, and do not run any commands of your
own. The LED is unaffected and keeps reporting the same states.
