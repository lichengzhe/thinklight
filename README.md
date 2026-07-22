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

ThinkLight 把 Mac 内建摄像头和 Studio Display 摄像头当作两个状态灯槽位：第一条
活跃 session 使用内建灯，第二条使用 Studio Display 灯，更多 session 分配给当前
负载较少的一侧。每一路只在分配给它的最后一条 session 结束时熄灭。没有 Studio
Display 时，所有 session 自动共用内建灯。

## 安装

需要 macOS + Xcode Command Line Tools（`swiftc`）。

```bash
git clone https://github.com/lichengzhe/thinklight.git
cd thinklight
./install.sh                    # 编译安装到 ~/.local/bin
~/.local/bin/thinklight blink 3 # 首次运行会弹摄像头授权框并亮灯 3 秒
```

ThinkLight 每 24 小时在后台检查一次 `main`，有新版时发送 macOS 通知（不会
自动安装）。运行 `thinklight update --check` 可手动检查，`thinklight update`
会在源码目录干净且位于 `main` 时执行 fast-forward 更新、重新编译，并保持现有
session 状态。也可以继续手动运行 `git pull && ./install.sh`。

## 用法

```
thinklight on              注册当前会话并分配一盏状态灯
thinklight off [--force]   注销当前会话；该灯的最后一个会话离开时才熄灭
                           （--force 或人在终端里直接敲 off：清空全部
                           会话、立即熄灯）
thinklight status          on | off
thinklight blink [秒]      亮、等待、灭
thinklight check           经 CoreMediaIO 读硬件层真实状态
thinklight update --check  检查是否有新版
thinklight update          安全更新源码并重新安装
```

## Claude Code

`~/.claude/settings.json` 增加（与现有配置合并）：

```json
"hooks": {
  "UserPromptSubmit": [
    { "hooks": [{ "type": "command", "command": "$HOME/.local/bin/thinklight on", "timeout": 10, "async": true }] }
  ],
  "PostToolUse": [
    { "hooks": [{ "type": "command", "command": "$HOME/.local/bin/thinklight on", "timeout": 10, "async": true }] }
  ],
  "Notification": [
    { "matcher": "permission_prompt", "hooks": [{ "type": "command", "command": "$HOME/.local/bin/thinklight off", "timeout": 10, "async": true }] }
  ],
  "Stop": [
    { "hooks": [{ "type": "command", "command": "$HOME/.local/bin/thinklight off", "timeout": 10, "async": true }] }
  ],
  "StopFailure": [
    { "hooks": [{ "type": "command", "command": "$HOME/.local/bin/thinklight off", "timeout": 10, "async": true }] }
  ],
  "SessionEnd": [
    { "hooks": [{ "type": "command", "command": "$HOME/.local/bin/thinklight off", "timeout": 10 }] }
  ]
}
```

灯的语义因此很严格:**亮 = agent 在干活,不用管它;灭 = 需要你**——跑完了
(`Stop`)、API 出错断了(`StopFailure`),或者正停在权限确认框等你批准
(`Notification`)。批准之后,下一个工具执行完成(`PostToolUse`)灯会重新亮起。

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

`thinklight-daemon` 可为 Mac 内建摄像头或 Apple Studio Display 摄像头分别打开
独立的 `AVCaptureSession`，各挂一个把每一帧都直接丢弃的
`AVCaptureVideoDataOutput`——会话要有输出才会真正启动采集、点亮 LED。
其他外置摄像头和 iPhone 连续互通相机会被排除。
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

**按 Esc 打断后灯还亮着？** Claude Code 目前没有任何 hook 事件在用户打断时
触发,灯要等这个会话下一轮回合结束或会话退出才熄灭;着急可以手动
`thinklight off`。

**多个 agent / 多个会话？** 完整支持。每个会话在 prompt 提交和每次工具执行
完成时到 `~/.local/state/thinklight` 注册/刷新 token,回合结束、API 出错或
等待权限确认时注销。有 Studio Display
时，第一条活跃 session 分到内建灯，第二条分到 Studio Display 灯，后续按两边
当前 session 数量较少的一侧分配（相同时优先内建灯）。每盏灯独立计数，分配给
它的最后一条 session 结束时才熄灭；没有或断开 Studio Display 时则全部自动
并回内建灯。
每次调用都会用存活进程核对 token，会话崩溃不可能把灯锁在常亮；人在终端
里敲 `thinklight off` 永远立即生效。

**提交到亮灯约 2 秒延迟**是摄像头上电时间，正常。

## Roadmap

ThinkLight 的核心抽象是「agent 状态 → 物理灯」。内建摄像头和 Studio Display
摄像头 LED 是第一个 backend，计划/可能的后续 backend：

- **键盘背光** —— 用 MacBook 键盘背光（CoreBrightness）做更含蓄的指示，
  脉冲或开关
- **其他外置摄像头灯** —— 将同样的采集会话技巧用于第三方 UVC 摄像头，
  并支持按使用场景选择 backend
- **屏幕指示** —— 亮度脉冲或屏幕边缘光晕，覆盖完全没有可控 LED 的设备
- **多状态信号** —— "等待授权即熄灯"已内置（`Notification` hook）；
  未来可为不同状态加入闪烁等模式
- **Windows 支持** —— 多数笔记本摄像头灯同样与采集硬件联动，
  同一招式可经 Media Foundation 移植；各厂商键盘背光 SDK 可作更多 backend

欢迎贡献。

## 免责声明

ThinkLight 是独立开源项目，与联想（我们深情怀念的同名 ThinkPad 键盘灯）
及苹果均无关联。

## License

MIT
