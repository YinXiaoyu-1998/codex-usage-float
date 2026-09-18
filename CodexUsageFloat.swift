import Cocoa

struct LimitWindow {
    let title: String
    let usedPercent: Int
    let windowDurationMins: Int?
    let resetsAt: Int64?

    var remainingPercent: Int {
        max(0, min(100, 100 - usedPercent))
    }
}

struct UsageSnapshot {
    let fiveHour: LimitWindow?
    let weekly: LimitWindow?
    let resetCredits: Int?
    let planType: String?
    let updatedAt: Date
    let status: String

    var hasUsageData: Bool {
        fiveHour != nil || weekly != nil
    }
}

final class UsageView: NSView {
    var requestHide: (() -> Void)?
    private let headerCenterY: CGFloat = 41
    private let trafficLightDiameter: CGFloat = 12
    private let trafficLightLeftX: CGFloat = 18
    private let trafficLightSpacing: CGFloat = 20

    var snapshot = UsageSnapshot(
        fiveHour: nil,
        weekly: nil,
        resetCredits: nil,
        planType: nil,
        updatedAt: Date(),
        status: "Connecting..."
    ) {
        didSet { needsDisplay = true }
    }

    override var isFlipped: Bool { true }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        let closeRect = trafficLightRect(index: 0).insetBy(dx: -4, dy: -4)
        let minimizeRect = trafficLightRect(index: 1).insetBy(dx: -4, dy: -4)

        if closeRect.contains(point) {
            NSApp.terminate(nil)
            return
        }
        if minimizeRect.contains(point) {
            requestHide?()
            return
        }
        super.mouseDown(with: event)
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        let bounds = self.bounds
        NSColor.clear.setFill()
        bounds.fill()

        drawGlassBackground(in: bounds)
        drawHeader()

