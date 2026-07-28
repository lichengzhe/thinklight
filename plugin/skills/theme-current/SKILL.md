---
name: theme-current
description: Show the sound theme ThinkLight currently has installed — its name, author, license, and source
disable-model-invocation: true
---

!`~/.local/bin/thinklight theme current 2>&1 || echo "thinklight: CLI not found at ~/.local/bin/thinklight — install it from https://github.com/lichengzhe/thinklight"`

Report that to the user, and do not run any commands of your own.
Nothing was changed. `thinklight theme install` and `thinklight theme reset` are what change it.
