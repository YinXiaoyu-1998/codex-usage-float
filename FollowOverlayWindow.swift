import AppKit

private final class FollowPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

private final class FollowOverlayView: NSView {
    var rows: [FollowOverlayRow] = [] { didSet { needsDisplay = true } }
    override var isFlipped: Bool { true }
    override var isOpaque: Bool { false }

    override func draw(_ dirtyRect: NSRect) {
        // Clear previous glyphs without painting a backdrop over Codex controls.
        // Keep text opaque; reducing the panel's alpha would fade the quota too.
        NSGraphicsContext.current?.cgContext.clear(bounds)
        for (index, row) in rows.enumerated() {
            let color: NSColor
            switch row.remainingPercent.map(RemainingQuotaTier.forPercent) {
            case .some(.meadow): color = NSColor(srgbRed: 0.08, green: 0.64, blue: 0.39, alpha: 1)
            case .some(.water): color = NSColor(srgbRed: 0.08, green: 0.47, blue: 0.84, alpha: 1)
            case .some(.sunset): color = NSColor(srgbRed: 0.85, green: 0.47, blue: 0.02, alpha: 1)
            case .some(.danger): color = NSColor(srgbRed: 0.94, green: 0.27, blue: 0.27, alpha: 1)
            case .none: color = .secondaryLabelColor
            }
            (row.text as NSString).draw(
                in: CGRect(x: 12, y: 8 + CGFloat(index) * 21, width: bounds.width - 24, height: 21),
                withAttributes: [.font: NSFont.monospacedDigitSystemFont(ofSize: 13, weight: .medium), .foregroundColor: color]
            )
        }
    }
}

final class FollowOverlayWindow: FollowOverlayPresenting {
    private let panel: FollowPanel
    private let view = FollowOverlayView()
    private var lastPresentation: FollowOverlayPresentation?

    init() {
        panel = FollowPanel(
            contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered, defer: false
        )
        panel.title = "Codex Usage Follow Overlay"
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.isMovable = false
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        panel.contentView = view
        view.autoresizingMask = [.width, .height]
    }

    func present(_ presentation: FollowOverlayPresentation?) {
        guard let presentation else {
            if panel.isVisible { panel.orderOut(nil) }
            lastPresentation = nil
            return
        }
        if lastPresentation?.rows != presentation.rows { view.rows = presentation.rows }
        if lastPresentation?.frame != presentation.frame {
            panel.setFrame(presentation.frame, display: true, animate: false)
        }
        lastPresentation = presentation
        if !panel.isVisible { panel.orderFrontRegardless() }
    }
}