        let cards = usageCards()
        if cards.isEmpty {
            drawWindow(nil, in: CGRect(x: 18, y: 78, width: bounds.width - 36, height: 88), icon: .clock)
        } else {
            for (index, card) in cards.enumerated() {
                let y = CGFloat(78 + index * 102)
                drawWindow(card.window, in: CGRect(x: 18, y: y, width: bounds.width - 36, height: 88), icon: card.icon)
            }
        }
        drawFooter()
    }

    private enum LimitIcon {
        case clock
        case calendar
    }

    private func usageCards() -> [(window: LimitWindow, icon: LimitIcon)] {
        var cards: [(LimitWindow, LimitIcon)] = []
        if let fiveHour = snapshot.fiveHour {
            cards.append((fiveHour, .clock))
        }
        if let weekly = snapshot.weekly {
            cards.append((weekly, .calendar))
        }
        return cards
    }

    private func drawGlassBackground(in rect: CGRect) {
        let background = NSBezierPath(roundedRect: rect, xRadius: 18, yRadius: 18)
        NSColor(calibratedWhite: 1.0, alpha: 0.30).setFill()
        background.fill()
    }

    private func drawHeader() {
        drawTrafficLights()

        drawText(
            "Codex Usage",
            rect: CGRect(x: 88, y: headerCenterY - 17, width: bounds.width - 170, height: 34),
            size: 24,
            weight: .bold,
            color: NSColor(calibratedRed: 0.05, green: 0.08, blue: 0.25, alpha: 1)
        )

        let plan = displayPlanName(snapshot.planType)
        let badgeWidth = max(CGFloat(54), textWidth(plan, size: 12, weight: .semibold) + 22)
        let badgeRect = CGRect(x: bounds.width - badgeWidth - 26, y: headerCenterY - 12, width: badgeWidth, height: 24)
        let badge = NSBezierPath(roundedRect: badgeRect, xRadius: 8, yRadius: 8)
        NSGradient(colors: [
            NSColor(calibratedRed: 0.43, green: 0.53, blue: 0.98, alpha: 0.92),
            NSColor(calibratedRed: 0.36, green: 0.40, blue: 0.90, alpha: 0.92)
        ])?.draw(in: badge, angle: 90)
        drawText(
            plan,
            rect: badgeRect.insetBy(dx: 8, dy: 4),
            size: 12,
            weight: .semibold,
            color: .white,
            alignment: .center
        )
    }

    private func displayPlanName(_ rawPlanType: String?) -> String {
        guard let rawPlanType else { return "LOCAL" }
        switch rawPlanType.lowercased() {
        case "free":
            return "FREE"
        case "plus":
            return "PLUS"
        case "prolite":
            return "PRO 5X"
        case "pro":
            return "PRO 20X"
        default:
            return rawPlanType.replacingOccurrences(of: "_", with: " ").uppercased()
        }
    }

    private func textWidth(_ text: String, size: CGFloat, weight: NSFont.Weight) -> CGFloat {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: size, weight: weight)
        ]
        return ceil((text as NSString).size(withAttributes: attributes).width)
    }

    private func trafficLightRect(index: Int) -> CGRect {
        CGRect(
            x: trafficLightLeftX + CGFloat(index) * trafficLightSpacing,
            y: headerCenterY - trafficLightDiameter / 2,
            width: trafficLightDiameter,
            height: trafficLightDiameter
        )
    }

    private func drawTrafficLights() {
        let colors = [
            NSColor(calibratedRed: 1.0, green: 0.37, blue: 0.34, alpha: 1),
            NSColor(calibratedRed: 1.0, green: 0.73, blue: 0.20, alpha: 1),
            NSColor(calibratedRed: 0.18, green: 0.82, blue: 0.32, alpha: 1)
        ]
        for (index, color) in colors.enumerated() {
            let rect = trafficLightRect(index: index)
            let dot = NSBezierPath(ovalIn: rect)
            color.setFill()
            dot.fill()
            NSColor(calibratedWhite: 0.0, alpha: 0.08).setStroke()
            dot.lineWidth = 0.5
            dot.stroke()
        }
    }

    private func drawWindow(_ limit: LimitWindow?, in rect: CGRect, icon: LimitIcon) {
        let panel = NSBezierPath(roundedRect: rect, xRadius: 12, yRadius: 12)
        NSGradient(colors: [
            NSColor(calibratedRed: 0.04, green: 0.08, blue: 0.28, alpha: 0.96),
            NSColor(calibratedRed: 0.02, green: 0.04, blue: 0.18, alpha: 0.98)
        ])?.draw(in: panel, angle: -20)

        NSColor(calibratedRed: 0.53, green: 0.67, blue: 1.0, alpha: 0.42).setStroke()
        panel.lineWidth = 1
        panel.stroke()

        drawIcon(icon, in: CGRect(x: rect.minX + 16, y: rect.minY + 14, width: 42, height: 42))

        guard let limit else {
            drawText(
                snapshot.status,
                rect: CGRect(x: rect.minX + 72, y: rect.minY + 24, width: rect.width - 92, height: 24),
                size: 12,
                weight: .medium,
                color: NSColor(calibratedWhite: 0.88, alpha: 1)
            )
            return
        }

        let isWeekly = limit.title == "Weekly"
        let titleWidth: CGFloat = isWeekly ? 118 : 54
        let percentX = rect.minX + (isWeekly ? 178 : 134)
        let title = limit.title
        drawText(
            title,
            rect: CGRect(x: rect.minX + 74, y: rect.minY + 16, width: titleWidth, height: 30),
            size: 26,
            weight: .bold,
            color: .white
        )

        drawText(
            "\(limit.remainingPercent)% left",
            rect: CGRect(x: percentX, y: rect.minY + 18, width: 130, height: 30),
            size: 25,
            weight: .bold,
            color: NSColor(calibratedRed: 0.43, green: 0.82, blue: 1.0, alpha: 1)
        )

        drawText(
            "used \(limit.usedPercent)%",
            rect: CGRect(x: rect.maxX - 86, y: rect.minY + 21, width: 68, height: 18),
            size: 13,
            weight: .medium,
            color: NSColor(calibratedRed: 0.73, green: 0.76, blue: 0.98, alpha: 1),
            alignment: .right
        )

        let resetRect = CGRect(x: rect.minX + 74, y: rect.minY + 47, width: rect.width - 92, height: 14)
        drawText(
            resetText(for: limit),
            rect: resetRect,
            size: 13,
            weight: .medium,
            color: NSColor(calibratedRed: 0.72, green: 0.76, blue: 0.98, alpha: 0.95)
        )

        drawSegmentBar(
            percent: limit.remainingPercent,
            rect: CGRect(x: rect.minX + 16, y: resetRect.maxY + 10, width: rect.width - 32, height: 10)
        )
    }

    private func drawIcon(_ icon: LimitIcon, in rect: CGRect) {
        let box = NSBezierPath(roundedRect: rect, xRadius: 11, yRadius: 11)
        NSGradient(colors: [
            NSColor(calibratedRed: 0.33, green: 0.39, blue: 0.92, alpha: 1),
            NSColor(calibratedRed: 0.20, green: 0.17, blue: 0.70, alpha: 1)
        ])?.draw(in: box, angle: -40)
        NSColor(calibratedRed: 0.62, green: 0.72, blue: 1.0, alpha: 0.55).setStroke()
        box.lineWidth = 1
        box.stroke()

        NSColor.white.withAlphaComponent(0.94).setStroke()
        switch icon {
        case .clock:
            let dial = NSBezierPath(ovalIn: rect.insetBy(dx: 12, dy: 10))
            dial.lineWidth = 2.2
            dial.stroke()
            let center = CGPoint(x: rect.midX, y: rect.midY)
            let hands = NSBezierPath()
            hands.lineWidth = 2.2
            hands.lineCapStyle = .round
            hands.move(to: center)
            hands.line(to: CGPoint(x: center.x, y: center.y - 8))
            hands.move(to: center)
            hands.line(to: CGPoint(x: center.x + 8, y: center.y))
            hands.stroke()
        case .calendar:
            let cal = NSBezierPath(roundedRect: rect.insetBy(dx: 11, dy: 10), xRadius: 3, yRadius: 3)
            cal.lineWidth = 2.2
            cal.stroke()
            let top = NSBezierPath()
            top.lineWidth = 2.2
            top.move(to: CGPoint(x: rect.minX + 13, y: rect.minY + 20))
            top.line(to: CGPoint(x: rect.maxX - 13, y: rect.minY + 20))
            top.move(to: CGPoint(x: rect.minX + 18, y: rect.minY + 9))
            top.line(to: CGPoint(x: rect.minX + 18, y: rect.minY + 15))
            top.move(to: CGPoint(x: rect.maxX - 18, y: rect.minY + 9))
            top.line(to: CGPoint(x: rect.maxX - 18, y: rect.minY + 15))
            top.stroke()
            NSColor.white.withAlphaComponent(0.9).setFill()
            for row in 0..<2 {
                for col in 0..<3 {
                    CGRect(x: rect.minX + 16 + CGFloat(col) * 6, y: rect.minY + 25 + CGFloat(row) * 6, width: 2.5, height: 2.5).fill()
                }
            }
        }
    }

    private func drawSegmentBar(percent: Int, rect: CGRect) {
        let gap: CGFloat = 3
        let segmentWidth = (rect.width - gap * 9) / 10
        let filled = Int(ceil(Double(max(0, min(100, percent))) / 10.0))

        for index in 0..<10 {
            let segmentRect = CGRect(
                x: rect.minX + CGFloat(index) * (segmentWidth + gap),
                y: rect.minY,
                width: segmentWidth,
                height: rect.height
            )
            let path = NSBezierPath(roundedRect: segmentRect, xRadius: 2, yRadius: 2)
            if index < filled {
                NSGradient(colors: [
                    NSColor(calibratedRed: 0.05, green: 0.65, blue: 1.0, alpha: 1),
                    NSColor(calibratedRed: 0.09, green: 0.83, blue: 1.0, alpha: 1)
                ])?.draw(in: path, angle: 90)
            } else {
                NSColor(calibratedRed: 0.16, green: 0.21, blue: 0.38, alpha: 1).setFill()
                path.fill()
            }
        }
    }

    private func drawFooter() {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        let updated = formatter.string(from: snapshot.updatedAt)
        let credits = snapshot.resetCredits.map { "reset credits \($0)" } ?? "reset credits -"
        let footerRect = CGRect(x: 18, y: bounds.height - 46, width: bounds.width - 36, height: 30)
        let footerPath = NSBezierPath(roundedRect: footerRect, xRadius: 10, yRadius: 10)
        NSColor(calibratedRed: 0.76, green: 0.82, blue: 1.0, alpha: 0.32).setFill()
        footerPath.fill()
        NSColor(calibratedWhite: 1.0, alpha: 0.42).setStroke()
        footerPath.lineWidth = 1
        footerPath.stroke()

        drawText(
            credits,
            rect: CGRect(x: footerRect.minX + 24, y: footerRect.minY + 7, width: 142, height: 14),
            size: 12,
            weight: .medium,
            color: NSColor(calibratedRed: 0.18, green: 0.22, blue: 0.62, alpha: 1)
        )

        drawText(
            "•  updated \(updated)",
            rect: CGRect(x: footerRect.minX + 178, y: footerRect.minY + 7, width: footerRect.width - 196, height: 14),
            size: 12,
            weight: .medium,
            color: NSColor(calibratedRed: 0.18, green: 0.22, blue: 0.62, alpha: 1)
        )
    }

    private func resetText(for limit: LimitWindow) -> String {
        guard let resetsAt = limit.resetsAt else {
            return "reset at -"
        }

        let date = Date(timeIntervalSince1970: TimeInterval(resetsAt))
        let calendar = Calendar.current
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")

        if calendar.isDateInToday(date) {
            formatter.dateFormat = "HH:mm"
            return "reset at \(formatter.string(from: date))"
        }

        formatter.dateFormat = "MMM d HH:mm"
        return "reset at \(formatter.string(from: date))"
    }

    private func drawText(
        _ text: String,
        rect: CGRect,
        size: CGFloat,
        weight: NSFont.Weight,
        color: NSColor,
        alignment: NSTextAlignment = .left
    ) {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = alignment
        paragraph.lineBreakMode = .byTruncatingTail
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: size, weight: weight),
            .foregroundColor: color,
            .paragraphStyle: paragraph
        ]
        text.draw(in: rect, withAttributes: attributes)
    }
}

