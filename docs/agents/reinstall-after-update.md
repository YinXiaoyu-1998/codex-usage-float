---
name: reinstall-after-update
description: 代码更新后构建、替换 /Applications 安装实例、清理旧副本、修复辅助功能授权并验收跟随浮层。
when_to_use: 用户要求"更新后重装 / 重新安装 / 清理旧版本 / 修辅助功能授权"，或合并了会改变可执行文件或构建脚本的提交之后。
---

# 更新后重安装

适用：更新代码后安装本机应用、重新安装、清理旧版本、修复辅助功能授权。按顺序执行，完成 §6 验收清单后再报告成功。

## 0. 铁律

1. **唯一安装位置** `/Applications/CodexUsageFloat.app`；标识 `local.codex.usagefloat`。仓库内 `.app` 与裸二进制只是构建中间产物。
2. 只用 `./run.sh --build-only` 构建。默认的 `./run.sh` 会直接启动仓库副本，不用于交付。
3. 安装前必须同时满足：`codesign --verify --deep --strict` 通过、构建与安装哈希一致、**产物 minos ≤ 本机 macOS**（见 §2）。
4. 验收必须用 `open -n /Applications/CodexUsageFloat.app` **成功启动**来证明。直接执行 `Contents/MacOS/CodexUsageFloat` 不算，它绕过 LaunchServices，会掩盖构建不兼容（2026-11-15 事故即由此假阳性漏过）。
5. 交付时废纸篓外只允许安装实例及指向它的快捷入口，且只有 1 个运行进程。

## 1. 盘点与同步

1. 记录工作区状态、当前提交、已运行进程的完整可执行路径、现有登录启动配置及应用签名。保护未提交改动；同步 `main` 用 fetch 加快进，合并 PR 仅在用户要求时执行。
2. `mdfind 'kMDItemCFBundleIdentifier == "local.codex.usagefloat"'` 找候选，再扫描可访问目录补足未索引副本：用户目录（Desktop、Downloads、Documents、`~/Applications`、隐藏目录及 worktree）、`~/Library/Application Support`、`/Applications`、`/Users/Shared`、临时与备份目录。排除废纸篓，去重真实路径，避免符号链接循环。
3. 对每个候选读 `Contents/Info.plist` 确认标识；检查进程路径、Finder 替身、Dock 与 LaunchAgent 引用。检查仓库及已知构建目录的裸 `CodexUsageFloat`。
4. 记录全部非唯一副本（含同版本副本、仓库构建、临时回滚备份），作为 §4 的清理清单。只读或不可访问的位置要记录并如实报告。

## 2. 构建与 macOS 兼容性

### 2.1 部署目标由构建脚本固定

`run.sh` 用 `CUF_DEPLOYMENT_TARGET` 决定 `swiftc -target`，默认 `$(uname -m)-apple-macos13.0`，与 `Info.plist` 的 `LSMinimumSystemVersion = 13.0` 对齐。需要支持更老系统时可显式覆盖：

```bash
CUF_DEPLOYMENT_TARGET=arm64-apple-macos12.0 ./run.sh --build-only
```

覆盖后必须同步下调 `Info.plist` 的 `LSMinimumSystemVersion`，并在真实目标系统上重测主窗口、菜单栏与浮层。

### 2.2 为什么必须锁 minos

**事故（2026-11-15）**：工具链（Swift 6.3.2）默认把 `-target` 设成 SDK 的 macOS 版本，产物 `LC_BUILD_VERSION` 的 `minos` 变成 `28.0`。本机是 macOS 27.2.1，`open -n` 直接报 `_LSOpenURLsWithCompletionHandler() failed with error -10825.`，而直接执行二进制照样能跑——于是"试运行通过"是假阳性，装进 `/Applications` 后点开无反应。二分定位：旧包 + 新二进制 → 失败；新包 + 旧二进制 → 成功。

规则与验证：

- `minos ≤ sw_vers -productVersion`，否则 LaunchServices 拒绝启动。
- `run.sh` 构建后已自动校验并 `exit 1`，报错会指出实际 minos、本机版本和覆盖方式；不要绕过该校验。
- 手动复核：

```bash
otool -l CodexUsageFloat.app/Contents/MacOS/CodexUsageFloat \
  | awk '/LC_BUILD_VERSION/,/ntools/' | grep minos
sw_vers -productVersion
```

### 2.3 支持范围

- 默认最低 macOS 13.0；Apple Silicon 默认架构，Intel 用 `CUF_DEPLOYMENT_TARGET=x86_64-apple-macos13.0`。
- 只想在本机构建自用时可提高 `CUF_DEPLOYMENT_TARGET`，但不得高于本机系统版本。

### 2.4 构建

1. `./tools/test.sh`：跟随浮层与重启策略测试必须全通过。
2. `./run.sh --build-only`。
3. `codesign --verify --deep --strict CodexUsageFloat.app`，记录待安装可执行文件的 SHA-256 与 `codesign -dr -` 输出。
4. 已存在可验证的同源码构建时可复用，避免无意义重建和重复授权。

## 3. 安装与替换

