# Codex Usage Float

A small macOS floating window and menu bar helper for monitoring local Codex usage limits.

It reads usage information from the local Codex app server and shows:

- 5-hour usage, when that window exists for the current plan
- weekly usage
- reset time for each visible window
- reset credits
- plan badge, such as `FREE`, `PLUS`, `PRO 5X`, or `PRO 20X`
- menu bar summary, with a compact icon mode for small MacBook screens

[中文说明](README.zh.md)

## Requirements

- macOS 13 or later
- Swift toolchain from Xcode Command Line Tools
- ChatGPT/Codex installed and signed in locally
- `codex app-server --stdio` available either from the ChatGPT app bundle or on `PATH`

This is an unofficial local utility. It uses the local Codex app-server interface and does not send your usage data anywhere else.

## Run

```bash
./run.sh
```

The script compiles `CodexUsageFloat.swift`, builds `CodexUsageFloat.app`, copies bundled resources, and opens the app.

## Start On Login

```bash
./start-on-login.sh
```

This installs `~/Library/LaunchAgents/local.codex.usagefloat.plist`. The LaunchAgent waits 20 seconds after login, checks whether the app is already running, and opens the local app bundle when needed.

## UI Behavior

- Click the red dot to quit.
- Click the yellow dot to hide the floating window.
- Click the menu bar item to show or hide the floating window.
- On smaller built-in displays, the menu bar item switches to a compact Codex icon. Hover it to see the full tooltip.
- On larger displays, the menu bar item shows a text summary, for example `Codex Usage W 65%` or `Codex Usage 5H 65% · W 65%`.

## Privacy

The app starts a local `codex app-server --stdio` child process and calls `account/rateLimits/read`. It keeps data in memory and does not write usage snapshots to disk.

## Project Layout

```text
CodexUsageFloat.swift  AppKit source
Info.plist             App bundle metadata
Resources/             Icons and logo assets copied into the app bundle
run.sh                 Build and run locally
start-on-login.sh      Install the LaunchAgent
```

## License

MIT. Logo and product names belong to their respective owners.
