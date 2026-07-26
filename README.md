# ThinkLight 🟢

**MacBook屏幕上面的🟢，变成AI工作状态灯。不占屏幕空间，切应用、开全屏，随时知道AI干完了。**

ThinkLight用Mac内建摄像头旁的绿灯显示Claude Code和Codex CLI的状态，并可选地配上声音：

| 状态 | 灯光 | 声音（默认关闭） |
| --- | --- | --- |
| AI正在干活——放心去做别的 | 常亮 | 循环播放背景音乐 |
| 干完了——轮到你 | 熄灭 | 播放一次完成音 |

[English](README.en.md)

> **最快安装：**[复制一段指令，让Claude Code或Codex自动完成安装和配置。](#让ai帮你安装推荐)

## 有什么用

和AI Agent协作像接力：你派出任务，棒就在AI手里；它跑完，棒交还给你。但任务一跑几分钟，你切去做别的事之后，想知道棒是否回到了自己手里，只能反复切回终端看。

ThinkLight把这个信号放进余光：灯亮着，AI还在忙，你继续专注手头的事；灯灭了，轮到你——验收结果、给反馈、派下一个任务。不弹窗，也不像桌宠或状态挂件要占一块屏幕——灯在屏幕之外，不占一个像素，切换桌面或进入全屏后依然可见。

如果你经常派完任务就离开屏幕，还可以再配上声音：干活时循环播放一段背景音乐，干完时播放一次完成音。声音默认是关的，装好后依然完全静默，直到你运行`thinklight unmute`。

它尤其适合：

- 经常派耗时任务给Claude Code或Codex；
- 同时开着多个AI Agent会话；
- 想保持专注，又不想错过接手的时机。

多个会话并存时，只要还有一个在跑，灯就保持常亮；全部干完后熄灭。

## 安装

需要一台带内建摄像头的Mac，macOS 14或更新。

### 让AI帮你安装（推荐）

把下面这段直接发给**正在这台Mac上运行、能够操作终端**的Claude Code、Codex或其他coding agent：

```text
请帮我在这台 Mac 上安装并配置 ThinkLight：https://github.com/lichengzhe/thinklight。
先阅读仓库中的 README.md 和 get.sh，确认安装范围；然后运行 get.sh 安装预编译版本
（或克隆仓库后运行 install.sh 从源码构建），为这台 Mac 上已有的 Claude Code 和/或
Codex CLI 配置 ThinkLight hooks，并运行 ~/.local/bin/thinklight blink 3 和
~/.local/bin/thinklight check 验证。
需要我授予 macOS 摄像头权限或确认 hook 信任时，停下来明确告诉我该点哪里。
完成后汇报安装位置、hook 配置和验证结果；不要改动无关设置。
```

AI可以完成下载、编译和hook配置；macOS摄像头授权与Codex hook信任仍需要你亲自确认。

### 一键安装

```bash
curl -fsSL https://raw.githubusercontent.com/lichengzhe/thinklight/main/get.sh | bash
```

脚本会从[Releases](https://github.com/lichengzhe/thinklight/releases)下载最新的预编译通用二进制（Apple Silicon与Intel均适用）并安装到`~/.local/bin`。装好后运行测试命令，macOS会请求摄像头权限；授权后绿灯会亮3秒：

```bash
~/.local/bin/thinklight blink 3
```

更新时重新运行同一行安装命令即可（此方式下`thinklight update`和更新通知不可用）。不想执行脚本的话，也可以从Releases手动下载压缩包，解压后用`xattr -d com.apple.quarantine`去掉隔离属性，再把三个程序放进`~/.local/bin`。

### 源码安装

如果装有Xcode Command Line Tools（`swiftc`），也可以从源码构建，这种方式下`thinklight update`和更新通知可用：

```bash
git clone https://github.com/lichengzhe/thinklight.git
cd thinklight
./install.sh
```

程序会编译并安装到`~/.local/bin`，同样运行`thinklight blink 3`授权摄像头并测试。

随后为你使用的AI Agent配置hooks。配置完成后，状态会随会话自动更新，日常不需要手动运行`thinklight on`或`thinklight off`。

### Claude Code

本仓库同时提供Claude Code plugin marketplace：

```text
/plugin marketplace add lichengzhe/thinklight
/plugin install thinklight@thinklight
```

除了hooks，插件还提供三个用于[声音](#声音默认关闭)的命令：`/thinklight:unmute`、`/thinklight:mute`、`/thinklight:config`。这三个只能由你主动触发，Claude不会自己调用。

如果不使用插件，也可以把以下hooks合并到`~/.claude/settings.json`：

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
  ],
  "SessionEnd": [
    { "hooks": [{ "type": "command", "command": "$HOME/.local/bin/thinklight off", "timeout": 3 }] }
  ]
}
```

你提交消息（`UserPromptSubmit`）时灯亮起，回合正常结束（`Stop`）、API请求失败（`StopFailure`）或会话结束（`SessionEnd`）时熄灭。会话退出或崩溃后，daemon会在一秒内清理它的状态。权限确认框弹出期间算作「在跑」，灯保持亮起。

### Codex CLI

Codex CLI 0.145及以上版本可以通过插件配置相同的hooks：

```bash
codex plugin marketplace add https://github.com/lichengzhe/thinklight.git
codex plugin add thinklight@thinklight
codex   # 在交互会话中确认 hook 信任提示
```

## 命令行

安装hooks后通常不需要手动调用这些命令，但它们可用于测试、排查或接入其他工具：

```text
thinklight on               将当前会话标记为运行中
thinklight off [--force]    注销当前会话
                            在终端直接运行或加 --force：清空状态并立即灭灯
thinklight status           输出 on 或 off
thinklight blink [秒]       亮起指定时间后熄灭
thinklight check            读取 CoreMediaIO 报告的摄像头硬件状态
thinklight config           输出声音开关状态和已安装的音轨
thinklight unmute           打开声音（首次会自动装上默认音轨）
thinklight mute             关闭声音，音轨文件保留
thinklight update --check   检查是否有新版
thinklight update           更新 ThinkLight
```

ThinkLight每24小时最多在后台检查一次新版，有更新时发送macOS通知。检查过程会访问本仓库，安装更新需要手动运行`thinklight update`。

## 声音（默认关闭）

灯只在你看得见的地方报信。派完任务就去做别的、人不在屏幕前时，声音能补上这一段。

ThinkLight装好后是静音的，打开只要一条命令：

```bash
thinklight unmute      # 干活时循环播放，干完时一声提示
thinklight mute        # 恢复静默，绿灯照常工作
thinklight config      # 当前是哪种状态，以及装了哪些音轨
```

在Claude Code里，插件提供同样的三个命令：`/thinklight:unmute`、`/thinklight:mute`、`/thinklight:config`。开关一秒内生效，所以`/thinklight:unmute`在它自己那一轮就能听见。

第一次`unmute`会把两首默认音轨装到位：

```text
~/.local/share/thinklight/loop.flac   AI干活时循环播放
~/.local/share/thinklight/done.flac   干完时播放一次
```

想换成自己的，直接替换文件即可，不用重新编译。格式支持macOS能解码的常见类型（FLAC、MP3、WAV、AAC等），扩展名不必一致，只有`loop`和`done`这两个名字有意义。声音开着时daemon会占用音轨文件，换完运行`thinklight mute && thinklight unmute`即可加载新的。之后再`unmute`不会覆盖你换过的音轨；想换回默认曲，把它删掉再`unmute`。

安装和更新都改不了以上任何一项：安装脚本只刷新`~/.local/share/thinklight/defaults/`——也就是`unmute`取默认曲的地方——真正生效的音轨和开关本身都在安装脚本不写的位置。所以更新既不会让一台静音的机器突然出声，也不会覆盖你选的音轨。

音量跟随系统音量，ThinkLight不单独调节。完成音还没放完你就派了新任务的话，它会被立刻掐断换回背景音乐——「轮到你了」的提示在下一轮开始的瞬间就过期了。`thinklight blink`走的是同一条on/off路径，所以打开声音后这个诊断命令也会响。

想把开关和音轨放到别处，设置`THINKLIGHT_SHARE_DIR`即可，daemon和CLI都读它。

## 隐私、资源与兼容性

- **摄像头画面**：ThinkLight需要摄像头权限来点亮硬件LED。采集到的帧会在回调中直接丢弃，不做图像处理，也不写入磁盘。
- **资源占用**：采集使用低分辨率preset，不编码、不保存视频。空闲时daemon继续等待下一次会话，但摄像头采集完全停止。声音打开时，音轨会被打开并预加载播放缓冲，而不是整首解码进内存。
- **声音**：音轨完全本地播放，不联网。静音状态（也就是默认状态）下daemon不做任何音频初始化。
- **视频会议**：macOS支持多个进程共享摄像头，ThinkLight已测试可与Zoom、腾讯会议同时运行。但其他应用正在使用摄像头时，绿灯会持续亮起，此时灯光无法反映ThinkLight的状态。
- **摄像头选择**：使用Mac内建摄像头；接有Studio Display时，它的摄像头灯也会同步亮灭，每台显示器一个🟢（灯亮期间每秒重新检测插拔，运行中途插上的显示器约1秒后跟上）。连续互通相机和其他外接摄像头不受影响。
- **指示灯归属**：Daemon通过launchd启动，macOS会把摄像头使用记在`thinklight-daemon`自己名下。菜单栏只有控制中心图标上的小绿点，不会额外出现绿色摄像头胶囊图标。
- **异常退出与中断**：ThinkLight每秒检查一次会话所属进程，并清理已经退出的会话状态。Codex的Ctrl+C中断不会触发`Stop` hook，因此daemon还会检测该回合写入本地transcript的结束事件并清理状态。Claude Code的Esc中断目前没有对应hook，因此中断后灯可能暂时保持亮起；等下一个回合结束时会熄灭，也可以运行`thinklight off`。

## 原理

ThinkLight的Swift daemon在每个状态摄像头（内建摄像头，接有Studio Display时加上它的摄像头）上各启动一个`AVCaptureSession`。摄像头实际采集时，macOS会点亮与硬件联动的绿色指示灯；停止采集时指示灯熄灭。Daemon每秒核对各个AI Agent会话的状态：只要还有会话在运行就保持采集（灯亮），没有则停止采集并等待下一次会话（灯灭）。Codex token还带有transcript和turn信息，让daemon能识别被Ctrl+C打断而未触发`Stop`的回合。Daemon空闲常驻，避免会话刚开始时撞上旧进程退出而漏掉启动信号。

声音挂在同一个状态跳变上，因此不需要额外的状态机：daemon用两个`AVAudioPlayer`分别持有循环曲（`numberOfLoops = -1`，无缝重复）和完成音，暗→亮时启动循环曲，亮→暗时停掉它并播一次完成音。同一次tick还会重读`unmute`写下的开关，所以设置一秒内生效，不用等daemon重启。播放器是在开关翻转时构建、而不是在灯的跳变上构建：在回合边界那一秒才解码会把提示音推迟到它本该标记的时刻之后，而拨开关是一次没有时限的主动操作。静音时daemon完全不碰音频API；打开但音轨缺失时`AVAudioPlayer`构建失败，daemon为每个缺失的音轨记一行stderr后继续——灯不该因为没有声音就罢工。

## License

MIT