final class CodexUsageClient {
    private let onSnapshot: (UsageSnapshot) -> Void
    private var process: Process?
    private var stdinHandle: FileHandle?
    private var stdoutBuffer = Data()
    private var nextId = 1
    private var initialized = false
    private var startedAt: Date?
    private var restartPending = false
    private var rateLimitReadPending = false
    private var rateLimitReadStartedAt: Date?
    private var lastSnapshot: UsageSnapshot?

    init(onSnapshot: @escaping (UsageSnapshot) -> Void) {
        self.onSnapshot = onSnapshot
    }

    func start() {
        guard process == nil else { return }

        let process = Process()
        if FileManager.default.fileExists(atPath: "/Applications/ChatGPT.app/Contents/Resources/codex") {
            process.executableURL = URL(fileURLWithPath: "/Applications/ChatGPT.app/Contents/Resources/codex")
            process.arguments = ["app-server", "--stdio"]
        } else {
            process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            process.arguments = ["codex", "app-server", "--stdio"]
        }

        let input = Pipe()
        let output = Pipe()
        let error = Pipe()
        process.standardInput = input
        process.standardOutput = output
        process.standardError = error
        self.stdinHandle = input.fileHandleForWriting
        self.process = process
        self.initialized = false
        self.startedAt = Date()

        output.fileHandleForReading.readabilityHandler = { [weak self] handle in
            self?.consume(handle.availableData)
        }
        error.fileHandleForReading.readabilityHandler = { _ in }
        process.terminationHandler = { [weak self] _ in
            DispatchQueue.main.async {
                self?.handleExit()
            }
        }

        do {
            try process.run()
            initialize()
        } catch {
            publishError("Cannot start codex app-server")
            scheduleRestart()
        }
    }

