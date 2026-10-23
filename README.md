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

## App Icon

The icon is a reproducible vector asset:

- `Resources/AppIcon.svg` — 1024 master (824 squircle on a 1024 canvas with a 100 px transparent margin)
- `Resources/AppIcon-small.svg` — simplified art for the 16/32 px slots (thicker ring, larger quota bars, no dashes or glow)
- `Resources/AppIcon.icns` — the icon packaged into the app bundle

Regenerate after editing the SVG:

```bash
./tools/build-icon.sh
```

The script rasterises the SVG at 1024 with Chrome (or `rsvg-convert`), then builds every size with `sips` and packs the `.icns` with `iconutil`. If Finder keeps showing the old icon, `touch CodexUsageFloat.app` and reopen the window; `killall Finder` as a last resort.

## UI Behavior

- Continuous usage bars change with remaining quota, and each tier has its own motion: green at 70–100% (two caustic bands drifting slowly in opposite directions), blue at 40–69% (thin diagonal ribbons flowing towards the remaining end), amber at 10–39% (a warm bloom breathing at the tip), and red below 10% (the whole bar breathing a slow red pulse; 0% is still reported). Colours stay when the window is hidden or macOS Reduce Motion is enabled; the motion stops.
- Drag the invisible handle at the right end of a filled bar to preview its colors and animations. Releasing it returns to the latest real quota; the preview never changes usage data or triggers reset notifications.
- Click the red dot to quit.
- Click the yellow dot to hide the floating window.
- Click the menu bar item to show or hide the floating window.
- On smaller built-in displays, the menu bar item switches to a compact Codex icon. Hover it to see the full tooltip.
- On larger displays, the menu bar item shows a text summary, for example `Codex Usage W 65%` or `Codex Usage 5H 65% · W 65%`.

## Privacy

The app starts a local `codex app-server --stdio` child process and calls `account/rateLimits/read`. It keeps data in memory and does not write usage snapshots to disk.

## Project Layout

```text
CodexUsageFloat.swift       AppKit source
Info.plist                  App bundle metadata
Resources/                  Icons and logo assets copied into the app bundle
design/progress-bar/        SVG motion prototypes and a browser preview of the four tiers
Resources/AppIcon.svg       App icon master (vector)
tools/build-icon.sh         Rebuild AppIcon.icns from the SVG
run.sh                      Build and run locally
start-on-login.sh           Install the LaunchAgent
```

## License

MIT. Logo and product names belong to their respective owners.
