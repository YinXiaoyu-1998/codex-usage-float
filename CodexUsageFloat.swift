import Cocoa
import QuartzCore
import UserNotifications

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

final class FlowProgressView: NSView {
    private enum Mood {
        case meadow, water, sunset, danger

        static func forPercent(_ percent: Int) -> Mood {
            switch percent {
            case 70...: return .meadow
            case 40..<70: return .water
            case 10..<40: return .sunset
            default: return .danger
            }
        }

        var colors: [NSColor] {
            switch self {
            case .meadow:
                return [NSColor(calibratedRed: 0.12, green: 0.60, blue: 0.29, alpha: 1),
                        NSColor(calibratedRed: 0.48, green: 0.88, blue: 0.49, alpha: 1)]
            case .water:
                return [NSColor(calibratedRed: 0.02, green: 0.65, blue: 0.98, alpha: 1),
                        NSColor(calibratedRed: 0.05, green: 0.83, blue: 0.98, alpha: 1)]
            case .sunset:
                return [NSColor(calibratedRed: 0.97, green: 0.61, blue: 0.12, alpha: 1),
                        NSColor(calibratedRed: 1, green: 0.86, blue: 0.35, alpha: 1)]
            case .danger:
                return [NSColor(calibratedRed: 0.85, green: 0.13, blue: 0.20, alpha: 1),
                        NSColor(calibratedRed: 1, green: 0.39, blue: 0.33, alpha: 1)]
            }
        }
    }

    private let fillLayer = CAGradientLayer()
    private let shimmerLayer = CAGradientLayer()
    private let waveLayer = CAShapeLayer()
    private let accentLayer = CAShapeLayer()
    private var displayOptionsObserver: NSObjectProtocol?
    private var visibilityObserver: NSObjectProtocol?
    private var fillSize = CGSize.zero
    private var previousMood: Mood?
    private var previewPercent: CGFloat?
    private var isDragging = false
    private var dragStartX: CGFloat = 0
    private var dragStartPercent: CGFloat = 0
    private var returnTimer: Timer?
    private var dragCursorPushed = false

    var displayedPercent: CGFloat {
        previewPercent ?? CGFloat(max(0, min(100, percent)))
    }

