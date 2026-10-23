import Foundation
import CoreGraphics

/// AX uses global top-left coordinates in logical points; desktopTop is the
/// top edge of the menu-bar display in AppKit's bottom-left coordinate system.
struct FollowEnvironment {
    var accessibilityGranted: Bool
    var focusedWindowFrame: CGRect?
    var desktopTop: CGFloat
}

struct FollowOverlayRow: Equatable {
    let text: String
    let remainingPercent: Int?
}

struct FollowOverlayPresentation: Equatable {
    let frame: CGRect
    let rows: [FollowOverlayRow]
}

protocol FollowOverlayTracking: AnyObject {
    var onChange: ((FollowEnvironment) -> Void)? { get set }
    func start()
    func stop()
    func refresh()
    func setContinuousTracking(_ enabled: Bool)
}

protocol FollowOverlayPresenting: AnyObject {
    func present(_ presentation: FollowOverlayPresentation?)
}

/// One entry point for observable overlay behavior. Platform observation and
/// drawing remain behind the tracker and presenter rather than in the usage UI.
final class FollowOverlayController {
    var onPermissionChange: ((Bool) -> Void)?

    private let tracker: FollowOverlayTracking
    private let presenter: FollowOverlayPresenting
    private var running = false
    private var session: UInt = 0
    private var mainWindowHidden = false
    private var snapshot: UsageSnapshot?
    private var environment = FollowEnvironment(
        accessibilityGranted: false, focusedWindowFrame: nil, desktopTop: 0
    )

    init(tracker: FollowOverlayTracking, presenter: FollowOverlayPresenting) {
        self.tracker = tracker
        self.presenter = presenter
    }

    func start() {
        guard !running else { return }
        running = true
        session &+= 1
        let session = self.session
        tracker.onChange = { [weak self] environment in
            guard let self, self.running, self.session == session else { return }
            let permissionChanged = self.environment.accessibilityGranted != environment.accessibilityGranted
            self.environment = environment
            if permissionChanged { self.onPermissionChange?(environment.accessibilityGranted) }
            self.render()
        }
        tracker.start()
        render()
    }

    func stop() {
        running = false
        session &+= 1
        tracker.onChange = nil
        tracker.setContinuousTracking(false)
        tracker.stop()
        presenter.present(nil)
    }

    func setMainWindowHidden(_ hidden: Bool) {
        mainWindowHidden = hidden
        // Never render using a cached target after the user has switched apps.
        if running { tracker.refresh() }
        render()
    }

    func updateSnapshot(_ snapshot: UsageSnapshot) {
        self.snapshot = snapshot
        render()
    }

    private func render() {
        guard running, mainWindowHidden, environment.accessibilityGranted,
              let target = environment.focusedWindowFrame,
              target.width > 0, target.height > 0,
              target.minX.isFinite, target.minY.isFinite,
              target.width.isFinite, target.height.isFinite,
              environment.desktopTop.isFinite else {
            tracker.setContinuousTracking(false)
            presenter.present(nil)
            return
        }

        let rows = makeRows()
        let size = CGSize(width: 140, height: CGFloat(rows.count) * 21 + 16)
        // Align the first quota line with the Codex title, just to its right.
        // Keep the same offset when the sidebar collapses or the window resizes.
        let frame = CGRect(
            x: target.minX + 140,
            y: environment.desktopTop - target.minY - 53 - size.height,
            width: size.width, height: size.height
        )
        tracker.setContinuousTracking(true)
        presenter.present(FollowOverlayPresentation(frame: frame, rows: rows))
    }

    private func makeRows() -> [FollowOverlayRow] {
        guard let snapshot else {
            return [FollowOverlayRow(text: "额度连接中…", remainingPercent: nil)]
        }
        var rows: [FollowOverlayRow] = []
        if let weekly = snapshot.weekly {
            rows.append(FollowOverlayRow(text: "周剩余 \(weekly.remainingPercent)%", remainingPercent: weekly.remainingPercent))
        }
        if let fiveHour = snapshot.fiveHour {
            rows.append(FollowOverlayRow(text: "5h 剩余 \(fiveHour.remainingPercent)%", remainingPercent: fiveHour.remainingPercent))
        }
        if rows.isEmpty {
            let connecting = snapshot.status == "Connecting..."
            rows.append(FollowOverlayRow(text: connecting ? "额度连接中…" : "额度暂不可用", remainingPercent: nil))
        }
        return rows
    }
}
