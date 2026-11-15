import AppKit
import ApplicationServices

/// Observes only the Codex application. No screen capture or UI text is read.
final class CodexWindowTracker: FollowOverlayTracking {
    var onChange: ((FollowEnvironment) -> Void)?

    private var running = false
    private var workspaceTokens: [NSObjectProtocol] = []
    private var screenToken: NSObjectProtocol?
    private var recoveryTimer: Timer?
    private var positionTimer: Timer?
    private var observer: AXObserver?
    private var observedPID: pid_t?
    private var applicationElement: AXUIElement?
    private var windowElement: AXUIElement?
    private var windowIdentity = FollowWindowIdentityResolver()

    /// Sampling cadence. `active` follows a moving window smoothly; `idle` is a
    /// bounded probe used while the tracked window stays still, so a permanently
    /// visible overlay cannot keep a full 30 Hz loop running all day.
    private let activeSamplingInterval: TimeInterval = 1.0 / 30
    private let idleSamplingInterval: TimeInterval = 1.0 / 8
    private let idleSamplesBeforeBackingOff = 60
    private var currentSamplingInterval: TimeInterval?
    private var idleSamples = 0
    private var lastPublishedFrame: CGRect?

    /// Budgets for the two costly window-server lookups. AX geometry is read on
    /// every sample because it is what moves the overlay; confirming that the
    /// resolved window still exists is limited to twice a second, and the full
    /// on-screen window enumeration needed to resolve a new identity to once a
    /// second. Both ceilings are what stop recovery polling from becoming the
    /// busy loop it is meant to recover from.
    private let presenceCheckInterval: TimeInterval = 0.5
    private let identityResolveInterval: TimeInterval = 1
    private var lastPresenceCheck = Date.distantPast
    private var windowIsPresent = false
    private var lastIdentityResolve = Date.distantPast

    private let applicationNotifications = [
        kAXFocusedWindowChangedNotification, kAXWindowCreatedNotification,
        kAXApplicationHiddenNotification, kAXApplicationShownNotification
    ]
    private let windowNotifications = [
        kAXMovedNotification, kAXResizedNotification, kAXWindowMovedNotification,
        kAXWindowResizedNotification, kAXWindowMiniaturizedNotification,
        kAXWindowDeminiaturizedNotification, kAXUIElementDestroyedNotification
    ]