1. 暂停已存在的登录任务；关闭所有已确认的 Codex Usage Float 进程与它们的 `codex app-server` 子进程，确认退出后再替换。
2. 把旧安装包移到废纸篓（保持可恢复），再 `ditto CodexUsageFloat.app /Applications/CodexUsageFloat.app`。用 `ditto` 复制而不是在旧包上合并，避免残留过期资源。
3. 复制失败时恢复旧包并报告，不要留下半个安装。
4. 再次 `codesign --verify`，用 `cmp` 或 SHA-256 确认安装的可执行文件与构建完全一致。
5. **重新注册再启动**：`lsregister -f /Applications/CodexUsageFloat.app`，然后 `open -n /Applications/CodexUsageFloat.app`。刚替换过的包若未重新注册，`open` 仍可能返回 -10825。
6. 此前已启用登录启动时执行 `./start-on-login.sh` 更新配置；此前未启用则保持用户选择。检查 plist 指向 `/Applications`，日志落在 `~/Library/Logs/CodexUsageFloat/`，清理指向旧路径的重复任务。
7. 记录新 PID，确认只有 1 个应用进程且完整路径为安装实例。

## 4. 移除副本与旧入口

1. 对 §1 确认的其他副本先 `lsregister -u <旧路径>`，再移到系统废纸篓（保留可恢复性）。未注册的备份可能返回 `-10814`，核对注册列表后继续。保护 `/Applications` 安装实例。
2. 清理构建产生的仓库 `.app`、裸二进制和临时备份。
3. 清理或重定向引用旧副本的桌面替身、符号链接和 Dock 入口；需要保留快捷入口时改指安装实例。无法解析的入口先报告，不凭名称猜测删除。
4. `lsregister -f /Applications/CodexUsageFloat.app` 注册安装实例；保持其他应用的注册信息。
5. 重复盘点。废纸篓外只允许安装实例及其快捷入口。Spotlight 可能缓存已移走路径，逐项确认文件确实不存在。

## 5. 辅助功能授权

1. 读取实际运行应用的主窗口：权限说明消失才表明应用已识别授权。系统设置里的开关为"开"不能替代应用侧验证。
2. 仍有提示时，在"系统设置 → 隐私与安全性 → 辅助功能"里右键该应用选择"在访达中显示"，核对记录指向安装实例。保持最终构建签名不变，再重启安装实例复查。
3. 提示仍在时，先取得当前操作所需的明确授权，再仅移除该应用的旧记录，用 `+` 按完整路径添加 `/Applications/CodexUsageFloat.app` 并允许。新签名（ad-hoc 每次构建都会变）通常被视为新记录，旧记录必须删掉而不是重复添加。
4. 需要系统级重置时只针对该标识执行 `tccutil reset Accessibility local.codex.usagefloat`，随后重新添加并授权。重置会撤销批准，本身不会授予权限；保持其他应用授权不变。
5. 授权完成后保持同一构建，不再编译或签名；若再次替换构建，重做本节验证。

## 6. 验收清单

- 代码：报告安装来源提交；`main` 与远端一致；未提交改动有明确说明。
- 构建：测试通过；`codesign --verify` 通过；安装与构建哈希一致；**minos ≤ 本机 macOS**。
- 启动：`open -n` 成功；只有 1 个进程；路径为 `/Applications/CodexUsageFloat.app/Contents/MacOS/CodexUsageFloat`；`codex app-server` 子进程存活。
- 清理：列出移到废纸篓的副本；快捷入口与登录启动均指向安装实例；无法清理的位置逐项报告。
- 权限：实际应用主窗口已无 Accessibility 提示。
- 浮层：收起主窗口、聚焦 Codex，确认 `Codex Usage Follow Overlay` 出现并显示真实英文额度（如 `Weekly 7% left`）。权限通过不能替代浮层显示验证。
- 无法观察或操作的部分（例如需要用户在系统设置里点授权）保留"待验证"状态并单独说明；不得以构建、测试或进程存活替代显示验证。

## 7. 故障排查

| 现象 | 判断 | 处理 |
| --- | --- | --- |
| `open` 报 `-10825` | 产物 minos 高于本机系统，或刚替换的包未重新注册 | 核对 §2.2 的 minos；`lsregister -f` 后重试；仍失败则重建并确认 `CUF_DEPLOYMENT_TARGET` |
| `open` 报 launchd `Code 5 / POSIX 162` | 应用不在标准安装位置（如 `/tmp`、仓库目录） | 从 `/Applications` 启动；不要用其他路径验证可启动性 |
| `spctl -a` 显示 `rejected` | ad-hoc 签名的正常结果，不是故障 | 以 `codesign --verify --deep --strict` 为准 |
| 出现两个进程 | 旧实例未退出，或登录任务同时拉起 | 结束全部实例、`launchctl bootout` 后重装，再重建登录任务 |
| 浮层不出现 | 未授权、主窗口未收起、Codex 非前台，或窗口在非活动 Space | 依次核对；浮层只在主窗口收起且 Codex 前台时出现 |
| 每次重装都要重新授权 | ad-hoc 签名每次构建都会变 | 属预期；删旧记录再用 `+` 添加安装实例 |
| 菜单栏图标仍是旧的 | 图标缓存 | `touch CodexUsageFloat.app` 后重开窗口；必要时 `killall Finder` |