    func stop() {
        process?.terminate()
        process = nil
        stdinHandle = nil
        initialized = false
        startedAt = nil
        rateLimitReadPending = false
        rateLimitReadStartedAt = nil
    }

    func poll() {
        if process == nil {
            start()
            return
        }
        if initializeTimedOut {
            restartAppServer(reason: "Waiting for Codex. Reconnecting...")
            return
        }
        if rateLimitReadTimedOut {
            restartAppServer(reason: "Read timed out. Reconnecting...")
            return
        }
        guard initialized else { return }
        requestRateLimits()
    }

    private func initialize() {
        let params: [String: Any] = [
            "clientInfo": [
                "name": "codex-usage-float",
                "title": "Codex Usage Float",
                "version": "0.1.0"
            ],
            "capabilities": [
                "experimentalApi": true,
                "requestAttestation": false,
                "optOutNotificationMethods": ["thread/tokenUsage/updated"]
            ]
        ]
        send(method: "initialize", params: params)
    }

    private func send(method: String, params: Any? = nil) {
        guard let stdinHandle else { return }
        var request: [String: Any] = [
            "id": nextId,
            "method": method
        ]
        nextId += 1
        if let params {
            request["params"] = params
        }

        do {
            let data = try JSONSerialization.data(withJSONObject: request, options: [])
            if let line = String(data: data, encoding: .utf8)?.appending("\n").data(using: .utf8) {
                stdinHandle.write(line)
            }
        } catch {
            publishError("Cannot encode request")
        }
    }

