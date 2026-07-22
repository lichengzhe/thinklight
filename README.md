# ThinkLight 🟢

**一盏静默、不打扰的 AI agent 状态灯——用 Mac 摄像头绿灯实现。**

绿灯亮 → agent（Claude Code、Codex 等）还在跑；灯灭 → 跑完了，轮到你。

[English](README.en.md)

## 为什么？

Agent 一跑就是好几分钟。你切去干别的事，又忍不住反复切回来看它跑完没有。
ThinkLight 把这个答案放进你的余光里：没有通知弹窗、没有提示音、不用留着
窗口盯终端。抬眼一瞥——灯亮着，继续干自己的事；灯灭了，跑完了。

摄像头 LED 恰好是这件事的完美载体：它与视线平齐、隔着房间都能看见，
且与摄像头供电硬件联动——macOS 不提供单独控制它的 API，摄像头真正
采集时必亮，停止必灭。

ThinkLight 打开一个最小化的内建摄像头采集会话（最低分辨率、丢弃所有帧、
不落盘）来点灯，杀掉会话熄灯，agent 的生命周期 hooks 负责其余部分。

## 安装

需要 macOS + Xcode Command Line Tools（`swiftc`）。

```bash
git clone https://github.com/lichengzhe/thinklight.git
cd thinklight
./install.sh                    # 编译安装到 ~/.local/bin
~/.local/bin/thinklight blink 3 # 首次运行会弹摄像头授权框
~/.local/bin/thinklight check   # FaceTime HD Camera 应显示 RUNNING
```

后续升级：`git pull && ./install.sh`。hooks 调用的是安装到 `~/.local/bin`
的副本，插件更新只刷新仓库、不更新已安装的二进制——更新后重跑一次
`install.sh` 即可，无需任何状态迁移。

## 用法

```
thinklight on              注册当前会话并点灯
thinklight off [--force]   注销当前会话；最后一个会话离开时才熄灯
                           （--force 或人在终端里直接敲 off：清空全部
                           会话、立即熄灯）
thinklight status          on | off
thinklight blink [秒]      亮、等待、灭
thinklight pulse [次数]    慢闪 n 下（默认 3），然后保持常亮
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
/plugin marketplace add lichengzhe/thinklight
/plugin install thinklight@thinklight
```

## Codex CLI

Codex（≥ 0.145）hooks 格式与 Claude Code 相同，经插件挂入：

```bash
codex plugin marketplace add https://github.com/lichengzhe/thinklight.git
codex plugin add thinklight@thinklight
codex   # 在交互会话里确认 hook 信任提示
```

注意：`codex exec` 非交互模式不触发 `UserPromptSubmit`，灯只在交互会话里有意义。

## 原理

`thinklight-daemon` 约 60 行 Swift：在内建摄像头（只匹配
`.builtInWideAngleCamera`，绝不会误开 Studio Display 或 iPhone 连续互通
相机）上开一个 `AVCaptureSession`，挂一个把每一帧都直接丢弃的
`AVCaptureVideoDataOutput`——会话要有输出才会真正启动采集、点亮 LED。
`thinklight check` 通过 CoreMediaIO 读
`kCMIODevicePropertyDeviceIsRunningSomewhere`，从硬件层确认灯的真实状态。

## FAQ

**影响视频会议吗？** 不影响。macOS 允许多进程共享摄像头，实测 ThinkLight
占用期间腾讯会议/Zoom 正常入会，任一方退出另一方不受影响。（开会时灯
本来就常亮，指示暂时失去意义。）

**隐私？** 帧在回调里直接丢弃，不读取、不处理、不写盘。菜单栏会显示
标准的绿色"摄像头使用中"指示（归属你的终端 App）——本项目正是建立在
系统这种诚实性之上。

**功耗？** 最低档 preset，无编码无 I/O，可忽略。

**多个 agent / 多个会话？** 完整支持。Claude Code、Codex 的各个会话共用
一盏灯：每个会话在 prompt 开始时到 `~/.local/state/thinklight` 注册一个
token、回合结束时注销，**最后一个**会话结束灯才熄灭。有会话先跑完而其他
还在干活时，灯会慢闪三下再恢复常亮——瞥一眼就知道"有一个完事了"。
每次调用都会用存活进程核对 token，会话崩溃不可能把灯锁在常亮；人在终端
里敲 `thinklight off` 永远立即生效。

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
- **Windows 支持** —— 多数笔记本摄像头灯同样与采集硬件联动，
  同一招式可经 Media Foundation 移植；各厂商键盘背光 SDK 可作更多 backend

欢迎贡献。

## 免责声明

ThinkLight 是独立开源项目，与联想（我们深情怀念的同名 ThinkPad 键盘灯）
及苹果均无关联。

## License

MIT
