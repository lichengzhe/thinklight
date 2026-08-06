# ThinkLight 🟢

[English](README.md) | **中文**

**MacBook屏幕上面的🟢，变成AI工作状态灯。不占屏幕空间，切应用、开全屏，随时知道AI干完了。**

ThinkLight用Mac内建摄像头旁的绿灯显示Claude Code和Codex CLI的状态，并可选地配上声音：

| 状态 | 灯光 | 声音（默认关闭） |
| --- | --- | --- |
| AI正在干活——放心去做别的 | 常亮 | 循环播放背景音乐 |
| 干完了——轮到你 | 熄灭 | 播放一次完成音 |

> **安装只有一步**——[在Claude Code里执行两条命令](#claude-code)，其余的它自己装。

## 有什么用

和AI Agent协作像接力：你派出任务，棒就在AI手里；它跑完，棒交还给你。但任务一跑几分钟，你切去做别的事之后，想知道棒是否回到了自己手里，只能反复切回终端看。

ThinkLight把这个信号放进余光：灯亮着，AI还在忙，你继续专注手头的事；灯灭了，轮到你——验收结果、给反馈、派下一个任务。不弹窗，也不像桌宠或状态挂件要占一块屏幕——灯在屏幕之外，不占一个像素，切换桌面或进入全屏后依然可见。

人不在屏幕前的时候，还可以[配上声音](#声音默认关闭)——默认关闭，`thinklight unmute`打开。

它尤其适合：

- 经常派耗时任务给Claude Code或Codex；
- 同时开着多个AI Agent会话；
- 通过ssh在服务器或另一台Mac上跑Agent；
- 想保持专注，又不想错过接手的时机。

多个会话并存时，只要还有一个在跑，灯就保持常亮；全部干完后熄灭。[ssh过去的机器上](#跑在别的机器上的agent)的会话同样算在内。

## 安装

需要一台带内建摄像头的Mac，macOS 14或更新。跑Agent的机器不必是这台Mac。

东西是两部分——**插件**负责在Agent开始和结束时通知状态灯，**程序**负责占住摄像头把LED点亮——但你只需要装一个。插件在第一个会话里就会把与自己版本配套的程序装进`~/.local/bin`并发通知告诉你；之后插件更新，程序也照同样的方式跟上。这一步[你想自己来](#自己安装程序)当然也可以，想彻底关掉它则是一条命令。

### Claude Code

两条命令，之后什么都不用做：

```text
/plugin marketplace add lichengzhe/thinklight
/plugin install thinklight@thinklight
```

这会配好hooks，并加上`/thinklight:unmute`、`/thinklight:mute`、`/thinklight:config`三个用于[声音](#声音默认关闭)的命令。这三个只能由你主动触发，Claude不会自己调用。

装好后开一个会话，插件就会在后台把程序装上——从[Releases](https://github.com/lichengzhe/thinklight/releases)下载的预编译通用二进制（Apple Silicon与Intel均适用）——装完发一条通知。灯第一次亮起时macOS会弹出摄像头授权，允许之后绿灯就跟着Agent走了。想一次看到全过程：

```bash
~/.local/bin/thinklight blink 3   # 绿灯亮3秒
```

### Codex CLI

Codex CLI 0.145及以上版本安装相同的hooks，程序也以同样的方式装上：

```bash
codex plugin marketplace add https://github.com/lichengzhe/thinklight.git
codex plugin add thinklight@thinklight
codex   # 在交互会话中确认 hook 信任提示
```

### 让Agent帮你装

把下面这段直接发给**能操作你想装的那台机器的终端**的Claude Code、Codex或其他coding agent——有灯的那台Mac，或者你ssh过去的服务器都行：

```text
请帮我在这台机器上安装并配置 ThinkLight：https://github.com/lichengzhe/thinklight。
先阅读仓库中的 README.zh.md、get.sh 和 plugin/scripts/install-programs.sh，确认安装范围。
优先走插件：Claude Code 用 `claude plugin marketplace add lichengzhe/thinklight` 和
`claude plugin install thinklight@thinklight`，Codex CLI 用对应的 codex plugin 命令；
只有插件方式失败时，才退回到往 ~/.claude/settings.json 里写 hooks。
插件会在会话开始时自己安装程序；如果 ~/.local/bin 里还没有，就运行 get.sh
（或克隆仓库后运行 install.sh 从源码构建）。之后运行
~/.local/bin/thinklight blink 3 和 ~/.local/bin/thinklight check 验证。
需要我授予 macOS 摄像头权限或确认 hook 信任时，停下来明确告诉我该点哪里。
如果这台机器不是 Mac，或者你是在 ssh 会话里工作，那么灯在我 ssh 过来的那台 Mac 上：
这台机器需要的就只是同样这一次插件安装，验证方式换成 ~/.local/bin/thinklight tunnel status，
而不是 blink 和 check。如果它报告没有隧道，就告诉我去那台 Mac 上运行 `thinklight tunnel setup`
再重连——它要改那边的 ~/.ssh/config，你不要在这里替我动手。
完成后汇报安装位置、hook 配置和验证结果；不要改动无关设置。
```

macOS摄像头授权与Codex hook信任仍需要你亲自确认；`thinklight tunnel setup`也仍然由你自己来跑——它要写你的`~/.ssh/config`，这不是agent该替你决定的事。

### 自己安装程序

下面任何一种方式都会让插件无事可做：自动安装只在`~/.local/bin`里缺程序、或程序比插件旧的时候才跑，所以先把程序装好，实际上就等于关掉了它。想彻底关掉，用`thinklight config bootstrap off`；如果什么都还没装，就在启动Agent的环境里设`THINKLIGHT_NO_BOOTSTRAP=1`。

**一行装预编译版。** 和插件会做的下载完全相同：

```bash
curl -fsSL https://raw.githubusercontent.com/lichengzhe/thinklight/main/get.sh | bash
```

**从源码构建。** 需要Xcode Command Line Tools（`swiftc`）。源码安装跟的是`main`而不是发布版，`thinklight update`也跟着走那条线；插件能认出源码安装，不会去碰它：

```bash
git clone https://github.com/lichengzhe/thinklight.git
cd thinklight
./install.sh
```

**手动放程序。** 从Releases下载压缩包，解压后用`xattr -d com.apple.quarantine`去掉隔离属性，再把三个程序放进`~/.local/bin`。

### 不用插件配hooks

不用插件，代价是没有`/thinklight:*`命令、hooks不会自动更新，上面那套程序自动安装也没有了——程序从此由你自己装、自己更新。hooks本身只是`~/.claude/settings.json`里的四条：

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

无论用哪种方式装，你提交消息（`UserPromptSubmit`）时灯亮起，回合正常结束（`Stop`）、API请求失败（`StopFailure`）或会话结束（`SessionEnd`）时熄灭。会话退出或崩溃后，daemon会在一秒内清理它的状态。权限确认框弹出期间算作「在跑」，灯保持亮起。

## 命令行

安装hooks后通常不需要手动调用这些命令，但它们可用于测试、排查或接入其他工具：

```text
thinklight on               将当前会话标记为运行中
thinklight off [--force]    注销当前会话
                            在终端直接运行或加 --force：清空状态并立即灭灯
thinklight status           输出 on 或 off
thinklight blink [秒]       亮起指定时间后熄灭
thinklight check            读取 CoreMediaIO 报告的摄像头硬件状态
thinklight version          输出已安装程序的版本
thinklight config           输出全部设置：声音、已装音轨、自动安装、更新检查
thinklight config KEY VALUE 改一项设置：sound、bootstrap 或 update-check，取 on 或 off
thinklight unmute           打开声音（首次会自动装上默认音轨）
thinklight mute             关闭声音，音轨文件保留
thinklight theme install P  从zip或目录装一套音轨主题（见下文）
thinklight theme current    显示已装主题的名称、作者、许可、来源
thinklight theme reset      恢复内置默认音轨，手工换过的曲子也会被替换掉
thinklight tunnel setup [H] 把这台Mac的灯带进ssh会话；不写主机则对所有主机生效
thinklight tunnel status    说明这台机器上的会话会点亮哪一盏灯
thinklight update --check   检查是否有新版
thinklight update           更新 ThinkLight
```

ThinkLight每24小时最多在后台检查一次新版，有更新时发送macOS通知。检查和`thinklight update`都按安装方式办事：预编译安装比对自己的版本和最新的发布版，更新就是再跑一次`get.sh`；源码安装比对自己的修订和`main`（`git ls-remote`），更新则是`git pull`加`install.sh`。两种方式下，装上更新都是你自己运行的一条命令。不采集也不上传任何使用数据。不想要的话`thinklight config update-check off`可以关掉——关掉之后`thinklight update --check`仍然可用，那是你主动问的，不算后台行为。

另一道缝由插件自己合上：插件会自动更新，而`~/.local/bin`里的程序不会，两者本可能漂移成一个谁都没选择过的组合——新hooks配旧CLI。插件在会话开始时比对双方版本；程序缺失或更旧时，才下载并装上与自己配套的程序，然后发通知说明做了什么。若程序反而更新则保持不动，避免Claude和Codex的插件更新时间不同，来回降级、升级同一份共享程序。每个插件版本只尝试一次，做了什么都会告诉你；有两种情况它不越权替你决定：源码安装仍由`thinklight update`说话，而`thinklight config bootstrap off`会让它退回从前那样只提醒。

## 声音（默认关闭）

灯只在你看得见的地方报信。派完任务就去做别的、人不在屏幕前时，声音能补上这一段。

```bash
thinklight unmute      # 干活时循环播放，干完时一声提示
thinklight mute        # 恢复静默，绿灯照常工作
thinklight config      # 当前状态和已装的音轨
```

Claude Code插件里是同样的三个：`/thinklight:unmute`、`/thinklight:mute`、`/thinklight:config`。开关一秒内生效，所以`/thinklight:unmute`在它自己那一轮就能听见。

第一次`unmute`会把两首默认音轨装到`~/.local/share/thinklight/`：`loop`循环播放，`done`播一次。想换成自己的直接替换文件，格式支持macOS能解码的常见类型（FLAC、MP3、WAV、AAC等），扩展名不限，只有`loop`和`done`这两个名字有意义；换完运行`thinklight mute && thinklight unmute`重新加载。之后再`unmute`不会覆盖你换过的音轨，删掉才会取回默认曲——安装和更新同样碰不到这两个文件，也改不了开关状态。（想放到别处：设`THINKLIGHT_SHARE_DIR`。）

一首一首换是给自己用的；**音轨主题**是给分享用的——两首曲子打包在一起，带上名字和许可证。主题是一个zip或一个目录，里面是`loop.<ext>`和`done.<ext>`，外加一份可选的`theme.json`，写着`name`、`title`、`author`、`license`、`source`。`thinklight theme install lofi-rain.zip`会先检查两首曲子是否齐全、格式是否是macOS能解码的，通过之前不会碰`~/.local/share/thinklight/`里的任何东西——包坏了就什么都不会变；包好了就会替换掉原来的曲子，旧格式的残留文件不会留下来，如果声音当时是开着的还会自动重载，装完那一轮就能听见。`thinklight theme current`显示当前装的主题信息。`theme.json`缺失或解析不了不会挡着安装——音轨能播才是要紧事，`theme current`只是把名字显示成unknown。

`thinklight theme reset`总是恢复内置默认音轨，哪怕是你手工换上的曲子也会被替换掉——这就是"reset"的含义：你主动跑它，要的就是回到内置的循环曲和完成音。

音量跟随系统音量。完成音还没放完你就派了新任务的话，它会被立刻掐断——「轮到你了」在下一轮开始的瞬间就过期了。`thinklight blink`走的是同一条on/off路径，所以打开声音后这个诊断命令也会响。

## 跑在别的机器上的Agent

灯在你的Mac上，Agent却常常不在：你ssh进一台编译机、或者另一台Mac，在那边跑Claude Code，它的hooks自然也在那边跑，而那台机器上并没有一盏有人看的灯。

ThinkLight把那些回合顺着你本来就开着的ssh连接送回来。在有灯的这台Mac上，做一次：

```bash
thinklight tunnel setup              # 对所有ssh目标生效
thinklight tunnel setup build gpu    # 或只对这几台
```

主机名按你**敲**的那个写——`ssh build`匹配的是`build`，不是它解析出来的`HostName`。它会往`~/.ssh/config`里写一段配置，把daemon的socket发布成你所连机器上的一个本地回环端口。在那台机器上，用和这边完全相同的方式装插件——它自己认得出那里没有摄像头可伺候，于是不装任何需要摄像头的东西：没有daemon，没有二进制，只有一个CLI脚本。

之后就没有别的要配了，也不需要声明哪台是哪台。每个会话只问一个问题，然后自己就答对了：

> **有隧道吗？有就把灯点在隧道另一头；没有就点这台机器自己的。**

| 人在哪 | Agent跑在哪 | 哪盏灯亮 |
| --- | --- | --- |
| 自己的Mac前 | 同一台Mac | 这台Mac的灯——和从前一样，隧道不参与 |
| 自己的Mac前 | ssh到的Linux服务器 | 你眼前这台Mac的灯 |
| 自己的Mac前 | ssh到的另一台Mac | **你眼前这台**，而不是没人看的那台 |

两边都可以用`thinklight tunnel status`把这个问题问出声。

连接一断，灯立刻灭——ssh掉线、合上盖子、Agent被杀掉，都算。远端的pid在这台Mac上毫无意义，所以daemon攥住的是那条连接本身：连接没了就是信号，不需要谁去猜一个超时时长。

### 对跑Agent的那台机器意味着什么

不编译、不授权、不常驻后台、不需要root。那边没有daemon、没有摄像头、也没有声音：CLI打开一个回环端口，写一行字，然后在这一回合里攥住它。

你的ssh会话开着的时候，那个端口存在于远端，属于你自己的sshd进程。同机登录的其他用户理论上能连上它——能做的只有开关你的灯，但在共享机器上这一点值得知道。

### 几个边界

- **VS Code Remote、Cursor、JetBrains**都读`~/.ssh/config`，所以照样带得动灯。**mosh不行**：它根本没有端口转发。
- **tmux**：detach之后让ssh断开，哪怕Agent还在跑，灯也会灭——隧道跟着你的会话一起走了。这是设计上想要的语义（你人已经不在了），但确实可能出乎意料。
- **同时开多条ssh到同一台机器**：第二条发现端口被占，打一行warning，然后共用第一条的隧道。只有当两台**不同的**Mac连同一台服务器时这才要紧：所有会话的灯都会亮在先连上的那台Mac。
- **你正坐在一台同时被别人ssh进来的Mac前**：这台机器上的本地回合也按同一条规则办，于是报到隧道那头去。少见，而且「那头有人在看」也说得通，但这就是这条规则的代价。
- **两跳**：A → B → C 目前送不回A，中间那台得当中继，而它还不会。

## 隐私、资源与兼容性

- **摄像头画面**：ThinkLight需要摄像头权限来点亮硬件LED。采集到的帧会在回调中直接丢弃，不做图像处理，也不写入磁盘。
- **联网**：只有两处会联网，对象都是本仓库。一是插件的会话开始hook：`~/.local/bin`里没有配套程序时，它会下载并安装——每个插件版本只做一次，装完发通知说明，`thinklight config bootstrap off`可关闭。二是装好后的CLI每天最多检查一次新版，且只发通知。两者都不携带任何关于你或你的对话的信息。
- **资源占用**：采集使用低分辨率preset，不编码、不保存视频。空闲时daemon继续等待下一次会话，但摄像头采集完全停止。
- **声音**：音轨完全本地播放，不联网；打开时音轨只是被打开并预加载播放缓冲，不整首解码进内存。静音（默认状态）下daemon不做任何音频初始化。
- **来自别的机器的会话**：隧道里走的是会话id、回合id和机器名——没有prompt内容、没有回复、也没有文件路径。它也不是网络服务：ssh把远端那头绑在`127.0.0.1`上，且只在你的ssh会话存续期间存在；这台Mac这头是你自己state目录里的一个Unix socket，除你之外谁都读写不了。
- **视频会议**：macOS支持多个进程共享摄像头，ThinkLight已测试可与Zoom、腾讯会议同时运行。但其他应用正在使用摄像头时，绿灯会持续亮起，此时灯光无法反映ThinkLight的状态。
- **摄像头选择**：使用Mac内建摄像头；接有Studio Display时，它的摄像头灯也会同步亮灭，每台显示器一个🟢（灯亮期间每秒重新检测插拔，运行中途插上的显示器约1秒后跟上）。连续互通相机和其他外接摄像头不受影响。
- **指示灯归属**：Daemon通过launchd启动，macOS会把摄像头使用记在`thinklight-daemon`自己名下。菜单栏只有控制中心图标上的小绿点，不会额外出现绿色摄像头胶囊图标。
- **异常退出与中断**：ThinkLight每秒检查一次会话所属进程，并清理已经退出的会话状态。Codex的Ctrl+C中断不会触发`Stop` hook，因此daemon还会检测该回合写入本地transcript的结束事件并清理状态。Claude Code的Esc中断目前没有对应hook，因此中断后灯可能暂时保持亮起；等下一个回合结束时会熄灭，也可以运行`thinklight off`。

## 原理

ThinkLight的Swift daemon在每个状态摄像头（内建摄像头，接有Studio Display时加上它的摄像头）上各启动一个`AVCaptureSession`。摄像头实际采集时，macOS会点亮与硬件联动的绿色指示灯；停止采集时指示灯熄灭。Daemon每秒核对各个AI Agent会话的状态：只要还有会话在运行就保持采集（灯亮），没有则停止采集并等待下一次会话（灯灭）。Codex token还带有transcript和turn信息，让daemon能识别被Ctrl+C打断而未触发`Stop`的回合。Daemon空闲常驻，避免会话刚开始时撞上旧进程退出而漏掉启动信号。

跑在别的机器上的会话没法往这个state目录里写东西，于是它改成通过一个Unix socket和daemon说话——`thinklight tunnel setup`把这个socket作为`RemoteForward`交给ssh。远端的hook找到那个被转发的端口，先确认应答的确实是daemon，然后在这一回合剩下的时间里攥住这条连接。这条连接就是那个会话：daemon里的token活得和它一样久，所以ssh一掉线灯就灭了，既不需要探测什么，也不需要等待什么。远端不需要自己的daemon；而一台没有隧道的机器根本察觉不到这一切——它走的还是从前那条路。

声音挂在同一个状态跳变上，因此不需要额外的状态机：daemon用两个`AVAudioPlayer`分别持有循环曲（`numberOfLoops = -1`，无缝重复）和完成音，暗→亮时启动循环曲，亮→暗时停掉它并播一次完成音。同一次tick还会重读`unmute`写下的开关，所以设置一秒内生效；播放器在开关翻转时构建，而不是在灯的跳变上——那一秒才解码会把提示音推迟到它本该标记的时刻之后。静音时完全不碰音频API，音轨缺失时也只记一行stderr继续跑——灯不该因为没有声音就罢工。

## 联系我

Bug和功能建议走[issue](https://github.com/lichengzhe/thinklight/issues)最方便，其余的可以扫码加我微信：

<img src="docs/wechat-qr.png" alt="微信二维码" width="140">

## License

MIT
