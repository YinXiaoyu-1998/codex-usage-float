import AppKit
import ApplicationServices

/// Permission guidance stays in the interactive main window, never the overlay.
final class FollowAccessibilityHelp: NSView {
    static let height: CGFloat = 68
    private let explanation = NSTextField(labelWithString: "Follow overlay needs Accessibility access")
    private let detail = NSTextField(labelWithString: "Reads Codex window position. Activates when allowed.")
    private let settingsButton = NSButton(title: "Open Settings", target: nil, action: nil)

    init() {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = NSColor(srgbRed: 0.06, green: 0.07, blue: 0.10, alpha: 0.98).cgColor
        layer?.cornerRadius = 14
        explanation.font = .systemFont(ofSize: 12, weight: .medium)
        explanation.textColor = .white
        detail.font = .systemFont(ofSize: 10.5)
        detail.textColor = NSColor.white.withAlphaComponent(0.7)
        settingsButton.bezelStyle = .rounded
        settingsButton.controlSize = .small
        settingsButton.appearance = NSAppearance(named: .darkAqua)
        settingsButton.target = self
        settingsButton.action = #selector(openSettings)
        [explanation, detail, settingsButton].forEach { addSubview($0) }
        setRevoked(false)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func setRevoked(_ revoked: Bool) {
        explanation.stringValue = revoked ? "Accessibility access revoked; overlay hidden" : "Follow overlay needs Accessibility access"
    }

    override func layout() {
        super.layout()
        explanation.frame = CGRect(x: 20, y: 35, width: bounds.width - 147, height: 18)
        detail.frame = CGRect(x: 20, y: 15, width: bounds.width - 147, height: 16)
        settingsButton.frame = CGRect(x: bounds.width - 122, y: 21, width: 104, height: 27)
    }

    @objc private func openSettings() {
        let defaults = UserDefaults.standard
        let key = "followOverlayAccessibilityPromptRequested"
        if !AXIsProcessTrusted(), !defaults.bool(forKey: key) {
            defaults.set(true, forKey: key)
            let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
            _ = AXIsProcessTrustedWithOptions(options)
        }
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }
}
