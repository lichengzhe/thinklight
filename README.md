# ThinkLight 🟢

**MacBook 屏幕上面的🟢，变成 AI 工作状态灯。不占屏幕空间，切应用、开全屏，
随时知道 AI 干完了。**

ThinkLight 用 Mac 内建摄像头旁的绿灯显示 Claude Code 和 Codex CLI 的状态：

| 灯光 | 含义 |
| --- | --- |
| 常亮 | AI 正在干活——放心去做别的 |
| 熄灭 | 干完了——轮到你 |

[English](README.en.md)

> **最快安装：** [复制一段指令，让 Claude Code 或 Codex 自动完成安装和配置。](#让-ai-帮你安装推荐)

## 有什么用

和 agent 协作像接力：你派出任务，棒就在 AI 手里；它跑完，棒交还给你。但任务一跑
几分钟，你切去做别的事之后，想知道棒是否回到了自己手里，只能反复切回终端看。

ThinkLight 把这个信号放进余光：灯亮着，AI 还在忙，你继续专注手头的事；灯灭了，
轮到你——验收结果、给反馈、派下一个任务。不弹窗、无声音，也不像桌宠或状态挂件
要占一块屏幕——灯在屏幕之外，不占一个像素，切换桌面或进入全屏后依然可见。

它尤其适合：

- 经常派耗时任务给 Claude Code 或 Codex；
- 同时开着多个 agent 会话；
- 想保持专注，又不想错过接手的时机。

多个会话并存时，只要还有一个在跑，灯就保持常亮；全部干完后熄灭。

## 安装

### 让 AI 帮你安装（推荐）

把下面这段直接发给**正在这台 Mac 上运行、能够操作终端**的 Claude Code、Codex
或其他 coding agent：

```text
请帮我在这台 Mac 上安装并配置 ThinkLight：https://github.com/lichengzhe/thinklight。
先阅读仓库中的 README.md 和 install.sh，确认安装范围；然后克隆或更新仓库，运行
install.sh，为这台 Mac 上已有的 Claude Code 和/或 Codex CLI 配置 ThinkLight hooks，
并运行 ~/.local/bin/thinklight blink 3 和 ~/.local/bin/thinklight check 验证。
需要我授予 macOS 摄像头权限或确认 hook 信任时，停下来明确告诉我该点哪里。
完成后汇报安装位置、hook 配置和验证结果；不要改动无关设置。
```

AI 可以完成下载、编译和 hook 配置；macOS 摄像头授权与 Codex hook 信任仍需要你亲自确认。

### 手动安装

需要一台带内建摄像头的 Mac，以及 Xcode Command Line Tools（`swiftc`）。

先安装 ThinkLight：

```bash
git clone https://github.com/lichengzhe/thinklight.git
cd thinklight
./install.sh
```

程序会编译并安装到 `~/.local/bin`。首次运行下面的测试命令时，macOS 会请求
摄像头权限；授权后绿灯会亮 3 秒：

```bash
~/.local/bin/thinklight blink 3
```

随后为你使用的 agent 配置 hooks。配置完成后，状态会随会话自动更新，日常不需要
手动运行 `thinklight on` 或 `thinklight off`。

### Claude Code

本仓库同时提供 Claude Code plugin marketplace：

```text
/plugin marketplace add lichengzhe/thinklight
/plugin install thinklight@thinklight
```

如果不使用插件，也可以把以下 hooks 合并到 `~/.claude/settings.json`：

```json
"hooks": {
  "UserPromptSubmit": [
    { "hooks": [{ "type": "command", "command": "$HOME/.local/bin/thinklight on", "timeout": 10 }] }
  ],
  "Stop": [
    { "hooks": [{ "type": "command", "command": "$HOME/.local/bin/thinklight off", "timeout": 10 }] }
  ],
  "StopFailure": [
    { "hooks": [{ "type": "command", "command": "$HOME/.local/bin/thinklight off", "timeout": 10 }] }
  ]
}
```

你提交消息（`UserPromptSubmit`）时灯亮起，回合正常结束（`Stop`）或 API 请求失败
（`StopFailure`）时熄灭。会话退出或崩溃后，daemon 会在一秒内清理它的状态。
权限确认框弹出期间算作「在跑」，灯保持亮起。

### Codex CLI

Codex CLI 0.145 及以上版本可以通过插件配置相同的 hooks：

```bash
codex plugin marketplace add https://github.com/lichengzhe/thinklight.git
codex plugin add thinklight@thinklight
codex   # 在交互会话中确认 hook 信任提示
```

## 命令行

安装 hooks 后通常不需要手动调用这些命令，但它们可用于测试、排查或接入其他工具：

```text
thinklight on               将当前会话标记为运行中
thinklight off [--force]    注销当前会话
                            在终端直接运行或加 --force：清空状态并立即灭灯
thinklight status           输出 on 或 off
thinklight blink [秒]       亮起指定时间后熄灭
thinklight check            读取 CoreMediaIO 报告的摄像头硬件状态
thinklight update --check   检查是否有新版
thinklight update           更新 ThinkLight
```

ThinkLight 每 24 小时最多在后台检查一次新版，有更新时发送 macOS 通知。检查过程会
访问本仓库，安装更新需要手动运行 `thinklight update`。

## 隐私、资源与兼容性

- **摄像头画面**：ThinkLight 需要摄像头权限来点亮硬件 LED。采集到的帧会在回调中
  直接丢弃，不做图像处理，也不写入磁盘。
- **资源占用**：采集使用低分辨率 preset，不编码、不保存视频。空闲时 daemon
  继续等待下一次会话，但摄像头采集完全停止。
- **视频会议**：macOS 支持多个进程共享摄像头，ThinkLight 已测试可与 Zoom、
  腾讯会议同时运行。但其他应用正在使用摄像头时，绿灯会持续亮起，此时灯光无法
  反映 ThinkLight 的状态。
- **摄像头选择**：使用 Mac 内建摄像头；接有 Studio Display 时，它的摄像头灯也会
  同步亮灭，每台显示器一个 🟢（每次点亮时重新检测插拔）。连续互通相机和其他
  外接摄像头不受影响。
- **指示灯归属**：daemon 通过 launchd 启动，macOS 会把摄像头使用记在
  `thinklight-daemon` 自己名下。菜单栏只有控制中心图标上的小绿点，不会额外出现
  绿色摄像头胶囊图标。
- **异常退出**：ThinkLight 每秒检查一次会话所属进程，并清理已经退出的会话状态。
  Claude Code 的 Esc 中断目前没有对应 hook，因此中断后灯可能暂时保持亮起；等下
  一个回合结束时会熄灭，也可以运行 `thinklight off`。

## 原理

ThinkLight 的 Swift daemon 在每个状态摄像头（内建摄像头，接有 Studio Display 时
加上它的摄像头）上各启动一个 `AVCaptureSession`。摄像头实际采集时，macOS 会点亮
与硬件联动的绿色指示灯；停止采集时指示灯熄灭。daemon 每秒
核对各个 agent 会话的状态：只要还有会话在运行就保持采集（灯亮），没有则停止
采集并等待下一次会话（灯灭）。daemon 空闲常驻，避免会话刚开始时撞上旧进程退出
而漏掉启动信号。

## License

MIT