    var percent = 0 {
        didSet {
            if oldValue != percent { needsLayout = true }
        }
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor(calibratedRed: 0.16, green: 0.21, blue: 0.38, alpha: 1).cgColor
        layer?.masksToBounds = true

        fillLayer.colors = [
            NSColor(calibratedRed: 0.02, green: 0.65, blue: 0.98, alpha: 1).cgColor,
            NSColor(calibratedRed: 0.05, green: 0.83, blue: 0.98, alpha: 1).cgColor
        ]
        fillLayer.startPoint = CGPoint(x: 0, y: 0)
        fillLayer.endPoint = CGPoint(x: 1, y: 1)
        fillLayer.masksToBounds = true
        layer?.addSublayer(fillLayer)

        let clear = NSColor.white.withAlphaComponent(0).cgColor
        let highlight = NSColor.white.withAlphaComponent(0.24).cgColor
        shimmerLayer.colors = [clear, highlight, clear, highlight, clear]
        shimmerLayer.locations = [0, 0.25, 0.5, 0.75, 1]
        shimmerLayer.startPoint = CGPoint(x: 0, y: 0.5)
        shimmerLayer.endPoint = CGPoint(x: 1, y: 0.5)
        fillLayer.addSublayer(shimmerLayer)
        waveLayer.fillColor = NSColor.white.withAlphaComponent(0.15).cgColor
        fillLayer.addSublayer(waveLayer)
        fillLayer.addSublayer(accentLayer)
        toolTip = "Drag the handle to preview quota colors. Release to restore live usage."

        displayOptionsObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            if self.returnTimer != nil && NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
                self.restoreActualPercent(animated: false)
            }
            self.updateAnimations()
        }
        visibilityObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didChangeOcclusionStateNotification,
            object: nil, queue: .main
        ) { [weak self] notification in
            guard let self, let window = notification.object as? NSWindow, window === self.window else { return }
            if !window.occlusionState.contains(.visible) { self.restoreActualPercent(animated: false) }
            self.updateAnimations()
        }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    deinit {
        returnTimer?.invalidate()
        if dragCursorPushed { NSCursor.pop() }
        if let displayOptionsObserver { NSWorkspace.shared.notificationCenter.removeObserver(displayOptionsObserver) }
        if let visibilityObserver { NotificationCenter.default.removeObserver(visibilityObserver) }
    }

    private var handleCenterX: CGFloat {
        max(8, min(bounds.width - 8, bounds.width * displayedPercent / 100 - 8))
    }

    private var handleRect: CGRect {
        CGRect(x: handleCenterX - 12, y: 0, width: 24, height: bounds.height).intersection(bounds)
    }

    override var mouseDownCanMoveWindow: Bool { false }
    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard !isHiddenOrHasHiddenAncestor else { return nil }
        return handleRect.contains(convert(point, from: superview)) ? self : nil
    }

    override func resetCursorRects() {
        super.resetCursorRects()
        addCursorRect(handleRect, cursor: .pointingHand)
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        guard handleRect.contains(point) else { return }
        returnTimer?.invalidate()
        returnTimer = nil
        dragStartPercent = displayedPercent
        previewPercent = dragStartPercent
        dragStartX = point.x
        isDragging = true
        window?.makeFirstResponder(self)
        if !dragCursorPushed {
            NSCursor.closedHand.push()
            dragCursorPushed = true
        }
    }

    override func mouseDragged(with event: NSEvent) {
        guard isDragging, bounds.width > 0 else { return }
        let x = convert(event.locationInWindow, from: nil).x
        previewPercent = max(0, min(100, dragStartPercent + (x - dragStartX) / bounds.width * 100))
        needsLayout = true
        layoutSubtreeIfNeeded()
    }

    override func mouseUp(with event: NSEvent) {
        guard isDragging else { return }
        restoreActualPercent(animated: true)
    }

    override func cancelOperation(_ sender: Any?) {
        restoreActualPercent(animated: true)
    }

    private func restoreActualPercent(animated: Bool) {
        returnTimer?.invalidate()
        returnTimer = nil
        isDragging = false
        if dragCursorPushed {
            NSCursor.pop()
            dragCursorPushed = false
        }
        guard let startPercent = previewPercent else { return }
        guard animated, !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion,
              window?.occlusionState.contains(.visible) == true else {
            previewPercent = nil
            needsLayout = true
            layoutSubtreeIfNeeded()
            return
        }

        let startedAt = CACurrentMediaTime()
        // The timer exists only during the short return; ambient motion stays on Core Animation.
        let timer = Timer(timeInterval: 1.0 / 60, repeats: true) { [weak self] timer in
            guard let self else { timer.invalidate(); return }
            let progress = min(1, (CACurrentMediaTime() - startedAt) / 0.32)
            let eased = CGFloat(1 - pow(1 - progress, 3))
            let target = CGFloat(max(0, min(100, self.percent)))
            self.previewPercent = progress >= 1 ? nil : startPercent + (target - startPercent) * eased
            self.needsLayout = true
            self.layoutSubtreeIfNeeded()
            if progress >= 1 {
                timer.invalidate()
                self.returnTimer = nil
            }
        }
        returnTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil { restoreActualPercent(animated: false) }
        updateAnimations()
    }

    override func layout() {
        super.layout()
        let size = CGSize(width: bounds.width * displayedPercent / 100, height: bounds.height)
        let mood = Mood.forPercent(Int(displayedPercent))
        if previousMood != mood {
            stopAnimations()
        } else if fillSize != size {
            shimmerLayer.removeAllAnimations()
        }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer?.cornerRadius = bounds.height / 2
        layer?.backgroundColor = mood.colors[0].blended(withFraction: 0.80, of: .black)?.cgColor
        fillLayer.colors = mood.colors.map { $0.cgColor }
        fillLayer.frame = CGRect(origin: .zero, size: size)
        fillLayer.cornerRadius = bounds.height / 2
        shimmerLayer.frame = CGRect(x: 0, y: 0, width: size.width * 2, height: size.height)

        // One extra wavelength lets the ribbon loop without a visible seam.
        let wave = CGMutablePath()
        wave.move(to: CGPoint(x: 0, y: 0))
        let waveWidth = size.width + 96
        for x in stride(from: CGFloat(0), through: ceil(waveWidth), by: 2) {
            let amplitude: CGFloat = mood == .sunset ? 0 : 2
            wave.addLine(to: CGPoint(x: x, y: size.height * 0.48 + sin(x * .pi * 2 / 96) * amplitude))
        }
        wave.addLine(to: CGPoint(x: waveWidth, y: 0))
        wave.closeSubpath()
        waveLayer.path = wave
        waveLayer.isHidden = mood == .danger
        shimmerLayer.isHidden = mood == .danger
        accentLayer.frame = CGRect(origin: .zero, size: size)
        accentLayer.isHidden = mood == .water || mood == .danger
        accentLayer.fillColor = NSColor(calibratedRed: 1, green: 0.97, blue: 0.75, alpha: 0.45).cgColor
        let accents = CGMutablePath()
        if mood == .meadow {
            for fraction in [CGFloat(0.22), 0.55, 0.82] {
                let x = size.width * fraction
                let y = size.height * 0.50
                accents.move(to: CGPoint(x: x - 5, y: y - 2))
                accents.addQuadCurve(to: CGPoint(x: x + 5, y: y + 2), control: CGPoint(x: x + 3, y: y - 7))
                accents.addQuadCurve(to: CGPoint(x: x - 5, y: y - 2), control: CGPoint(x: x - 3, y: y + 7))
                accents.closeSubpath()
            }
        } else if mood == .sunset {
            accents.addEllipse(in: CGRect(x: size.width * 0.65 - 9, y: size.height * 0.48 - 9, width: 18, height: 18))
        }
        accentLayer.path = accents
        CATransaction.commit()
        fillSize = size
        previousMood = mood
        window?.invalidateCursorRects(for: self)
        updateAnimations()
    }

    private func stopAnimations() {
        layer?.removeAnimation(forKey: "danger")
        shimmerLayer.removeAllAnimations()
        waveLayer.removeAllAnimations()
        accentLayer.removeAllAnimations()
    }

    private func updateAnimations() {
        let visible = window?.occlusionState.contains(.visible) == true && !isHiddenOrHasHiddenAncestor
        guard visible,
              !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else {
            stopAnimations()
            return
        }
        let mood = Mood.forPercent(Int(displayedPercent))
        if mood == .danger {
            if layer?.animation(forKey: "danger") == nil, let layer {
                addBreathing(to: layer, key: "danger", keyPath: "opacity", from: 0.50, to: 1, duration: 0.85)
            }
            return
        }
        guard fillSize.width > 0 else { return }
        if shimmerLayer.animation(forKey: "flow") == nil {
            let duration: TimeInterval = mood == .water ? 3.6 : 9
            addFlow(to: shimmerLayer, distance: fillSize.width, duration: duration)
        }
        if mood != .sunset, waveLayer.animation(forKey: "flow") == nil {
            addFlow(to: waveLayer, distance: 96, duration: mood == .water ? 4.8 : 8)
        }
        if mood == .meadow, accentLayer.animation(forKey: "sway") == nil {
            addBreathing(to: accentLayer, key: "sway", keyPath: "transform.translation.y", from: -2, to: 2, duration: 2.8)
        } else if mood == .sunset, accentLayer.animation(forKey: "glow") == nil {
            addBreathing(to: accentLayer, key: "glow", keyPath: "opacity", from: 0.35, to: 1, duration: 3.5)
        }
    }

    private func addBreathing(to layer: CALayer, key: String, keyPath: String, from: CGFloat, to: CGFloat, duration: TimeInterval) {
        let animation = CABasicAnimation(keyPath: keyPath)
        animation.fromValue = from
        animation.toValue = to
        animation.duration = duration
        animation.autoreverses = true
        animation.repeatCount = .infinity
        animation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        layer.add(animation, forKey: key)
    }

    private func addFlow(to layer: CALayer, distance: CGFloat, duration: TimeInterval) {
        let animation = CABasicAnimation(keyPath: "transform.translation.x")
        animation.fromValue = -distance
        animation.toValue = 0
        animation.duration = duration
        animation.repeatCount = .infinity
        animation.timingFunction = CAMediaTimingFunction(name: .linear)
        layer.add(animation, forKey: "flow")
    }
}

