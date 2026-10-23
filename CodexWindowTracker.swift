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
            positionTimer = makeTimer(interval: 1.0 / 30) { [weak self] in self?.refresh() }
        } else {
            positionTimer?.invalidate()
            positionTimer = nil
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
                var minimized: CFTypeRef?
                let result = AXUIElementCopyAttributeValue(focused, kAXMinimizedAttribute as CFString, &minimized)
                if result == .success, let isMinimized = minimized as? Bool, !isMinimized,
                   let origin = point(focused), let size = size(focused),
                   size.width > 0, size.height > 0,
                   isOnActiveSpace(frame: CGRect(origin: origin, size: size), pid: target.processIdentifier) {
                    frame = CGRect(origin: origin, size: size)
                }
            } else {
                unbindWindow()
            }
        } else {
            unbindApplication()
        }
        onChange?(FollowEnvironment(accessibilityGranted: trusted, focusedWindowFrame: frame, desktopTop: desktopTop))
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
        windowIdentity.reset()
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

    private func isOnActiveSpace(frame: CGRect, pid: pid_t) -> Bool {
        // An app may stay frontmost while its AX focused window belongs to an
        // inactive Space. Window-server metadata prevents the all-Spaces panel
        // from appearing on that empty desktop. No pixels or window titles read.
        guard let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
                as? [[String: Any]] else { return false }
        let candidates = windows.filter {
            ($0[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value == pid &&
            ($0[kCGWindowLayer as String] as? NSNumber)?.intValue == 0
        }
        let visibleWindows: [FollowWindowCandidate] = candidates.compactMap { window in
            guard let bounds = window[kCGWindowBounds as String] as? [String: Any],
                  let number = window[kCGWindowNumber as String] as? NSNumber else { return nil }
            var candidate = CGRect.zero
            guard CGRectMakeWithDictionaryRepresentation(bounds as CFDictionary, &candidate) else { return nil }
            return FollowWindowCandidate(id: number.uint32Value, frame: candidate)
        }
        return windowIdentity.isVisible(focusedFrame: frame, windows: visibleWindows)
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
