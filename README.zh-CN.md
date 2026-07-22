# ThinkLight 💡

**把 Mac 摄像头绿灯变成一盏"AI agent 正在干活"的状态灯——而且无法伪造。**

绿灯亮 → agent（Claude Code、Codex 等）正在思考；灯灭 → 轮到你了。

[English](README.md)

## 为什么用摄像头灯？

Mac 摄像头旁的绿色 LED 与摄像头传感器供电硬件联动，macOS 不提供任何
单独控制它的 API——摄像头真正采集时必亮，停止必灭。这个隐私保证反过来
意味着：它是你机器上**唯一无法被软件伪造的指示灯**。不用找菜单栏图标、
不用瞟终端，一盏与视线平齐的物理灯，隔着房间都能看见。

ThinkLight 打开一个最小化的内建摄像头采集会话（最低分辨率、丢弃所有帧、
不落盘）来点灯，杀掉会话熄灯，agent 的生命周期 hooks 负责其余部分。

## 安装

需要 macOS + Xcode Command Line Tools（`swiftc`）。

```bash
git clone https://github.com/leecz/thinklight.git
cd thinklight
./install.sh                    # 编译安装到 ~/.local/bin
~/.local/bin/thinklight blink 3 # 首次运行会弹摄像头授权框
~/.local/bin/thinklight check   # FaceTime HD Camera 应显示 RUNNING
```

## 用法

```
thinklight on              点灯（拉起一个极小的守护进程）
thinklight off             熄灯
thinklight status          on | off
thinklight blink [秒]      亮、等待、灭
thinklight check           经 CoreMediaIO 读硬件层真实状态
```

## Claude Code

`~/.claude/settings.json` 增加（与现有配置合并）：

```json
"hooks": {
  "UserPromptSubmit": [
    { "hooks": [{ "type": "command", "command": "$HOME/.local/bin/thinklight on", "timeout": 10, "async": true }] }
  ],
  "Stop": [
    { "hooks": [{ "type": "command", "command": "$HOME/.local/bin/thinklight off", "timeout": 10, "async": true }] }
  ],
  "SessionEnd": [
    { "hooks": [{ "type": "command", "command": "$HOME/.local/bin/thinklight off", "timeout": 10 }] }
  ]
}
```

也可以走插件（本仓库本身就是一个 plugin marketplace）：

```
/plugin marketplace add leecz/thinklight
/plugin install thinklight@thinklight
```

## Codex CLI

Codex（≥ 0.145）hooks 格式与 Claude Code 相同，经插件挂入：

```bash
codex plugin marketplace add https://github.com/leecz/thinklight.git
codex plugin add thinklight@thinklight
codex   # 在交互会话里确认 hook 信任提示
```

注意：`codex exec` 非交互模式不触发 `UserPromptSubmit`，灯只在交互会话里有意义。

## 原理与踩坑

`thinklight-daemon` 约 60 行 Swift：在内建摄像头（只匹配
`.builtInWideAngleCamera`，绝不会误开 Studio Display 或 iPhone 连续互通
相机）上开一个 `AVCaptureSession`，delegate 丢弃所有帧。

不显然的坑：**只有输入没有输出的会话不会真正启动采集**——
`session.isRunning` 返回 `true` 但摄像头是黑的、灯不亮。必须挂一个
`AVCaptureVideoDataOutput`，哪怕它把每一帧都扔掉。`thinklight check`
通过 CoreMediaIO 读 `kCMIODevicePropertyDeviceIsRunningSomewhere`，
用硬件层状态做断言，不要信 API，也不要只靠肉眼。

## FAQ

**影响视频会议吗？** 不影响。macOS 允许多进程共享摄像头，实测 ThinkLight
占用期间腾讯会议/Zoom 正常入会，任一方退出另一方不受影响。（开会时灯
本来就常亮，指示暂时失去意义。）

**隐私？** 帧在回调里直接丢弃，不读取、不处理、不写盘。菜单栏会显示
标准的绿色"摄像头使用中"指示（归属你的终端 App）——本项目正是建立在
系统这种诚实性之上。

**功耗？** 最低档 preset，无编码无 I/O，可忽略。

**多个 agent 会话？** 共用一盏灯和一个 pidfile，最后停下的会话熄灯。
按会话引用计数是可能的后续改进。

**提交到亮灯约 2 秒延迟**是摄像头上电时间，正常。

## Roadmap

ThinkLight 的核心抽象是「agent 状态 → 一盏物理灯」。内建摄像头 LED
只是第一个 backend，计划/可能的后续 backend：

- **键盘背光** —— 用 MacBook 键盘背光（CoreBrightness）做更含蓄的指示，
  脉冲或开关
- **外置摄像头灯** —— 同样的采集会话技巧用在 UVC 摄像头和 Studio Display
  摄像头上（按使用场景选 backend，比如合盖模式下内建灯不可见）
- **屏幕指示** —— 亮度脉冲或屏幕边缘光晕，覆盖完全没有可控 LED 的设备
- **多状态信号** —— "等待授权"用闪烁（`Notification` hook）、
  "干活中"用常亮
- **按会话引用计数** —— 多个并发 agent 会话时的精确指示

欢迎贡献。

## 免责声明

ThinkLight 是独立开源项目，与联想（我们深情怀念的同名 ThinkPad 键盘灯）
及苹果均无关联。

## License

MIT