    private func consume(_ data: Data) {
        guard !data.isEmpty else { return }
        stdoutBuffer.append(data)

        while let newline = stdoutBuffer.firstIndex(of: 10) {
            let lineData = stdoutBuffer.subdata(in: 0..<newline)
            stdoutBuffer.removeSubrange(0...newline)
            guard !lineData.isEmpty else { continue }
            handleLine(lineData)
        }
    }

    private func handleLine(_ data: Data) {
        guard
            let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return }

        if let result = object["result"] as? [String: Any] {
            if result["userAgent"] != nil {
                initialized = true
                startedAt = nil
                requestRateLimits()
                return
            }
            rateLimitReadPending = false
            rateLimitReadStartedAt = nil
            if let snapshot = parseRateLimitResult(result) {
                guard shouldAccept(snapshot) else {
                    requestRateLimits(after: 2)
                    return
                }
                lastSnapshot = snapshot
                DispatchQueue.main.async {
                    self.onSnapshot(snapshot)
                }
            }
            return
        }

        if
            let method = object["method"] as? String,
            method == "account/rateLimits/updated"
        {
            requestRateLimits()
        }
    }

    private func requestRateLimits() {
        guard initialized else { return }
        if rateLimitReadTimedOut {
            restartAppServer(reason: "Read timed out. Reconnecting...")
            return
        }
        guard !rateLimitReadPending else { return }
        rateLimitReadPending = true
        rateLimitReadStartedAt = Date()
        send(method: "account/rateLimits/read")
    }

    private func requestRateLimits(after delay: TimeInterval) {
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            self.requestRateLimits()
        }
    }

    private var rateLimitReadTimedOut: Bool {
        guard rateLimitReadPending, let rateLimitReadStartedAt else { return false }
        return Date().timeIntervalSince(rateLimitReadStartedAt) > 15
    }

    private var initializeTimedOut: Bool {
        guard !initialized, let startedAt else { return false }
        return Date().timeIntervalSince(startedAt) > 15
    }

    private func shouldAccept(_ snapshot: UsageSnapshot) -> Bool {
        guard let previous = lastSnapshot else { return true }

        let resetCreditsDropped: Bool
        if let oldCredits = previous.resetCredits, let newCredits = snapshot.resetCredits {
            resetCreditsDropped = newCredits < oldCredits
        } else {
            resetCreditsDropped = false
        }
        if resetCreditsDropped { return true }

        let now = Int64(Date().timeIntervalSince1970)
        let fiveHourOk = windowLooksStable(old: previous.fiveHour, new: snapshot.fiveHour, now: now)
        let weeklyOk = windowLooksStable(old: previous.weekly, new: snapshot.weekly, now: now)
        return fiveHourOk && weeklyOk
    }

    private func windowLooksStable(old: LimitWindow?, new: LimitWindow?, now: Int64) -> Bool {
        guard let old, let new else { return true }
        guard let oldReset = old.resetsAt else { return true }

        let resetIsDue = now >= oldReset - 60
        if resetIsDue { return true }

        let resetTimeChanged = old.resetsAt != new.resetsAt
        let usedDroppedSharply = old.usedPercent - new.usedPercent >= 25
        let jumpedToNearFull = old.remainingPercent <= 75 && new.remainingPercent >= 90

        if !resetTimeChanged && (usedDroppedSharply || jumpedToNearFull) {
            return false
        }
        return true
    }

    private func parseRateLimitResult(_ result: [String: Any]) -> UsageSnapshot? {
        var rateLimits: [String: Any]?
        if
            let byId = result["rateLimitsByLimitId"] as? [String: Any],
            let codex = byId["codex"] as? [String: Any]
        {
            rateLimits = codex
        } else {
            rateLimits = result["rateLimits"] as? [String: Any]
        }

        guard let rateLimits else { return nil }
        let resetCredits = (result["rateLimitResetCredits"] as? [String: Any])?["availableCount"] as? Int
        return makeSnapshot(rateLimits: rateLimits, resetCredits: resetCredits)
    }

    private func makeSnapshot(rateLimits: [String: Any], resetCredits: Int?) -> UsageSnapshot {
        let primary = parseWindow(rateLimits["primary"] as? [String: Any], fallbackTitle: "5H")
        let secondary = parseWindow(rateLimits["secondary"] as? [String: Any], fallbackTitle: "Weekly")
        let windows = [primary, secondary].compactMap { $0 }

        let fiveHour = windows.first { $0.windowDurationMins == 300 }
        let weekly = windows.first { $0.windowDurationMins == 10080 }
        let planType = rateLimits["planType"] as? String

        return UsageSnapshot(
            fiveHour: fiveHour.map { LimitWindow(title: "5H", usedPercent: $0.usedPercent, windowDurationMins: $0.windowDurationMins, resetsAt: $0.resetsAt) },
            weekly: weekly.map { LimitWindow(title: "Weekly", usedPercent: $0.usedPercent, windowDurationMins: $0.windowDurationMins, resetsAt: $0.resetsAt) },
            resetCredits: resetCredits,
            planType: planType,
            updatedAt: Date(),
            status: "OK"
        )
    }

    private func parseWindow(_ dictionary: [String: Any]?, fallbackTitle: String) -> LimitWindow? {
        guard let dictionary else { return nil }
        let used = intValue(dictionary["usedPercent"]) ?? 0
        return LimitWindow(
            title: fallbackTitle,
            usedPercent: max(0, min(100, used)),
            windowDurationMins: intValue(dictionary["windowDurationMins"]),
            resetsAt: int64Value(dictionary["resetsAt"])
        )
    }

    private func intValue(_ value: Any?) -> Int? {
        if let value = value as? Int { return value }
        if let value = value as? NSNumber { return value.intValue }
        return nil
    }

    private func int64Value(_ value: Any?) -> Int64? {
        if let value = value as? Int64 { return value }
        if let value = value as? Int { return Int64(value) }
        if let value = value as? NSNumber { return value.int64Value }
        return nil
    }

    private func publishError(_ message: String) {
        DispatchQueue.main.async {
            self.onSnapshot(UsageSnapshot(
                fiveHour: nil,
                weekly: nil,
                resetCredits: nil,
                planType: nil,
                updatedAt: Date(),
                status: message
            ))
        }
    }

    private func handleExit() {
        process = nil
        stdinHandle = nil
        initialized = false
        startedAt = nil
        rateLimitReadPending = false
        rateLimitReadStartedAt = nil
        publishError("Disconnected. Reconnecting...")
        scheduleRestart()
    }

    private func restartAppServer(reason: String) {
        rateLimitReadPending = false
        rateLimitReadStartedAt = nil
        initialized = false
        startedAt = nil
        publishError(reason)
        process?.terminationHandler = nil
        process?.terminate()
        process = nil
        stdinHandle = nil
        scheduleRestart()
    }

    private func scheduleRestart() {
        guard !restartPending else { return }
        restartPending = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            self.restartPending = false
            self.start()
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let windowWidth: CGFloat = 480
    private let fullWindowHeight: CGFloat = 332
    private let compactWindowHeight: CGFloat = 218
    private let compactStatusItemWidthThreshold: CGFloat = 1700
    private var window: NSWindow!
    private var usageView: UsageView!
    private var client: CodexUsageClient!
    private var timer: Timer?
    private var statusItem: NSStatusItem!
    private var latestSnapshot: UsageSnapshot?
    private let statusIcon: NSImage? = {
        let candidates: [URL?] = [
            Bundle.main.url(forResource: "openai-codex-seeklogo", withExtension: "svg"),
            Bundle.main.url(forResource: "codex_logo", withExtension: "svg"),
            Bundle.main.url(forResource: "codex-logo", withExtension: "png")
        ]

        for candidate in candidates {
            guard let url = candidate, let image = NSImage(contentsOf: url) else { continue }
            image.size = NSSize(width: 18, height: 18)
            image.isTemplate = true
            return image
        }
        return NSImage(systemSymbolName: "terminal.fill", accessibilityDescription: "Codex Usage")
    }()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        let windowSize = CGSize(width: windowWidth, height: fullWindowHeight)
        usageView = UsageView(frame: CGRect(origin: .zero, size: windowSize))
        usageView.autoresizingMask = [.width, .height]
        usageView.requestHide = { [weak self] in
            self?.hideWindow()
        }

        let visualEffectView = NSVisualEffectView(frame: CGRect(origin: .zero, size: windowSize))
        visualEffectView.autoresizingMask = [.width, .height]
        visualEffectView.blendingMode = .withinWindow
        visualEffectView.material = .popover
        visualEffectView.state = .active
        visualEffectView.wantsLayer = true
        visualEffectView.layer?.cornerRadius = 18
        visualEffectView.layer?.masksToBounds = true
        visualEffectView.layer?.backgroundColor = NSColor(calibratedWhite: 1.0, alpha: 0.16).cgColor
        visualEffectView.addSubview(usageView)

        window = NSWindow(
            contentRect: CGRect(origin: .zero, size: windowSize),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.title = "Codex Usage"
        window.contentView = visualEffectView
        window.isMovableByWindowBackground = true
        window.level = .floating
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.backgroundColor = .clear
        window.isOpaque = false
        window.hasShadow = false
        window.isReleasedWhenClosed = false
        window.delegate = self

        if let screen = NSScreen.main?.visibleFrame {
            let x = screen.maxX - window.frame.width - 24
            let y = screen.maxY - window.frame.height - 24
            window.setFrameOrigin(CGPoint(x: x, y: y))
        }
        window.makeKeyAndOrderFront(nil)
        setupStatusItem()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(screenParametersDidChange),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )

        client = CodexUsageClient { [weak self] snapshot in
            self?.usageView.snapshot = snapshot
            self?.latestSnapshot = snapshot
            self?.updateStatusItem(snapshot)
            self?.resizeWindow(for: snapshot)
        }
        client.start()

        timer = Timer.scheduledTimer(withTimeInterval: 10, repeats: true) { [weak self] _ in
            self?.client.poll()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        timer?.invalidate()
        client?.stop()
        NotificationCenter.default.removeObserver(self)
    }

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.target = self
            button.action = #selector(toggleWindowFromStatusItem)
            button.imageScaling = .scaleProportionallyDown
        }
        applyStatusItem(snapshot: nil)
    }

    private func updateStatusItem(_ snapshot: UsageSnapshot) {
        applyStatusItem(snapshot: snapshot)
    }

    private func applyStatusItem(snapshot: UsageSnapshot?) {
        guard let button = statusItem.button else { return }
        let compact = shouldUseCompactStatusItem()
        statusItem.length = compact ? NSStatusItem.squareLength : NSStatusItem.variableLength

        if compact {
            button.title = ""
            button.image = statusIcon
            button.imagePosition = .imageOnly
        } else {
            button.image = nil
            button.imagePosition = .noImage
            button.title = statusTitle(for: snapshot)
        }

        button.toolTip = statusTooltip(for: snapshot)
    }

    private func shouldUseCompactStatusItem() -> Bool {
        let width = NSScreen.main?.frame.width ?? NSScreen.screens.first?.frame.width ?? 0
        return width > 0 && width < compactStatusItemWidthThreshold
    }

    private func statusTitle(for snapshot: UsageSnapshot?) -> String {
        guard let snapshot else { return "Codex ..." }
        if let fiveHour = snapshot.fiveHour, let weekly = snapshot.weekly {
            return "Codex Usage 5H \(fiveHour.remainingPercent)% · W \(weekly.remainingPercent)%"
        } else if let weekly = snapshot.weekly {
            return "Codex Usage W \(weekly.remainingPercent)%"
        } else if let fiveHour = snapshot.fiveHour {
            return "Codex Usage 5H \(fiveHour.remainingPercent)%"
        }
        return "Codex ..."
    }

    private func statusTooltip(for snapshot: UsageSnapshot?) -> String {
        guard let snapshot else {
            return "Codex Usage\nConnecting...\nClick to show or hide the window."
        }

        var lines = ["Codex Usage"]
        if let fiveHour = snapshot.fiveHour {
            lines.append(tooltipLine(label: "5H", window: fiveHour))
        }
        if let weekly = snapshot.weekly {
            lines.append(tooltipLine(label: "Weekly", window: weekly))
        }
        if !snapshot.hasUsageData {
            lines.append(snapshot.status)
        }

        lines.append("Plan \(displayPlanName(snapshot.planType))")
        lines.append("Reset credits \(snapshot.resetCredits.map(String.init) ?? "-")")

        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        lines.append("Updated \(formatter.string(from: snapshot.updatedAt))")
        lines.append("Click to show or hide the window.")
        return lines.joined(separator: "\n")
    }

    private func tooltipLine(label: String, window: LimitWindow) -> String {
        "\(label) \(window.remainingPercent)% left, used \(window.usedPercent)%, \(resetText(for: window))"
    }

    private func resetText(for limit: LimitWindow) -> String {
        guard let resetsAt = limit.resetsAt else {
            return "reset at -"
        }

        let date = Date(timeIntervalSince1970: TimeInterval(resetsAt))
        let calendar = Calendar.current
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")

        if calendar.isDateInToday(date) {
            formatter.dateFormat = "HH:mm"
            return "reset at \(formatter.string(from: date))"
        }

        formatter.dateFormat = "MMM d HH:mm"
        return "reset at \(formatter.string(from: date))"
    }

    private func displayPlanName(_ rawPlanType: String?) -> String {
        guard let rawPlanType else { return "LOCAL" }
        switch rawPlanType.lowercased() {
        case "free":
            return "FREE"
        case "plus":
            return "PLUS"
        case "prolite":
            return "PRO 5X"
        case "pro":
            return "PRO 20X"
        default:
            return rawPlanType.replacingOccurrences(of: "_", with: " ").uppercased()
        }
    }

    @objc private func screenParametersDidChange() {
        applyStatusItem(snapshot: latestSnapshot)
    }

    private func resizeWindow(for snapshot: UsageSnapshot) {
        guard snapshot.hasUsageData else { return }
        let targetHeight = snapshot.fiveHour == nil || snapshot.weekly == nil ? compactWindowHeight : fullWindowHeight
        guard abs(window.frame.height - targetHeight) > 0.5 else { return }

        var frame = window.frame
        frame.origin.y += frame.height - targetHeight
        frame.size.height = targetHeight
        frame.size.width = windowWidth
        window.setFrame(frame, display: true, animate: false)
    }

    @objc private func toggleWindowFromStatusItem() {
        if window.isVisible {
            hideWindow()
        } else {
            showWindow()
        }
    }

    private func hideWindow() {
        window.orderOut(nil)
    }

    private func showWindow() {
        if let screen = NSScreen.main?.visibleFrame {
            let x = screen.maxX - window.frame.width - 24
            let y = screen.maxY - window.frame.height - 24
            window.setFrameOrigin(CGPoint(x: x, y: y))
        }
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

extension AppDelegate: NSWindowDelegate {
    func windowWillClose(_ notification: Notification) {
        NSApp.terminate(nil)
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
