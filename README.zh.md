# Codex Usage Float

一个 macOS 小浮窗和菜单栏工具，用来查看本机 Codex 使用限制。

它会从本机 Codex app-server 读取用量，并显示：

- 5 小时用量窗口：当前套餐存在这个限制时才显示
- 每周用量窗口
- 每个窗口的 reset 时间
- reset credits
- 套餐标签，例如 `FREE`、`PLUS`、`PRO 5X`、`PRO 20X`
- 菜单栏摘要；MacBook 小屏空间不足时会自动切换成紧凑图标
- 主窗口收起后，依附于当前聚焦 Codex 窗口的只读跟随额度浮层

[English README](README.md)

## 环境要求

- macOS 13 或更新版本
- Xcode Command Line Tools 提供的 Swift 工具链
- 本机已安装并登录 ChatGPT/Codex
- 可以从 ChatGPT app bundle 或 `PATH` 调用 `codex app-server --stdio`
- 跟随额度浮层需要为 Codex Usage Float 授予“辅助功能”权限；未授权不影响主窗口和菜单栏

这是一个非官方的本地工具。它使用本机 Codex app-server 接口，不会把你的用量数据发送到其他地方。

## 运行

```bash
./run.sh
```

使用 `./run.sh --build-only` 只构建、不启动。运行 `./tools/test.sh` 可执行浮层控制器行为测试；测试不会启动应用或请求系统权限。

脚本会编译 Swift 源码，生成 `CodexUsageFloat.app`，复制资源文件，并打开 app。

## 开机自启

```bash
./start-on-login.sh
```

这个脚本会安装 `~/Library/LaunchAgents/local.codex.usagefloat.plist`。LaunchAgent 会在登录后等待 20 秒，检查程序是否已经运行，如果没有就打开本地 app bundle。

## 应用图标

图标是可复现的矢量资产：

- `Resources/AppIcon.svg` — 1024 母版（824 圆角方块 + 100 透明留边）
- `Resources/AppIcon-small.svg` — 16/32px 专用简化版（更粗的环、更大的用量条、去掉虚线与辉光）
- `Resources/AppIcon.icns` — 打包进 app bundle 的最终图标

改完 SVG 后重新生成：

```bash
./tools/build-icon.sh
```

脚本用 Chrome（或 `rsvg-convert`）把 SVG 栅格化到 1024，再用 `sips` 生成各尺寸、`iconutil` 打成 `.icns`。Finder 若仍显示旧图标，先 `touch CodexUsageFloat.app` 并重开窗口，必要时再 `killall Finder`。

## 使用方式

- 连续进度条随余量变化，四档各有一种动效：70–100% 绿色「极光漂移」（两道光带缓慢反向漂移）、40–69% 蓝色「光带流动」（斜向细光带匀速流向额度剩余端）、10–39% 橙色「余烬呼吸」（端点暖光缓慢胀缩）、低于 10% 红色「低位呼吸」（整条容量条以约 1 秒的节奏缓慢闪烁，0% 也提示）。隐藏窗口或开启 macOS“减少动态效果”时保留配色、停止运动。
- 按住彩色条右端的隐形手柄左右拖动，可预览不同余量的颜色与动画；松开后回到最新真实余量。预览不会修改用量数据或触发额度刷新通知。
- 点红色圆点退出。
- 点黄色圆点隐藏浮窗。
- 点菜单栏 item 显示或隐藏浮窗。
- 在空间较小的内建屏上，菜单栏会显示紧凑 Codex 图标；鼠标悬停可以看到完整 tooltip。
- 在大屏上，菜单栏会显示文字摘要，例如 `Codex Usage W 65%` 或 `Codex Usage 5H 65% · W 65%`。

## 跟随额度浮层

通过黄色圆点或菜单栏入口将主窗口收起到托盘后，程序继续运行。当 Codex 窗口聚焦时，跟随额度浮层出现在窗口左上区域。这个功能始终启用，不提供独立开关；展开主窗口时，浮层自动隐藏。

