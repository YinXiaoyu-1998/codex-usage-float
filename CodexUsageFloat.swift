import Cocoa
import QuartzCore
import UserNotifications
import ApplicationServices

private extension NSColor {
    convenience init(hex: UInt32, alpha: CGFloat = 1) {
        self.init(
            srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: alpha
        )
    }
}

/// One quota window drawn as a dark glass trough.
///
/// The four remaining-quota tiers keep their own motion language:
/// - meadow (>= 70%): two wide caustic bands drifting slowly in opposite directions
/// - water (40-69%): thin diagonal ribbons flowing towards the tip
/// - sunset (10-39%): a warm bloom breathing at the tip
/// - danger (< 10%): the whole bar breathing a slow red pulse
///
/// Every tier shares the same glass body, gloss and colour grammar.
/// The drag handle at the fill end stays invisible; there is no bead or marker drawn there.
final class FlowProgressView: NSView {
    private typealias Mood = RemainingQuotaTier

    private struct Skin {
        let top: NSColor
        let upper: NSColor
        let lower: NSColor
        let bottom: NSColor
        let rim: NSColor
        let rimAlpha: CGFloat
    }

    private static func skin(for mood: Mood) -> Skin {
        switch mood {
        case .meadow:
            return Skin(
                top: NSColor(hex: 0x8DFFCE),
                upper: NSColor(hex: 0x2EE08A),
                lower: NSColor(hex: 0x14B06D),
                bottom: NSColor(hex: 0x0A7C46),
                rim: NSColor(hex: 0xB9FFDC),
                rimAlpha: 0.24
            )
        case .water:
            return Skin(
                top: NSColor(hex: 0x9AF2FF),
                upper: NSColor(hex: 0x2FB4F5),
                lower: NSColor(hex: 0x1479D6),
                bottom: NSColor(hex: 0x0A4F9E),
                rim: NSColor(hex: 0xB7ECFF),
                rimAlpha: 0.26
            )
        case .sunset:
            return Skin(
                top: NSColor(hex: 0xFFD98A),
                upper: NSColor(hex: 0xF7B32B),
                lower: NSColor(hex: 0xD97706),
                bottom: NSColor(hex: 0x8F3D05),
                rim: NSColor(hex: 0xFFD9A0),
                rimAlpha: 0.30
            )
        case .danger:
            return Skin(
                top: NSColor(hex: 0xFF9A86),
                upper: NSColor(hex: 0xEF4444),
                lower: NSColor(hex: 0xB91C1C),
                bottom: NSColor(hex: 0x5F0D0D),
                rim: NSColor(hex: 0xFFC6BB),
                rimAlpha: 0.55
            )
        }
    }

    // Trough.
    private let trackGradient = CAGradientLayer()
    private let trackTopShadow = CAGradientLayer()
    private let trackBottomLine = CALayer()
    private let trackBorder = CAShapeLayer()
    // Fill.
    private let fillClip = CALayer()
    private let baseGradient = CAGradientLayer()
    private let causticA = CAGradientLayer()
    private let causticB = CAGradientLayer()
    private let stripes = CAShapeLayer()
    private let sheenLayer = CAGradientLayer()
    private let warmWash = CAGradientLayer()
    private let bloom = CAGradientLayer()
    private let gloss = CAGradientLayer()
    private let leftShade = CAGradientLayer()
    private let rim = CAShapeLayer()

    private var displayOptionsObserver: NSObjectProtocol?
    private var visibilityObserver: NSObjectProtocol?
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
        layer?.masksToBounds = true
        layer?.backgroundColor = NSColor(hex: 0x060A14).cgColor

        configureLayers()
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

