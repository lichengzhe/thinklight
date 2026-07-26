---
name: config
description: Show ThinkLight's current configuration — whether sound is on, and which tracks are installed
disable-model-invocation: true
---

!`~/.local/bin/thinklight config 2>&1 || echo "thinklight: CLI not found at ~/.local/bin/thinklight — install it from https://github.com/lichengzhe/thinklight"`

Report that configuration to the user, and do not run any commands of your own.
Nothing was changed. `/thinklight:unmute` and `/thinklight:mute` are what change it.
