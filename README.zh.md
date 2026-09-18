# Codex Usage Float

一个 macOS 小浮窗和菜单栏工具，用来查看本机 Codex 使用限制。

它会从本机 Codex app-server 读取用量，并显示：

- 5 小时用量窗口：当前套餐存在这个限制时才显示
- 每周用量窗口
- 每个窗口的 reset 时间
- reset credits
- 套餐标签，例如 `FREE`、`PLUS`、`PRO 5X`、`PRO 20X`
- 菜单栏摘要；MacBook 小屏空间不足时会自动切换成紧凑图标

[English README](README.md)

## 环境要求

- macOS 13 或更新版本
- Xcode Command Line Tools 提供的 Swift 工具链
- 本机已安装并登录 ChatGPT/Codex
- 可以从 ChatGPT app bundle 或 `PATH` 调用 `codex app-server --stdio`

这是一个非官方的本地工具。它使用本机 Codex app-server 接口，不会把你的用量数据发送到其他地方。

## 运行

```bash
./run.sh
```

脚本会编译 `CodexUsageFloat.swift`，生成 `CodexUsageFloat.app`，复制资源文件，并打开 app。

## 开机自启

```bash
./start-on-login.sh
```

这个脚本会安装 `~/Library/LaunchAgents/local.codex.usagefloat.plist`。LaunchAgent 会在登录后等待 20 秒，检查程序是否已经运行，如果没有就打开本地 app bundle。

## 使用方式

- 点红色圆点退出。
- 点黄色圆点隐藏浮窗。
- 点菜单栏 item 显示或隐藏浮窗。
- 在空间较小的内建屏上，菜单栏会显示紧凑 Codex 图标；鼠标悬停可以看到完整 tooltip。
- 在大屏上，菜单栏会显示文字摘要，例如 `Codex Usage W 65%` 或 `Codex Usage 5H 65% · W 65%`。

## 隐私

程序会启动本机 `codex app-server --stdio` 子进程，并调用 `account/rateLimits/read`。用量数据只保存在内存中，不会写入磁盘。

## 项目结构

```text
CodexUsageFloat.swift  AppKit 源码
Info.plist             app bundle 元数据
Resources/             打包进 app bundle 的图标和 logo 资源
run.sh                 本地构建并运行
start-on-login.sh      安装 LaunchAgent
```

## License

MIT。Logo 和产品名称归各自权利方所有。