    private func configureLayers() {
        trackGradient.colors = [NSColor(hex: 0x0D1A33).cgColor, NSColor(hex: 0x070C1A).cgColor]
        trackGradient.startPoint = CGPoint(x: 0.5, y: 0)
        trackGradient.endPoint = CGPoint(x: 0.5, y: 1)
        layer?.addSublayer(trackGradient)

        trackTopShadow.colors = [
            NSColor.black.withAlphaComponent(0.55).cgColor,
            NSColor.black.withAlphaComponent(0).cgColor
        ]
        trackTopShadow.startPoint = CGPoint(x: 0.5, y: 0)
        trackTopShadow.endPoint = CGPoint(x: 0.5, y: 1)
        layer?.addSublayer(trackTopShadow)

        trackBottomLine.backgroundColor = NSColor.white.withAlphaComponent(0.05).cgColor
        layer?.addSublayer(trackBottomLine)

        fillClip.masksToBounds = true
        layer?.addSublayer(fillClip)

        baseGradient.startPoint = CGPoint(x: 0, y: 0)
        baseGradient.endPoint = CGPoint(x: 0.18, y: 1)
        fillClip.addSublayer(baseGradient)

        causticA.colors = [
            NSColor(hex: 0xE9FFF6, alpha: 0).cgColor,
            NSColor(hex: 0xE9FFF6, alpha: 0.34).cgColor,
            NSColor(hex: 0xFFFFFF, alpha: 0.40).cgColor,
            NSColor(hex: 0xC9FFE7, alpha: 0).cgColor
        ]
        causticA.locations = [0, 0.42, 0.62, 1]
        causticA.startPoint = CGPoint(x: 0, y: 0.5)
        causticA.endPoint = CGPoint(x: 1, y: 0.5)
        causticA.transform = CATransform3DMakeRotation(-0.19, 0, 0, 1)
        causticA.isHidden = true
        fillClip.addSublayer(causticA)

        causticB.colors = [
            NSColor(hex: 0xD8FFF0, alpha: 0).cgColor,
            NSColor(hex: 0xD8FFF0, alpha: 0.20).cgColor,
            NSColor(hex: 0xD8FFF0, alpha: 0).cgColor
        ]
        causticB.locations = [0, 0.5, 1]
        causticB.startPoint = CGPoint(x: 0, y: 0.5)
        causticB.endPoint = CGPoint(x: 1, y: 0.5)
        causticB.transform = CATransform3DMakeRotation(-0.245, 0, 0, 1)
        causticB.isHidden = true
        fillClip.addSublayer(causticB)

        stripes.fillColor = NSColor.white.withAlphaComponent(0.20).cgColor
        stripes.isHidden = true
        fillClip.addSublayer(stripes)

        sheenLayer.colors = [
            NSColor.white.withAlphaComponent(0).cgColor,
            NSColor.white.withAlphaComponent(0.18).cgColor,
            NSColor.white.withAlphaComponent(0).cgColor
        ]
        sheenLayer.locations = [0, 0.5, 1]
        sheenLayer.startPoint = CGPoint(x: 0, y: 0.5)
        sheenLayer.endPoint = CGPoint(x: 1, y: 0.5)
        sheenLayer.transform = CATransform3DMakeRotation(-0.26, 0, 0, 1)
        sheenLayer.isHidden = true
        fillClip.addSublayer(sheenLayer)

        warmWash.colors = [
            NSColor(hex: 0xFFF3CD, alpha: 0).cgColor,
            NSColor(hex: 0xFFE6AD, alpha: 0.30).cgColor,
            NSColor(hex: 0xFF9D2E, alpha: 0).cgColor
        ]
        warmWash.locations = [0, 0.55, 1]
        warmWash.startPoint = CGPoint(x: 0.5, y: 0)
        warmWash.endPoint = CGPoint(x: 0.5, y: 1)
        warmWash.isHidden = true
        fillClip.addSublayer(warmWash)

        bloom.type = .radial
        bloom.colors = [
            NSColor(hex: 0xFFF7E0, alpha: 0.80).cgColor,
            NSColor(hex: 0xFFB347, alpha: 0.30).cgColor,
            NSColor(hex: 0xF59E0B, alpha: 0).cgColor
        ]
        bloom.locations = [0, 0.38, 1]
        bloom.startPoint = CGPoint(x: 0.5, y: 0.5)
        bloom.endPoint = CGPoint(x: 1, y: 0.5)
        bloom.isHidden = true
        fillClip.addSublayer(bloom)

        gloss.colors = [
            NSColor.white.withAlphaComponent(0.26).cgColor,
            NSColor.white.withAlphaComponent(0.03).cgColor,
            NSColor.black.withAlphaComponent(0.05).cgColor,
            NSColor.black.withAlphaComponent(0.24).cgColor
        ]
        gloss.locations = [0, 0.24, 0.7, 1]
        gloss.startPoint = CGPoint(x: 0.5, y: 0)
        gloss.endPoint = CGPoint(x: 0.5, y: 1)
        fillClip.addSublayer(gloss)

        leftShade.colors = [
            NSColor.black.withAlphaComponent(0.24).cgColor,
            NSColor.black.withAlphaComponent(0).cgColor
        ]
        leftShade.locations = [0, 1]
        leftShade.startPoint = CGPoint(x: 0, y: 0.5)
        leftShade.endPoint = CGPoint(x: 1, y: 0.5)
        fillClip.addSublayer(leftShade)

        rim.fillColor = nil
        rim.lineWidth = 1
        fillClip.addSublayer(rim)

        trackBorder.fillColor = nil
        trackBorder.lineWidth = 1
        trackBorder.strokeColor = NSColor(hex: 0xB9C8FF, alpha: 0.13).cgColor
        layer?.addSublayer(trackBorder)
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
        let width = bounds.width
        let height = bounds.height
        guard width > 0, height > 0 else { return }

        let mood = Mood.forPercent(Int(displayedPercent))
        let fillWidth = max(0, min(width, width * displayedPercent / 100))
        if previousMood != mood {
            stopAnimations()
        }

        CATransaction.begin()
        CATransaction.setDisableActions(true)

        layer?.cornerRadius = height / 2

        trackGradient.frame = bounds
        trackGradient.cornerRadius = height / 2
        trackTopShadow.frame = CGRect(x: 1, y: 1, width: width - 2, height: 3)
        trackBottomLine.frame = CGRect(x: 3, y: height - 2.6, width: width - 6, height: 1)

        trackBorder.frame = bounds
        trackBorder.path = CGPath(
            roundedRect: CGRect(x: 0.5, y: 0.5, width: width - 1, height: height - 1),
            cornerWidth: height / 2 - 0.5, cornerHeight: height / 2 - 0.5, transform: nil
        )

        fillClip.frame = CGRect(x: 0, y: 0, width: fillWidth, height: height)
        fillClip.cornerRadius = min(height / 2, fillWidth / 2)
        baseGradient.frame = fillClip.bounds
        gloss.frame = fillClip.bounds
        leftShade.frame = CGRect(x: 0, y: 0, width: 14, height: height)

        stripes.frame = CGRect(x: 0, y: 0, width: fillWidth, height: height)
        stripes.path = stripePath(width: fillWidth, height: height)

        causticA.bounds = CGRect(x: 0, y: 0, width: 64, height: height + 16)
        causticA.position = CGPoint(x: 0, y: height / 2)
        causticB.bounds = CGRect(x: 0, y: 0, width: 112, height: height + 24)
        causticB.position = CGPoint(x: 0, y: height / 2)
        sheenLayer.bounds = CGRect(x: 0, y: 0, width: 16, height: height + 16)
        sheenLayer.position = CGPoint(x: 0, y: height / 2)

        warmWash.frame = CGRect(x: 0, y: -4, width: fillWidth, height: height + 8)
        bloom.bounds = CGRect(x: 0, y: 0, width: 52, height: 52)
        bloom.position = CGPoint(x: max(12, fillWidth - 14), y: height / 2)

        rim.frame = fillClip.bounds
        if fillWidth > 1.5 {
            rim.path = CGPath(
                roundedRect: CGRect(x: 0.5, y: 0.5, width: fillWidth - 1, height: height - 1),
                cornerWidth: height / 2 - 0.5, cornerHeight: height / 2 - 0.5, transform: nil
            )
        } else {
            rim.path = nil
        }

        applySkin(mood)
        CATransaction.commit()

        previousMood = mood
        window?.invalidateCursorRects(for: self)
        updateAnimations()
    }