final class UsageView: NSView {
    var requestHide: (() -> Void)?
    private let headerCenterY: CGFloat = 29
    private let trafficLightDiameter: CGFloat = 12
    private let trafficLightLeftX: CGFloat = 18
    private let trafficLightSpacing: CGFloat = 20
    private let cardTopY: CGFloat = 58
    private let cardHeight: CGFloat = 103.6
    private let cardVerticalStep: CGFloat = 117.6
    private let footerGap: CGFloat = 10
    private let footerHeight: CGFloat = 30
    private var progressViews: [FlowProgressView] = []

    var snapshot = UsageSnapshot(
        fiveHour: nil,
        weekly: nil,
        resetCredits: nil,
        planType: nil,
        updatedAt: Date(),
        status: "Connecting..."
    ) {
        didSet {
            needsDisplay = true
            needsLayout = true
        }
    }

    override var isFlipped: Bool { true }

    override func layout() {
        super.layout()
        let cards = usageCards()
        while progressViews.count < cards.count {
            let progress = FlowProgressView(frame: .zero)
            progressViews.append(progress)
            addSubview(progress)
        }
        while progressViews.count > cards.count {
            progressViews.removeLast().removeFromSuperview()
        }
        for (index, card) in cards.enumerated() {
            let progress = progressViews[index]
            progress.frame = CGRect(
                x: 34, y: cardTopY + CGFloat(index) * cardVerticalStep + 71,
                width: bounds.width - 68, height: 25.6
            )
            progress.percent = card.window.remainingPercent
        }
    }

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

