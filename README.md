# ThinkLight 🟢

**Mac 摄像头绿灯 = AI agent 状态灯。**

**常亮**：agent 在干活，去忙你的。**闪烁**：有会话在等你。**灭**：全部收工。

[English](README.en.md)

## 为什么

Agent 一跑几分钟，你切走干别的，又忍不住反复切回来看。ThinkLight 把答案放进
余光：不弹窗、无声音、不用盯终端，抬眼一瞥就知道该不该回去。

摄像头 LED 是完美载体：与视线平齐、隔着房间可见、与采集硬件联动——
macOS 不提供伪造它的 API，采集必亮，停止必灭。**灯亮就是真的在跑。**

## 安装

需要 macOS + Xcode Command Line Tools（`swiftc`）。

```bash
git clone https://github.com/lichengzhe/thinklight.git
cd thinklight
./install.sh                    # 编译安装到 ~/.local/bin
~/.local/bin/thinklight blink 3 # 首次运行弹摄像头授权框，亮灯 3 秒
```

有新版时发 macOS 通知（每 24 小时后台检查一次，绝不自动安装），
`thinklight update` 一键更新。

## 用法

```
thinklight on              本会话标记为「干活中」
thinklight off [--force]   回合结束标记「等你」；会话退出注销
                           （终端里直接敲 off / --force：全清、立即灭灯）
thinklight status          on | blink | off
thinklight blink [秒]      亮、等待、灭
thinklight check           经 CoreMediaIO 读硬件层真实状态
thinklight update [--check] 更新 / 检查新版
```

## Claude Code

插件一行装好（本仓库即 plugin marketplace）：

```
/plugin marketplace add lichengzhe/thinklight
/plugin install thinklight@thinklight
```

或手动在 `~/.claude/settings.json` 合并：

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

语义严格：**常亮 = 在干活；闪烁 = 有会话等你**——跑完了（`Stop`）、API 断了
（`StopFailure`）、停在权限框（`Notification`）；**灭 = 一个会话都不剩**。

## Codex CLI

Codex（≥ 0.145）hooks 格式相同，经插件挂入：

```bash
codex plugin marketplace add https://github.com/lichengzhe/thinklight.git
codex plugin add thinklight@thinklight
codex   # 交互会话里确认 hook 信任提示
```

## 原理

一个 Swift daemon 对内建摄像头开一个丢弃所有帧的 `AVCaptureSession`——
会话真正采集时 LED 必亮。daemon 每秒核对各会话 token（宿主进程死掉的
直接清扫），有人等你就亮 2 秒、眨 1 秒地闪，全空则灭灯退出。多会话、
崩溃、断电，灯永远反映真实状态。只用内建摄像头，菜单栏不会出现
外接摄像头的绿色使用中图标。

## FAQ

**影响视频会议吗？** 不影响，macOS 允许多进程共享摄像头，实测 Zoom /
腾讯会议正常。**隐私？** 每一帧在回调里直接丢弃，不读不存。**功耗？**
最低档 preset、无编码无 I/O，可忽略。**Esc 打断后灯还亮？** Claude Code
没有中断事件，等本回合结束即恢复，急可 `thinklight off`。

## License

MIT