    private func stripePath(width: CGFloat, height: CGFloat) -> CGPath {
        // Repeating ribbons, clipped by the fill. One animation period equals one ribbon period.
        let period: CGFloat = 66
        let band: CGFloat = 10
        let skew: CGFloat = 12
        let path = CGMutablePath()
        var x = -period * 3
        while x < width + period {
            path.move(to: CGPoint(x: x, y: height))
            path.addLine(to: CGPoint(x: x + band, y: height))
            path.addLine(to: CGPoint(x: x + band + skew, y: 0))
            path.addLine(to: CGPoint(x: x + skew, y: 0))
            path.closeSubpath()
            x += period
        }
        return path
    }

    static func accentColor(forPercent percent: Int) -> NSColor {
        skin(for: Mood.forPercent(percent)).top
    }

    private func applySkin(_ mood: Mood) {
        let skin = FlowProgressView.skin(for: mood)
        baseGradient.colors = [skin.top, skin.upper, skin.lower, skin.bottom].map { $0.cgColor }
        baseGradient.locations = [0, 0.34, 0.72, 1]
        rim.strokeColor = skin.rim.withAlphaComponent(skin.rimAlpha).cgColor
    }

    private func updateAnimations() {
        let mood = Mood.forPercent(Int(displayedPercent))
        let visible = window?.occlusionState.contains(.visible) == true && !isHiddenOrHasHiddenAncestor
        guard visible, !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else {
            stopAnimations()
            setMotionLayersVisible(false, for: mood)
            return
        }
        setMotionLayersVisible(true, for: mood)
        startAnimations(for: mood)
    }

    private func setMotionLayersVisible(_ visible: Bool, for mood: Mood) {
        causticA.isHidden = !(visible && mood == .meadow)
        causticB.isHidden = !(visible && mood == .meadow)
        stripes.isHidden = !(visible && mood == .water)
        sheenLayer.isHidden = !(visible && mood == .water)
        warmWash.isHidden = !(visible && mood == .sunset)
        bloom.isHidden = !(visible && mood == .sunset)    }

    private func startAnimations(for mood: Mood) {
        let width = bounds.width
        guard width > 0 else { return }
        switch mood {
        case .meadow:
            addDrift(causticA, key: "driftA", from: -150, to: width + 60, duration: 15, phase: 3.4)
            addDrift(causticB, key: "driftB", from: width * 0.7, to: -140, duration: 21, phase: 7.2)
        case .water:
            addStripeFlow()
            addSweep(sheenLayer, key: "sheen", from: -160, to: width + 150, duration: 3.4)
        case .sunset:
            addBloomPulse()
            addWarmShift()
        case .danger:
            addAlertPulse()
        }
    }