浮层显示“周剩余”和“5h 剩余”百分比；缺少某项额度时只显示另一行。它复用主窗口的真实额度快照、剩余额度算法、颜色分档及刷新周期。仅绘制文字，背景完全透明，让相邻的 Codex 控件保持可见；不显示动态进度条、套餐、重置倒计时或红色边框。等待数据时显示“额度连接中…”，读取失败时显示“额度暂不可用”，不将旧百分比继续当作有效数据。拖动主窗口进度条预览颜色不会改变浮层的数据。

浮层完全穿透鼠标：点击、滚动直接作用于下方界面，也不会抢占键盘焦点。浮层没有按钮、拖动手柄或右键菜单。位置相对 Codex 窗口左上角固定，折叠侧栏不会改变定位规则。

同一时间只显示一个浮层，跟随当前聚焦的 Codex 窗口。切换应用、隐藏或最小化 Codex、撤销授权或无法可靠定位目标窗口时，浮层隐藏；条件恢复且主窗口仍收起时自动恢复。退出任一程序后浮层消失；Usage Float 仍运行时，重启 Codex 后会重新识别窗口。浮层可见时持续跟踪位置，隐藏后停止高频位置检查，额度仍按原有机制刷新。

全屏、桌面切换、多显示器及不同缩放比例属于支持目标。连续拖动、缩放、全屏层级和跨屏定位必须在真实 Mac 上按[验收清单](docs/follow-overlay-validation.md)验证，控制器测试通过不能替代这些实机结果。

### 辅助功能授权

主窗口会说明授权用途，并提供前往系统设置的入口。在“系统设置 → 隐私与安全性 → 辅助功能”中允许 Codex Usage Float 访问，以读取当前聚焦 Codex 窗口的位置和尺寸。程序不会反复弹出授权请求。未授权时浮层暂不可用，原有主窗口和菜单栏仍可正常使用。

完成授权后自动生效；撤销授权后浮层隐藏，主窗口更新原因说明。应使用实际构建的应用进行授权验证；重新构建并进行本地签名后，可能需要重新授权。

如果“应用程序”中还保留旧版，它的授权不代表签名不同的工作区构建也已授权。可在辅助功能列表中右键应用，选择“在访达中显示”核对实际位置。先移除过期记录，再使用 `+` 添加当前工作区里的 `CodexUsageFloat.app`：直接重复添加相同标识的应用可能不会替换旧记录，仅重启也无法解决。必要时可执行 `tccutil reset Accessibility local.codex.usagefloat`，仅清除此工具的辅助功能授权，再重新添加并允许实际构建。此命令只撤销原有批准，不会自动授予权限。

## 隐私

程序会启动本机 `codex app-server --stdio` 子进程，并调用 `account/rateLimits/read`。用量数据只保存在内存中，不会写入磁盘。

辅助功能权限用于定位并跟随当前聚焦的 Codex 窗口。浮层复用现有本地额度数据源，不新增远端服务。

## 项目结构

```text
CodexUsageFloat.swift    主窗口、额度客户端和应用生命周期
UsageModels.swift       共用额度快照
FollowOverlayController.swift  浮层行为和呈现状态
CodexWindowTracker.swift Codex 窗口观察和可见期间采样
FollowOverlayWindow.swift  被动 AppKit 浮层
FollowAccessibilityHelp.swift  主窗口授权说明
Tests/                   控制器行为测试
docs/follow-overlay-validation.md  实机验收记录
Info.plist               app bundle 元数据
Resources/               打包进 app bundle 的图标和 logo 资源
design/progress-bar/     四档动效的 SVG 设计稿与浏览器预览页
Resources/AppIcon.svg    应用图标母版（矢量）
tools/build-icon.sh      从 SVG 重新生成 AppIcon.icns
run.sh                   本地构建并运行
start-on-login.sh        安装 LaunchAgent
```

## License

MIT。Logo 和产品名称归各自权利方所有。
