# ThinkLight 🟢

**不用切回终端，也能知道 AI agent 是否需要你。**

ThinkLight 把 Mac 内建摄像头旁的绿灯变成 Claude Code 和 Codex CLI 的状态灯：

| 灯光 | 含义 |
| --- | --- |
| 常亮 | 有 agent 正在运行 |
| 熄灭 | 没有 agent 在运行——跑完了，或在等你操作 |

[English](README.en.md)

## 适合什么场景

当 agent 的任务需要运行几分钟，你通常会切到编辑器、浏览器或别的工作区继续做事。
这时，ThinkLight 可以让你从余光里看到进度，不需要反复切回终端，也不会增加弹窗、
声音或新的窗口。状态显示在屏幕之外，因此切换桌面或进入全屏后依然可见。

它尤其适合：

- 经常让 Claude Code 或 Codex 执行耗时任务；
- 同时打开多个 agent 会话；
- 希望在不打断当前工作的情况下，知道何时需要回来处理。

多个会话并存时，只要还有一个会话在运行，绿灯就保持常亮；全部跑完后熄灭。

## 安装

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
  ]
}
```

你提交消息（`UserPromptSubmit`）时灯亮起，回合结束（`Stop`）时熄灭。会话退出或
崩溃后，daemon 会在一秒内清理它的状态。权限确认框弹出期间算作「在跑」，灯保持亮起。

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
- **资源占用**：采集使用低分辨率 preset，不编码、不保存视频。
- **视频会议**：macOS 支持多个进程共享摄像头，ThinkLight 已测试可与 Zoom、
  腾讯会议同时运行。但其他应用正在使用摄像头时，绿灯会持续亮起，此时灯光无法
  反映 ThinkLight 的状态。
- **摄像头选择**：只使用 Mac 内建摄像头，不使用 Studio Display、连续互通相机或
  其他外接摄像头。
- **异常退出**：ThinkLight 每秒检查一次会话所属进程，并清理已经退出的会话状态。
  Claude Code 的 Esc 中断目前没有对应 hook，因此中断后灯可能暂时保持亮起；等下
  一个回合结束时会熄灭，也可以运行 `thinklight off`。

## 原理

ThinkLight 的 Swift daemon 在内建摄像头上启动一个 `AVCaptureSession`。摄像头实际
采集时，macOS 会点亮与硬件联动的绿色指示灯；停止采集时指示灯熄灭。daemon 每秒
核对各个 agent 会话的状态：只要还有会话在运行就保持采集（灯亮），没有则停止
采集并退出（灯灭）。

## License

MIT