    func start() {
        guard !running else { return }
        running = true
        let center = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didActivateApplicationNotification, NSWorkspace.didDeactivateApplicationNotification,
                     NSWorkspace.didHideApplicationNotification, NSWorkspace.didUnhideApplicationNotification,
                     NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didTerminateApplicationNotification,
                     NSWorkspace.activeSpaceDidChangeNotification] {
            workspaceTokens.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                self?.refresh()
            })
        }
        screenToken = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in self?.refresh() }
        // Also recovers when permission is granted in Settings, an AX read fails
        // transiently, or the target does not support a particular notification.
        recoveryTimer = makeTimer(interval: 2) { [weak self] in self?.refresh() }
        refresh()
    }

    func stop() {
        running = false
        setContinuousTracking(false)
        recoveryTimer?.invalidate()
        recoveryTimer = nil
        let center = NSWorkspace.shared.notificationCenter
        workspaceTokens.forEach { center.removeObserver($0) }
        workspaceTokens.removeAll()
        if let screenToken { NotificationCenter.default.removeObserver(screenToken) }
        screenToken = nil
        unbindApplication()
    }

    func setContinuousTracking(_ enabled: Bool) {
        if enabled && running {
            guard positionTimer == nil else { return }
            installSamplingTimer(activeSamplingInterval)
        } else {
            positionTimer?.invalidate()
            positionTimer = nil
            currentSamplingInterval = nil
            idleSamples = 0
        }
    }

    private func installSamplingTimer(_ interval: TimeInterval) {
        positionTimer?.invalidate()
        currentSamplingInterval = interval
        positionTimer = makeTimer(interval: interval) { [weak self] in self?.refresh() }
    }

    private func noteSampledFrame(_ frame: CGRect?) {
        guard positionTimer != nil else { return }
        if frame == lastPublishedFrame {
            idleSamples += 1
            if idleSamples == idleSamplesBeforeBackingOff,
               currentSamplingInterval == activeSamplingInterval {
                installSamplingTimer(idleSamplingInterval)
            }
        } else {
            idleSamples = 0
            lastPublishedFrame = frame
            if currentSamplingInterval == idleSamplingInterval {
                installSamplingTimer(activeSamplingInterval)
            }
        }
    }

    func refresh() {
        guard running else { return }
        let trusted = AXIsProcessTrusted()
        // NSScreen.screens.first is the menu-bar display (not the active screen).
        let desktopTop = NSScreen.screens.first?.frame.maxY ?? 0
        var frame: CGRect?
        if trusted, let target = NSWorkspace.shared.frontmostApplication,
           target.bundleIdentifier == "com.openai.codex", !target.isHidden, !target.isTerminated {
            bindApplication(pid: target.processIdentifier)
            if let applicationElement,
               let focused = copyElement(applicationElement, attribute: kAXFocusedWindowAttribute) {
                bindWindow(focused)
                if let candidate = visibleFrame(of: focused) {
                    frame = confirmedFrame(candidate, pid: target.processIdentifier)
                }
            } else {
                unbindWindow()
            }
        } else {
            unbindApplication()
        }
        noteSampledFrame(frame)
        onChange?(FollowEnvironment(accessibilityGranted: trusted, focusedWindowFrame: frame, desktopTop: desktopTop))
    }

    /// Geometry of a focused window that can host the overlay, or nil when it is
    /// minimized, degenerate or not yet on screen.
    private func visibleFrame(of focused: AXUIElement) -> CGRect? {
        var minimized: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(focused, kAXMinimizedAttribute as CFString, &minimized)
        guard result == .success, let isMinimized = minimized as? Bool, !isMinimized else { return nil }
        guard let origin = point(focused), let size = size(focused),
              size.width > 0, size.height > 0,
              origin.x.isFinite, origin.y.isFinite, size.width.isFinite, size.height.isFinite
        else { return nil }
        return CGRect(origin: origin, size: size)
    }

    /// Resolves the AX geometry to a window-server identity, spending as little
    /// as possible: a cached identity is confirmed with a single-window lookup,
    /// and the full window list is only enumerated to find a new identity.
    private func confirmedFrame(_ candidate: CGRect, pid: pid_t) -> CGRect? {
        let now = Date()
        if let tracked = windowIdentity.trackedWindowID {
            if now.timeIntervalSince(lastPresenceCheck) >= presenceCheckInterval {
                lastPresenceCheck = now
                windowIsPresent = windowIsOnScreen(tracked, pid: pid)
                if !windowIsPresent {
                    // The cached id is gone. Resolve again on this sample instead of
                    // leaving the overlay hidden until the next budgeted attempt;
                    // repeated failures stay limited by `identityResolveInterval`.
                    windowIdentity.reset()
                    lastIdentityResolve = .distantPast
                }
            }
            if windowIdentity.trackedWindowID != nil, windowIsPresent { return candidate }
        }
        guard now.timeIntervalSince(lastIdentityResolve) >= identityResolveInterval else { return nil }
        lastIdentityResolve = now
        guard resolveIdentity(candidate, pid: pid) else { return nil }
        windowIsPresent = true
        return candidate
    }

    /// Full enumeration, bounded by `identityResolveInterval`.
    private func resolveIdentity(_ focusedFrame: CGRect, pid: pid_t) -> Bool {
        guard let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
                as? [[String: Any]] else { return false }
        let candidates = windowCandidates(windows, pid: pid)
        return windowIdentity.isVisible(focusedFrame: focusedFrame, windows: candidates)
    }

    /// Single-window lookup, used to confirm a cached identity cheaply. The window
    /// must still be on screen, so a Codex window on an inactive Space never pulls
    /// the all-Spaces overlay onto an empty desktop.
    private func windowIsOnScreen(_ id: CGWindowID, pid: pid_t) -> Bool {
        guard let info = CGWindowListCopyWindowInfo([.optionIncludingWindow], id) as? [[String: Any]],
              let window = info.first else { return false }
        guard (window[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value == pid,
              (window[kCGWindowLayer as String] as? NSNumber)?.intValue == 0
        else { return false }
        return (window[kCGWindowIsOnscreen as String] as? Bool) ?? true
    }

    private func windowCandidates(_ windows: [[String: Any]], pid: pid_t) -> [FollowWindowCandidate] {
        windows.compactMap { window in
            guard
                (window[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value == pid,
                (window[kCGWindowLayer as String] as? NSNumber)?.intValue == 0,
                let bounds = window[kCGWindowBounds as String] as? [String: Any],
                let number = window[kCGWindowNumber as String] as? NSNumber
            else { return nil }
            var candidate = CGRect.zero
            guard CGRectMakeWithDictionaryRepresentation(bounds as CFDictionary, &candidate) else { return nil }
            return FollowWindowCandidate(id: number.uint32Value, frame: candidate)
        }
    }

    private func makeTimer(interval: TimeInterval, action: @escaping () -> Void) -> Timer {
        let timer = Timer(timeInterval: interval, repeats: true) { _ in action() }
        timer.tolerance = interval * 0.1
        // Continue tracking during mouse dragging and menu/event tracking modes.
        RunLoop.main.add(timer, forMode: .common)
        return timer
    }

    private func bindApplication(pid: pid_t) {
        guard observedPID != pid else { return }
        unbindApplication()
        observedPID = pid
        let element = AXUIElementCreateApplication(pid)
        // A hung target must not stall the main run loop for AX's default timeout.
        AXUIElementSetMessagingTimeout(element, 0.05)
        applicationElement = element
        var newObserver: AXObserver?
        let result = AXObserverCreate(pid, { _, _, _, context in
            guard let context else { return }
            let tracker = Unmanaged<CodexWindowTracker>.fromOpaque(context).takeUnretainedValue()
            tracker.refresh()
        }, &newObserver)
        guard result == .success, let newObserver else { return }
        observer = newObserver
        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(newObserver), .commonModes)
        for name in applicationNotifications { addNotification(name, element: element) }
    }

    private func bindWindow(_ element: AXUIElement) {
        if let windowElement, CFEqual(windowElement, element) { return }
        unbindWindow()
        windowElement = element
        AXUIElementSetMessagingTimeout(element, 0.05)
        for name in windowNotifications { addNotification(name, element: element) }
    }

    private func unbindWindow() {
        if let observer, let windowElement {
            for name in windowNotifications {
                AXObserverRemoveNotification(observer, windowElement, name as CFString)
            }
        }
        windowElement = nil
        resetIdentityState()
    }

    /// Drops cached identity and its budgets so the next bind resolves from scratch.
    private func resetIdentityState() {
        windowIdentity.reset()
        windowIsPresent = false
        lastPresenceCheck = .distantPast
        lastIdentityResolve = .distantPast
        lastPublishedFrame = nil
    }

    private func unbindApplication() {
        unbindWindow()
        if let observer {
            if let applicationElement {
                for name in applicationNotifications {
                    AXObserverRemoveNotification(observer, applicationElement, name as CFString)
                }
            }
            CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .commonModes)
        }
        observer = nil
        applicationElement = nil
        observedPID = nil
    }

    private func addNotification(_ name: String, element: AXUIElement) {
        guard let observer else { return }
        // Unsupported events are covered by bounded visible sampling / recovery.
        AXObserverAddNotification(observer, element, name as CFString, Unmanaged.passUnretained(self).toOpaque())
    }

    private func copyElement(_ source: AXUIElement, attribute: String) -> AXUIElement? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(source, attribute as CFString, &value) == .success,
              let value, CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return (value as! AXUIElement)
    }

    private func point(_ element: AXUIElement) -> CGPoint? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &value) == .success,
              let value, CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
        let ax = value as! AXValue
        guard AXValueGetType(ax) == .cgPoint else { return nil }
        var point = CGPoint.zero
        return AXValueGetValue(ax, .cgPoint, &point) ? point : nil
    }

    private func size(_ element: AXUIElement) -> CGSize? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &value) == .success,
              let value, CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
        let ax = value as! AXValue
        guard AXValueGetType(ax) == .cgSize else { return nil }
        var size = CGSize.zero
        return AXValueGetValue(ax, .cgSize, &size) ? size : nil
    }
}

struct FollowWindowCandidate {
    let id: CGWindowID
    let frame: CGRect
}

/// Resolve AX geometry to window-server identity without reading window titles.
struct FollowWindowIdentityResolver {
    private var windowID: CGWindowID?

    /// Identity currently tracked, if a window-server window has been resolved.
    var trackedWindowID: CGWindowID? { windowID }

    mutating func reset() { windowID = nil }

    mutating func isVisible(focusedFrame: CGRect, windows: [FollowWindowCandidate]) -> Bool {
        if let windowID, windows.contains(where: { $0.id == windowID }) { return true }
        // A window-server ID can be replaced without changing the AX element.
        // Discard a missing ID so recovery polls can resolve the target again.
        windowID = nil
        let matches = windows.filter {
            abs($0.frame.minX - focusedFrame.minX) <= 4 && abs($0.frame.minY - focusedFrame.minY) <= 4 &&
            abs($0.frame.width - focusedFrame.width) <= 4 && abs($0.frame.height - focusedFrame.height) <= 4
        }
        // Geometry is the only cross-API identity available here. Do not guess
        // between overlapping same-sized windows when resolving a new ID.
        guard matches.count == 1, let match = matches.first else { return false }
        windowID = match.id
        return true
    }
}
