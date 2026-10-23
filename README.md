# Codex Usage Float

A small macOS floating window and menu bar helper for monitoring local Codex usage limits.

It reads usage information from the local Codex app server and shows:

- 5-hour usage, when that window exists for the current plan
- weekly usage
- reset time for each visible window
- reset credits
- plan badge, such as `FREE`, `PLUS`, `PRO 5X`, or `PRO 20X`
- menu bar summary, with a compact icon mode for small MacBook screens
- a passive follow overlay showing remaining quota beside the focused Codex window when the main window is hidden

[中文说明](README.zh.md)

## Requirements

- macOS 13 or later
- Swift toolchain from Xcode Command Line Tools
- ChatGPT/Codex installed and signed in locally
- `codex app-server --stdio` available either from the ChatGPT app bundle or on `PATH`
- Accessibility permission for Codex Usage Float to follow the Codex window; the main window and menu bar work without it

This is an unofficial local utility. It uses the local Codex app-server interface and does not send your usage data anywhere else.

## Run

```bash
./run.sh
```

The script compiles the Swift sources, builds `CodexUsageFloat.app`, copies bundled resources, and opens the app.

Use `./run.sh --build-only` to build without launching. Run `./tools/test.sh` for the follow-overlay controller's behavior tests; these do not start the app or request system permissions.

## Start On Login

```bash
./start-on-login.sh
```

First install the built `CodexUsageFloat.app` in `/Applications`. This script installs `~/Library/LaunchAgents/local.codex.usagefloat.plist`. The LaunchAgent waits 20 seconds after login, checks the installed executable's exact path, and opens `/Applications/CodexUsageFloat.app` when needed. It does not depend on the repository checkout; logs are stored in `~/Library/Logs/CodexUsageFloat/`.

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

## Follow Overlay

Hiding the main window with the yellow dot or menu bar item leaves the app running. While the main window is hidden, a small follow overlay appears near the upper-left corner of the focused Codex window. It is always enabled and has no separate toggle. Restoring the main window hides the overlay.

The overlay uses English copy to match the main window: `Weekly 40% left` and `5H 88% left`, omitting a row when that quota is unavailable. It uses the same real usage snapshots, remaining-quota calculation, colors, and refresh cycle as the main window. Only the text is drawn; its background is fully transparent so nearby Codex controls remain visible. It has no animated bars, plan badge, reset timer, or red outline. Waiting for data displays `Connecting...`; a failed read displays `Usage unavailable` instead of stale percentages. Dragging a main-window bar to preview colors does not affect overlay data.

The overlay is fully click-through: clicks and scrolling reach the interface underneath, and it never takes keyboard focus. It has no buttons, drag handle, or context menu. Its position uses a fixed offset from the Codex window's upper-left corner; folding the Codex sidebar does not change that rule.

Only one overlay follows the currently focused Codex window. Switching applications, hiding or minimizing Codex, losing permission, or losing a reliable target window hides it. It returns automatically when those conditions recover and the main window is still hidden. Quitting either app removes it; restarting Codex lets the running helper find it again. Continuous position tracking runs while the overlay is visible and stops when hidden; usage polling continues normally.

Full-screen windows, Spaces, and multiple displays, including different display scales, are supported behavior targets. Validate window layering, continuous dragging and resizing, and cross-display positioning on a real Mac using the [validation checklist](docs/follow-overlay-validation.md); controller tests alone cannot confirm them.

### Accessibility Permission

The main window explains why Accessibility access is needed and provides an entry to System Settings. Enable Codex Usage Float in **System Settings → Privacy & Security → Accessibility** so it can read the focused Codex window's position and size. The app does not repeatedly show permission prompts. Until access is granted, the existing main window and menu bar remain usable and the follow overlay stays hidden.

Granting access takes effect automatically. Revoking it hides the overlay and updates the explanation in the main window. Test permission using the actual built app: rebuilding and locally signing the app may require renewed approval.

If an older copy is installed in Applications, its permission does not establish permission for a differently signed workspace build. In the Accessibility list, right-click the app and choose Show in Finder to check which copy is authorized. Remove an obsolete entry before using `+` to add the current workspace `CodexUsageFloat.app`: adding the same bundle identifier again may leave the old record unchanged. Restarting alone does not resolve an authorization associated with the other copy. To clear only this helper's Accessibility approval when necessary, use `tccutil reset Accessibility local.codex.usagefloat`, then add and approve the actual build again. This revokes the existing approval; it does not grant permission.

## Privacy

The app starts a local `codex app-server --stdio` child process and calls `account/rateLimits/read`. It keeps data in memory and does not write usage snapshots to disk.

Accessibility access is used to locate and follow the focused Codex window. The follow overlay reuses the existing local quota data source and does not add a remote service.

## Project Layout

```text
CodexUsageFloat.swift       Main window, usage client, and application lifecycle
UsageModels.swift           Shared quota snapshots
FollowOverlayController.swift  Overlay behavior and presentation state
CodexWindowTracker.swift    Codex window observation and visible-only sampling
FollowOverlayWindow.swift   Passive AppKit overlay
FollowAccessibilityHelp.swift  Main-window permission guidance
Tests/                     Controller behavior tests
docs/follow-overlay-validation.md  Real-machine QA and results
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