    private func addDrift(_ layer: CALayer, key: String, from: CGFloat, to: CGFloat, duration: CFTimeInterval, phase: CFTimeInterval) {
        guard layer.animation(forKey: key) == nil else { return }
        let animation = CABasicAnimation(keyPath: "transform.translation.x")
        animation.fromValue = from
        animation.toValue = to
        animation.duration = duration
        animation.autoreverses = true
        animation.repeatCount = .infinity
        // Start mid-drift so the tier never launches with a uniform, light-less bar.
        animation.timeOffset = phase
        animation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        layer.add(animation, forKey: key)
    }

    private func addSweep(_ layer: CALayer, key: String, from: CGFloat, to: CGFloat, duration: CFTimeInterval) {
        guard layer.animation(forKey: key) == nil else { return }
        let animation = CABasicAnimation(keyPath: "transform.translation.x")
        animation.fromValue = from
        animation.toValue = to
        animation.duration = duration
        animation.repeatCount = .infinity
        animation.timingFunction = CAMediaTimingFunction(name: .linear)
        layer.add(animation, forKey: key)
    }

    private func addStripeFlow() {
        addSweep(stripes, key: "flow", from: 0, to: 66, duration: 1.7)
    }

    private func addBloomPulse() {
        guard bloom.animation(forKey: "bloom") == nil else { return }
        let scale = CABasicAnimation(keyPath: "transform.scale")
        scale.fromValue = 0.8
        scale.toValue = 1.18
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = 0.4
        fade.toValue = 1
        let group = CAAnimationGroup()
        group.animations = [scale, fade]
        group.duration = 2.4
        group.autoreverses = true
        group.repeatCount = .infinity
        group.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        bloom.add(group, forKey: "bloom")
    }

    private func addWarmShift() {
        guard warmWash.animation(forKey: "warm") == nil else { return }
        let shift = CABasicAnimation(keyPath: "transform.translation.y")
        shift.fromValue = -3
        shift.toValue = 4
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = 0.55
        fade.toValue = 1
        let group = CAAnimationGroup()
        group.animations = [shift, fade]
        group.duration = 4.6
        group.autoreverses = true
        group.repeatCount = .infinity
        group.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        warmWash.add(group, forKey: "warm")
    }

    private func addAlertPulse() {
        // Warn by breathing the whole bar, like the original low-quota blink.
        guard let layer, layer.animation(forKey: "alert") == nil else { return }
        let pulse = CABasicAnimation(keyPath: "opacity")
        pulse.fromValue = 0.55
        pulse.toValue = 1.0
        pulse.duration = 0.95
        pulse.autoreverses = true
        pulse.repeatCount = .infinity
        pulse.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        layer.add(pulse, forKey: "alert")
    }

    private func stopAnimations() {
        let layers: [CALayer] = [causticA, causticB, stripes, sheenLayer, warmWash, bloom, rim]
        for layer in layers { layer.removeAllAnimations() }
        layer?.removeAnimation(forKey: "alert")
        layer?.opacity = 1
        rim.opacity = 1
        bloom.opacity = 1
        warmWash.opacity = 1
        bloom.transform = CATransform3DIdentity
        warmWash.transform = CATransform3DIdentity
    }
}

final class UsageView: NSView {
    var requestHide: (() -> Void)?
    private var progressViews: [FlowProgressView] = []

    private enum Metrics {
        static let cornerRadius: CGFloat = 22
        static let sidePadding: CGFloat = 20
        static let topPadding: CGFloat = 12
        static let headerHeight: CGFloat = 36
        static let headerGap: CGFloat = 10
        static let cardHeight: CGFloat = 122
        static let cardGap: CGFloat = 10
        static let cardRadius: CGFloat = 14
        static let barHeight: CGFloat = 26
        static let barInset: CGFloat = 16
        static let barTop: CGFloat = 86
        static let footerGap: CGFloat = 14
        static let footerHeight: CGFloat = 26
        static let bottomPadding: CGFloat = 14

        static var cardsTop: CGFloat { topPadding + headerHeight + headerGap }
    }

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

    // MARK: - Geometry

    private func cardRect(at index: Int) -> CGRect {
        CGRect(
            x: Metrics.sidePadding,
            y: Metrics.cardsTop + CGFloat(index) * (Metrics.cardHeight + Metrics.cardGap),
            width: bounds.width - Metrics.sidePadding * 2,
            height: Metrics.cardHeight
        )
    }

    private func barRect(in card: CGRect) -> CGRect {
        CGRect(
            x: card.minX + Metrics.barInset,
            y: card.minY + Metrics.barTop,
            width: card.width - Metrics.barInset * 2,
            height: Metrics.barHeight
        )
    }

