## Agent skills

### Skill：reinstall-after-update（更新后重安装）

**何时使用**：合并了会改动可执行文件或构建脚本的提交之后；用户要求更新后重装、重新安装、清理旧版本或修复辅助功能授权。这是项目级 skill，按文档执行即可，不需要再向用户确认流程本身。

**硬性规则**（违反即返工）：

1. 只用 `./run.sh --build-only` 构建；默认 `./run.sh` 会直接启动仓库副本。
2. 安装前必须：`codesign --verify --deep --strict` 通过、安装与构建的 SHA-256 一致、产物 `minos ≤ sw_vers -productVersion`。`run.sh` 已自动拦截不兼容产物（`error -10825` 的成因），不要绕过。
3. 替换安装包后先 `lsregister -f /Applications/CodexUsageFloat.app`，再用 `open -n` 验证启动。直接执行包内二进制不算验证。
4. 交付时废纸篓外只保留 `/Applications/CodexUsageFloat.app`，且只有 1 个应用进程。
5. 需要用户在系统设置里授权或做真机验收时，保留“待验证”状态并写清用户要做的那一步，不把待办写成完成。

完整流程、兼容性说明与故障排查：[更新后重安装](docs/agents/reinstall-after-update.md)。

### Issue tracker

Issues live in this repo's GitHub Issues, managed with the `gh` CLI. See `docs/agents/issue-tracker.md`.

### Triage labels

The five canonical triage labels keep their default names. See `docs/agents/triage-labels.md`.

### Domain docs

Single-context: `GLOSSARY.md` and `docs/adr/` at the repo root. See `docs/agents/domain.md`.