    override func resetCursorRects() {
        super.resetCursorRects()
        for index in 0..<2 {
            addCursorRect(trafficLightRect(index: index).insetBy(dx: -4, dy: -4), cursor: .pointingHand)
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        let bounds = self.bounds
        NSColor.clear.setFill()
        bounds.fill()

        drawGlassBackground(in: bounds)
        drawHeader()

        let cards = usageCards()
        let footerY: CGFloat
        if cards.isEmpty {
            let cardRect = CGRect(x: 18, y: cardTopY, width: bounds.width - 36, height: cardHeight)
            drawWindow(nil, in: cardRect, icon: .clock)
            footerY = cardRect.maxY + footerGap
        } else {
            for (index, card) in cards.enumerated() {
                let y = cardTopY + CGFloat(index) * cardVerticalStep
                drawWindow(card.window, in: CGRect(x: 18, y: y, width: bounds.width - 36, height: cardHeight), icon: card.icon)
            }
            footerY = cardTopY + CGFloat(cards.count - 1) * cardVerticalStep + cardHeight + footerGap
        }
        drawFooter(y: footerY)
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
            NSColor(calibratedRed: 1.0, green: 0.73, blue: 0.20, alpha: 1)
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

    static func windowHeight(cardCount: Int) -> CGFloat {
        let contentCardCount = max(1, cardCount)
        let cardTopY: CGFloat = 58
        let cardHeight: CGFloat = 103.6
        let cardVerticalStep: CGFloat = 117.6
        let footerGap: CGFloat = 10
        let footerHeight: CGFloat = 30
        let footerBottomPadding: CGFloat = 10

        return cardTopY
            + CGFloat(contentCardCount - 1) * cardVerticalStep
            + cardHeight
            + footerGap
            + footerHeight
            + footerBottomPadding
    }

    private func drawFooter(y footerY: CGFloat) {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        let updated = formatter.string(from: snapshot.updatedAt)
        let credits = snapshot.resetCredits.map { "reset credits \($0)" } ?? "reset credits -"
        let footerRect = CGRect(x: 18, y: footerY, width: bounds.width - 36, height: footerHeight)
        let footerPath = NSBezierPath(roundedRect: footerRect, xRadius: 10, yRadius: 10)
        NSColor(calibratedRed: 0.76, green: 0.82, blue: 1.0, alpha: 0.32).setFill()
        footerPath.fill()
        NSColor(calibratedWhite: 1.0, alpha: 0.42).setStroke()
        footerPath.lineWidth = 1
        footerPath.stroke()

        let footerTextY = footerRect.minY + (footerRect.height - 14) / 2
        drawText(
            credits,
            rect: CGRect(x: footerRect.minX + 24, y: footerTextY, width: 142, height: 14),
            size: 12,
            weight: .medium,
            color: NSColor(calibratedRed: 0.18, green: 0.22, blue: 0.62, alpha: 1)
        )

        drawText(
            "•  updated \(updated)",
            rect: CGRect(x: footerRect.minX + 178, y: footerTextY, width: footerRect.width - 196, height: 14),
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
        configureCodexProcess(process)

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

    private func configureCodexProcess(_ process: Process) {
        let codexPaths = [
            "/Applications/ChatGPT.app/Contents/Resources/codex-cli/CodexCLI.app/Contents/MacOS/codex",
            "/Applications/ChatGPT.app/Contents/Resources/codex",
            "/opt/homebrew/bin/codex",
            "/usr/local/bin/codex"
        ]

        if let codexPath = codexPaths.first(where: { FileManager.default.isExecutableFile(atPath: $0) }) {
            process.executableURL = URL(fileURLWithPath: codexPath)
            process.arguments = ["app-server", "--stdio"]
            return
        }

        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["codex", "app-server", "--stdio"]
        var environment = ProcessInfo.processInfo.environment
        environment["PATH"] = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
        process.environment = environment
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
    private let fullWindowHeight = UsageView.windowHeight(cardCount: 2)
    private let compactWindowHeight = UsageView.windowHeight(cardCount: 1)
    private let compactStatusItemWidthThreshold: CGFloat = 1700
    private var window: NSWindow!
    private var usageView: UsageView!
    private var client: CodexUsageClient!
    private var timer: Timer?
    private var statusItem: NSStatusItem!
    private var latestSnapshot: UsageSnapshot?
    private var notificationPermissionGranted = false
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
        setupNotifications()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(screenParametersDidChange),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )

        client = CodexUsageClient { [weak self] snapshot in
            let previousSnapshot = self?.latestSnapshot
            self?.usageView.snapshot = snapshot
            self?.notifyForRefreshedLimits(previous: previousSnapshot, current: snapshot)
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

    private func setupNotifications() {
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        center.requestAuthorization(options: [.alert, .sound]) { [weak self] granted, _ in
            DispatchQueue.main.async {
                self?.notificationPermissionGranted = granted
            }
        }
    }

    private func notifyForRefreshedLimits(previous: UsageSnapshot?, current: UsageSnapshot) {
        guard let previous else { return }

        var refreshed: [(label: String, remaining: Int)] = []
        if didRefresh(previous: previous.fiveHour, current: current.fiveHour) {
            refreshed.append(("5H", current.fiveHour?.remainingPercent ?? 100))
        }
        if didRefresh(previous: previous.weekly, current: current.weekly) {
            refreshed.append(("Weekly", current.weekly?.remainingPercent ?? 100))
        }
        guard !refreshed.isEmpty else { return }

        let summary = refreshed
            .map { "\($0.label) is back to \($0.remaining)% left" }
            .joined(separator: ", ")
        deliverUsageRefreshNotification(body: summary)
    }

    private func didRefresh(previous: LimitWindow?, current: LimitWindow?) -> Bool {
        guard let previous, let current else { return false }
        return previous.remainingPercent <= 96 && current.remainingPercent >= 99
    }

    private func deliverUsageRefreshNotification(body: String) {
        guard notificationPermissionGranted else {
            NSSound.beep()
            return
        }

        let content = UNMutableNotificationContent()
        content.title = "Codex Usage Refreshed"
        content.body = body
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: "codex-usage-refreshed-\(UUID().uuidString)",
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request) { error in
            if error != nil {
                DispatchQueue.main.async {
                    NSSound.beep()
                }
            }
        }
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

extension AppDelegate: UNUserNotificationCenterDelegate {
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