    private func footerTop(cardCount: Int) -> CGFloat {
        let count = max(1, cardCount)
        return Metrics.cardsTop
            + CGFloat(count) * Metrics.cardHeight
            + CGFloat(count - 1) * Metrics.cardGap
            + Metrics.footerGap
    }

    static func windowHeight(cardCount: Int) -> CGFloat {
        let count = max(1, cardCount)
        return Metrics.cardsTop
            + CGFloat(count) * Metrics.cardHeight
            + CGFloat(count - 1) * Metrics.cardGap
            + Metrics.footerGap
            + Metrics.footerHeight
            + Metrics.bottomPadding
    }

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
            progress.frame = barRect(in: cardRect(at: index))
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

    // MARK: - Drawing

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        NSColor.clear.setFill()
        bounds.fill()

        drawPanel()
        drawHeader()

        let cards = usageCards()
        if cards.isEmpty {
            // Fill whatever height the window currently has, so a disconnect never
            // leaves a half-empty panel below the status card.
            let footerY = bounds.height - Metrics.bottomPadding - Metrics.footerHeight
            let card = CGRect(
                x: Metrics.sidePadding,
                y: Metrics.cardsTop,
                width: bounds.width - Metrics.sidePadding * 2,
                height: max(Metrics.cardHeight, footerY - Metrics.footerGap - Metrics.cardsTop)
            )
            drawStatusCard(in: card)
            drawFooter(above: footerY)
        } else {
            for (index, card) in cards.enumerated() {
                drawCard(card.window, icon: card.icon, in: cardRect(at: index))
            }
            drawFooter(above: footerTop(cardCount: cards.count))
        }
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

    private func drawPanel() {
        let path = NSBezierPath(
            roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5),
            xRadius: Metrics.cornerRadius,
            yRadius: Metrics.cornerRadius
        )
        NSGradient(colors: [
            NSColor(srgbRed: 0.070, green: 0.082, blue: 0.112, alpha: 0.94),
            NSColor(srgbRed: 0.028, green: 0.034, blue: 0.052, alpha: 0.97)
        ])?.draw(in: path, angle: -90)
        NSColor.white.withAlphaComponent(0.10).setStroke()
        path.lineWidth = 1
        path.stroke()

        let highlight = NSBezierPath()
        highlight.move(to: CGPoint(x: 26, y: 1.4))
        highlight.line(to: CGPoint(x: bounds.width - 26, y: 1.4))
        highlight.lineCapStyle = .round
        highlight.lineWidth = 1.2
        NSColor.white.withAlphaComponent(0.13).setStroke()
        highlight.stroke()
    }

    private func drawHeader() {
        drawTrafficLights()

        drawText(
            "Codex Usage",
            centerY: headerCenterY,
            x: 62,
            width: 260,
            size: 17,
            weight: .semibold,
            color: NSColor.white.withAlphaComponent(0.95),
            tracking: -0.2
        )

        drawPlanBadge()
    }

    private func drawPlanBadge() {
        let plan = displayPlanName(snapshot.planType)
        let width = max(50, textWidth(plan, size: 9.5, weight: .semibold, tracking: 0.10) + 20)
        let rect = CGRect(x: bounds.width - Metrics.sidePadding - width, y: headerCenterY - 11, width: width, height: 22)
        let path = NSBezierPath(roundedRect: rect, xRadius: 7, yRadius: 7)
        NSColor.white.withAlphaComponent(0.08).setFill()
        path.fill()
        NSColor.white.withAlphaComponent(0.15).setStroke()
        path.lineWidth = 1
        path.stroke()
        drawText(
            plan,
            rect: rect.insetBy(dx: 8, dy: 5),
            size: 9.5,
            weight: .semibold,
            color: NSColor.white.withAlphaComponent(0.88),
            alignment: .center,
            tracking: 0.10
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

    private var headerCenterY: CGFloat {
        Metrics.topPadding + Metrics.headerHeight / 2
    }

    private let trafficLightDiameter: CGFloat = 14
    private let trafficLightLeftX: CGFloat = 13
    private let trafficLightSpacing: CGFloat = 23.5

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
            NSColor(srgbRed: 1.0, green: 0.39, blue: 0.35, alpha: 1),
            NSColor(srgbRed: 1.0, green: 0.75, blue: 0.24, alpha: 1)
        ]
        for (index, color) in colors.enumerated() {
            let rect = trafficLightRect(index: index)
            let dot = NSBezierPath(ovalIn: rect)
            color.setFill()
            dot.fill()
            NSColor.black.withAlphaComponent(0.28).setStroke()
            dot.lineWidth = 0.6
            dot.stroke()
        }
    }

    private func drawCard(_ limit: LimitWindow, icon: LimitIcon, in rect: CGRect) {
        drawCardChrome(in: rect)

        let iconRect = CGRect(x: rect.minX + 14, y: rect.minY + 12, width: 26, height: 26)
        drawWindowIcon(icon, in: iconRect)
        let rowCenterY = iconRect.midY

        let label = limit.title == "Weekly" ? "WEEKLY WINDOW" : "5-HOUR WINDOW"
        drawText(
            label,
            centerY: rowCenterY,
            x: rect.minX + 48,
            width: 220,
            size: 9.5,
            weight: .semibold,
            color: NSColor.white.withAlphaComponent(0.50),
            tracking: 0.10
        )

        drawText(
            "used \(limit.usedPercent)%",
            centerY: rowCenterY,
            x: rect.maxX - 156,
            width: 142,
            size: 10.5,
            weight: .medium,
            color: NSColor.white.withAlphaComponent(0.46),
            alignment: .right
        )

        let accent = FlowProgressView.accentColor(forPercent: limit.remainingPercent)
        let number = "\(limit.remainingPercent)%"
        let baselineY = rect.minY + 69
        drawText(
            number,
            baselineY: baselineY,
            x: rect.minX + 14,
            width: 220,
            size: 30,
            weight: .semibold,
            color: accent,
            tracking: -0.6,
            monospaced: true
        )

        let numberWidth = textWidth(number, size: 30, weight: .semibold, tracking: -0.6, monospaced: true)
        drawText(
            "left",
            baselineY: baselineY,
            x: rect.minX + 14 + numberWidth + 5,
            width: 40,
            size: 11,
            weight: .medium,
            color: NSColor.white.withAlphaComponent(0.46)
        )

        drawText(
            resetText(for: limit),
            baselineY: baselineY,
            x: rect.maxX - 260,
            width: 246,
            size: 10.5,
            weight: .medium,
            color: NSColor.white.withAlphaComponent(0.42),
            alignment: .right
        )
    }

    private func drawStatusCard(in rect: CGRect) {
        drawCardChrome(in: rect)
        let iconRect = CGRect(x: rect.minX + 14, y: rect.minY + 12, width: 26, height: 26)
        drawWindowIcon(.clock, in: iconRect)
        drawText(
            "STATUS",
            centerY: iconRect.midY,
            x: rect.minX + 48,
            width: 220,
            size: 9.5,
            weight: .semibold,
            color: NSColor.white.withAlphaComponent(0.50),
            tracking: 0.10
        )
        drawText(
            snapshot.status,
            rect: CGRect(x: rect.minX + 14, y: rect.minY + (rect.height - 22) / 2 + 12, width: rect.width - 28, height: 24),
            size: 15,
            weight: .medium,
            color: NSColor.white.withAlphaComponent(0.82)
        )
    }

    private func drawCardChrome(in rect: CGRect) {
        let path = NSBezierPath(roundedRect: rect, xRadius: Metrics.cardRadius, yRadius: Metrics.cardRadius)
        NSGradient(colors: [
            NSColor.white.withAlphaComponent(0.058),
            NSColor.white.withAlphaComponent(0.016)
        ])?.draw(in: path, angle: -90)
        NSColor.white.withAlphaComponent(0.09).setStroke()
        path.lineWidth = 1
        path.stroke()
    }

    private func drawWindowIcon(_ icon: LimitIcon, in rect: CGRect) {
        let tile = NSBezierPath(roundedRect: rect, xRadius: 8, yRadius: 8)
        NSColor.white.withAlphaComponent(0.06).setFill()
        tile.fill()
        NSColor.white.withAlphaComponent(0.10).setStroke()
        tile.lineWidth = 1
        tile.stroke()

        NSColor.white.withAlphaComponent(0.80).setStroke()
        switch icon {
        case .clock:
            let dial = NSBezierPath(ovalIn: rect.insetBy(dx: 7, dy: 7))
            dial.lineWidth = 1.4
            dial.stroke()
            let center = CGPoint(x: rect.midX, y: rect.midY)
            let hands = NSBezierPath()
            hands.lineWidth = 1.4
            hands.lineCapStyle = .round
            hands.move(to: center)
            hands.line(to: CGPoint(x: center.x, y: center.y - 4.5))
            hands.move(to: center)
            hands.line(to: CGPoint(x: center.x + 4.5, y: center.y))
            hands.stroke()
        case .calendar:
            let body = NSBezierPath(roundedRect: rect.insetBy(dx: 6.5, dy: 7), xRadius: 2.5, yRadius: 2.5)
            body.lineWidth = 1.3
            body.stroke()
            let top = NSBezierPath()
            top.lineWidth = 1.3
            top.move(to: CGPoint(x: rect.minX + 8, y: rect.minY + 12.5))
            top.line(to: CGPoint(x: rect.maxX - 8, y: rect.minY + 12.5))
            top.move(to: CGPoint(x: rect.minX + 11, y: rect.minY + 6.5))
            top.line(to: CGPoint(x: rect.minX + 11, y: rect.minY + 9.5))
            top.move(to: CGPoint(x: rect.maxX - 11, y: rect.minY + 6.5))
            top.line(to: CGPoint(x: rect.maxX - 11, y: rect.minY + 9.5))
            top.stroke()
            NSColor.white.withAlphaComponent(0.65).setFill()
            for row in 0..<2 {
                for col in 0..<3 {
                    CGRect(
                        x: rect.minX + 9.5 + CGFloat(col) * 3.6,
                        y: rect.minY + 15 + CGFloat(row) * 3.6,
                        width: 1.6,
                        height: 1.6
                    ).fill()
                }
            }
        }
    }

    private func drawFooter(above y: CGFloat) {
        let divider = NSBezierPath()
        divider.move(to: CGPoint(x: Metrics.sidePadding, y: y))
        divider.line(to: CGPoint(x: bounds.width - Metrics.sidePadding, y: y))
        NSColor.white.withAlphaComponent(0.07).setStroke()
        divider.lineWidth = 1
        divider.stroke()

        let credits = snapshot.resetCredits.map { "reset credits \($0)" } ?? "reset credits -"
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"

        drawText(
            credits,
            rect: CGRect(x: Metrics.sidePadding, y: y + 9, width: 220, height: 15),
            size: 10.5,
            weight: .medium,
            color: NSColor.white.withAlphaComponent(0.42)
        )
        drawText(
            "updated \(formatter.string(from: snapshot.updatedAt))",
            rect: CGRect(x: bounds.width - 240 - Metrics.sidePadding, y: y + 9, width: 240, height: 15),
            size: 10.5,
            weight: .medium,
            color: NSColor.white.withAlphaComponent(0.42),
            alignment: .right,
            monospaced: true
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

    // MARK: - Text helpers

    private func font(size: CGFloat, weight: NSFont.Weight, monospaced: Bool) -> NSFont {
        monospaced
            ? NSFont.monospacedDigitSystemFont(ofSize: size, weight: weight)
            : NSFont.systemFont(ofSize: size, weight: weight)
    }

    private func attributes(
        size: CGFloat,
        weight: NSFont.Weight,
        color: NSColor,
        alignment: NSTextAlignment,
        tracking: CGFloat,
        monospaced: Bool
    ) -> [NSAttributedString.Key: Any] {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = alignment
        paragraph.lineBreakMode = .byTruncatingTail
        var attributes: [NSAttributedString.Key: Any] = [
            .font: font(size: size, weight: weight, monospaced: monospaced),
            .foregroundColor: color,
            .paragraphStyle: paragraph
        ]
        if tracking != 0 {
            attributes[.kern] = tracking
        }
        return attributes
    }

    private func textWidth(
        _ text: String,
        size: CGFloat,
        weight: NSFont.Weight,
        tracking: CGFloat = 0,
        monospaced: Bool = false
    ) -> CGFloat {
        let attributes = attributes(
            size: size,
            weight: weight,
            color: .white,
            alignment: .left,
            tracking: tracking,
            monospaced: monospaced
        )
        return ceil((text as NSString).size(withAttributes: attributes).width)
    }

    private func drawText(
        _ text: String,
        centerY: CGFloat,
        x: CGFloat,
        width: CGFloat,
        size: CGFloat,
        weight: NSFont.Weight,
        color: NSColor,
        alignment: NSTextAlignment = .left,
        tracking: CGFloat = 0,
        monospaced: Bool = false
    ) {
        let lineFont = font(size: size, weight: weight, monospaced: monospaced)
        let lineHeight = lineFont.ascender - lineFont.descender
        drawText(
            text,
            rect: CGRect(x: x, y: centerY - lineHeight / 2, width: width, height: lineHeight),
            size: size,
            weight: weight,
            color: color,
            alignment: alignment,
            tracking: tracking,
            monospaced: monospaced
        )
    }

    private func drawText(
        _ text: String,
        baselineY: CGFloat,
        x: CGFloat,
        width: CGFloat,
        size: CGFloat,
        weight: NSFont.Weight,
        color: NSColor,
        alignment: NSTextAlignment = .left,
        tracking: CGFloat = 0,
        monospaced: Bool = false
    ) {
        let lineFont = font(size: size, weight: weight, monospaced: monospaced)
        drawText(
            text,
            rect: CGRect(
                x: x,
                y: baselineY - lineFont.ascender,
                width: width,
                height: lineFont.ascender - lineFont.descender
            ),
            size: size,
            weight: weight,
            color: color,
            alignment: alignment,
            tracking: tracking,
            monospaced: monospaced
        )
    }

    private func drawText(
        _ text: String,
        rect: CGRect,
        size: CGFloat,
        weight: NSFont.Weight,
        color: NSColor,
        alignment: NSTextAlignment = .left,
        tracking: CGFloat = 0,
        monospaced: Bool = false
    ) {
        let attributes = attributes(
            size: size,
            weight: weight,
            color: color,
            alignment: alignment,
            tracking: tracking,
            monospaced: monospaced
        )
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

        if object["error"] != nil || (object["result"] != nil && !(object["result"] is [String: Any])) {
            rateLimitReadPending = false
            rateLimitReadStartedAt = nil
            publishError("Cannot read Codex usage limits")
            return
        }

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
            } else {
                publishError("Codex usage limits are unavailable")
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
    private var followController: FollowOverlayController?
    private var permissionHelp: FollowAccessibilityHelp!
    private var accessibilityGranted = AXIsProcessTrusted()
    private var hasHadAccessibilityPermission = false
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

        hasHadAccessibilityPermission = accessibilityGranted
        let helpHeight = accessibilityGranted ? 0 : FollowAccessibilityHelp.height
        let windowSize = CGSize(width: windowWidth, height: fullWindowHeight + helpHeight)
        usageView = UsageView(frame: CGRect(x: 0, y: helpHeight, width: windowWidth, height: fullWindowHeight))
        usageView.requestHide = { [weak self] in
            self?.hideWindow()
        }

        // A plain container: the panel draws its own rounded shape. A behind-window
        // NSVisualEffectView would fill the whole rectangular window with blur, which
        // shows up as square, semi-transparent corners outside the rounded panel.
        let container = NSView(frame: CGRect(origin: .zero, size: windowSize))
        container.autoresizingMask = [.width, .height]
        container.wantsLayer = true
        container.addSubview(usageView)
        permissionHelp = FollowAccessibilityHelp()
        permissionHelp.frame = CGRect(x: 0, y: 0, width: windowWidth, height: FollowAccessibilityHelp.height)
        permissionHelp.isHidden = accessibilityGranted
        container.addSubview(permissionHelp)

        window = NSWindow(
            contentRect: CGRect(origin: .zero, size: windowSize),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.title = "Codex Usage"
        window.contentView = container
        window.isMovableByWindowBackground = true
        window.level = .floating
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.backgroundColor = .clear
        window.isOpaque = false
        window.hasShadow = false
        window.isReleasedWhenClosed = false
        window.delegate = self

        positionWindow()
        window.makeKeyAndOrderFront(nil)
        setupStatusItem()
        setupNotifications()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(screenParametersDidChange),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )

        let followController = FollowOverlayController(tracker: CodexWindowTracker(), presenter: FollowOverlayWindow())
        followController.onPermissionChange = { [weak self] granted in
            self?.updateAccessibilityPermission(granted)
        }
        self.followController = followController
        followController.start()

        client = CodexUsageClient { [weak self] snapshot in
            let previousSnapshot = self?.latestSnapshot
            self?.usageView.snapshot = snapshot
            self?.notifyForRefreshedLimits(previous: previousSnapshot, current: snapshot)
            self?.latestSnapshot = snapshot
            self?.updateStatusItem(snapshot)
            self?.resizeWindow(for: snapshot)
            self?.followController?.updateSnapshot(snapshot)
        }
        client.start()

        timer = Timer.scheduledTimer(withTimeInterval: 10, repeats: true) { [weak self] _ in
            self?.client.poll()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        followController?.stop()
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
        if window?.isVisible == true {
            positionWindow()
        }
    }

    private func positionWindow() {
        guard let screen = NSScreen.main ?? NSScreen.screens.first else { return }
        let visible = screen.visibleFrame
        let x = visible.maxX - window.frame.width - 24
        let y = visible.maxY - window.frame.height - 24
        window.setFrameOrigin(CGPoint(x: x, y: y))
    }

    private func resizeWindow(for snapshot: UsageSnapshot) {
        let baseHeight: CGFloat
        if snapshot.hasUsageData {
            baseHeight = snapshot.fiveHour == nil || snapshot.weekly == nil ? compactWindowHeight : fullWindowHeight
        } else {
            baseHeight = usageView.frame.height
        }
        let helpHeight = accessibilityGranted ? 0 : FollowAccessibilityHelp.height
        let targetHeight = baseHeight + helpHeight
        usageView.frame = CGRect(x: 0, y: helpHeight, width: windowWidth, height: baseHeight)
        permissionHelp.isHidden = accessibilityGranted
        guard abs(window.frame.height - targetHeight) > 0.5 else { return }

        var frame = window.frame
        frame.origin.y += frame.height - targetHeight
        frame.size.height = targetHeight
        frame.size.width = windowWidth
        window.setFrame(frame, display: true, animate: false)
    }

    private func updateAccessibilityPermission(_ granted: Bool) {
        accessibilityGranted = granted
        permissionHelp.setRevoked(!granted && hasHadAccessibilityPermission)
        hasHadAccessibilityPermission = hasHadAccessibilityPermission || granted
        resizeWindow(for: latestSnapshot ?? usageView.snapshot)
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
        followController?.setMainWindowHidden(true)
    }

    private func showWindow() {
        followController?.setMainWindowHidden(false)
        positionWindow()
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

@main
enum CodexUsageFloatApp {
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        withExtendedLifetime(delegate) { app.run() }
    }
}
