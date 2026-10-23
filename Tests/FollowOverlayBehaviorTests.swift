import Foundation
import CoreGraphics

private struct TestFailure: Error, CustomStringConvertible {
    let description: String
}

private func expect(_ condition: @autoclosure () throws -> Bool, _ message: String) throws {
    if try !condition() { throw TestFailure(description: message) }
}

private final class FakeTracker: FollowOverlayTracking {
    var onChange: ((FollowEnvironment) -> Void)?
    var environment = FollowEnvironment(accessibilityGranted: false, focusedWindowFrame: nil, desktopTop: 900)
    private(set) var continuousTracking = false
    private(set) var running = false

    func start() {
        running = true
        refresh()
    }

    func stop() { running = false }
    func refresh() { onChange?(environment) }
    func setContinuousTracking(_ enabled: Bool) { continuousTracking = enabled }

    func send(permission: Bool = true, frame: CGRect? = CGRect(x: 100, y: 80, width: 1000, height: 700), desktopTop: CGFloat = 900) {
        environment = FollowEnvironment(accessibilityGranted: permission, focusedWindowFrame: frame, desktopTop: desktopTop)
        refresh()
    }
}

private final class RecordingPresenter: FollowOverlayPresenting {
    private(set) var visible: FollowOverlayPresentation?
    func present(_ presentation: FollowOverlayPresentation?) { visible = presentation }
}

private final class Fixture {
    let tracker = FakeTracker()
    let presenter = RecordingPresenter()
    let controller: FollowOverlayController

    init() {
        controller = FollowOverlayController(tracker: tracker, presenter: presenter)
        controller.start()
    }

    func show() {
        tracker.send()
        controller.setMainWindowHidden(true)
    }

    func presentation() throws -> FollowOverlayPresentation {
        guard let result = presenter.visible else { throw TestFailure(description: "Expected a visible follow overlay") }
        return result
    }

    func expectHidden(_ message: String) throws {
        try expect(presenter.visible == nil, message)
        try expect(!tracker.continuousTracking, "Hidden overlays must stop continuous position sampling: \(message)")
    }
}

private func snapshot(fiveHour: Int? = nil, weekly: Int? = nil, status: String = "Live") -> UsageSnapshot {
    func window(_ used: Int?, title: String) -> LimitWindow? {
        used.map { LimitWindow(title: title, usedPercent: $0, windowDurationMins: nil, resetsAt: nil) }
    }
    return UsageSnapshot(
        fiveHour: window(fiveHour, title: "5H"), weekly: window(weekly, title: "Weekly"),
        resetCredits: nil, planType: nil, updatedAt: Date(timeIntervalSince1970: 0), status: status
    )
}

private func testVisibilityMatrix() throws {
    for hidden in [false, true] {
        for granted in [false, true] {
            for focused in [false, true] {
                let fixture = Fixture()
                fixture.tracker.send(permission: granted, frame: focused ? CGRect(x: 100, y: 80, width: 1000, height: 700) : nil)
                fixture.controller.setMainWindowHidden(hidden)
                let shouldShow = hidden && granted && focused
                try expect((fixture.presenter.visible != nil) == shouldShow, "Wrong visibility for hidden=\(hidden), permission=\(granted), focused=\(focused)")
                try expect(fixture.tracker.continuousTracking == shouldShow, "Continuous tracking must match visible eligibility")
            }
        }
    }
}

private func testFocusAndMainWindowRecovery() throws {
    let fixture = Fixture()
    fixture.show()
    try expect(fixture.presenter.visible != nil, "Collapsing the main window should show the overlay")
    fixture.tracker.send(frame: nil)
    try fixture.expectHidden("Switching apps, minimizing, hiding or quitting Codex must hide its overlay")
    fixture.tracker.send()
    try expect(fixture.presenter.visible != nil && fixture.tracker.continuousTracking, "Returning to Codex must restore the overlay and tracking")
    fixture.controller.setMainWindowHidden(false)
    try fixture.expectHidden("Restoring Usage Float must hide the duplicate summary")
    fixture.controller.setMainWindowHidden(true)
    try expect(fixture.presenter.visible != nil, "Collapsing Usage Float again must restore the summary automatically")
}

private func testPermissionRevocationAndRecovery() throws {
    let fixture = Fixture()
    var reportedPermission: Bool?
    fixture.controller.onPermissionChange = { reportedPermission = $0 }
    fixture.controller.setMainWindowHidden(true)
    try fixture.expectHidden("Permission has not been granted")
    fixture.tracker.send()
    try expect(reportedPermission == true && fixture.presenter.visible != nil, "Granting permission must restore the overlay and update the main-window permission state")
    fixture.tracker.send(permission: false)
    try fixture.expectHidden("Revoking permission must immediately hide the overlay")
    try expect(reportedPermission == false, "The main window must receive revoked permission state")
    fixture.tracker.send()
    try expect(fixture.presenter.visible != nil, "Granting permission again must recover without restarting Usage Float")
}

private func testLoadingAndQuotaRows() throws {
    let fixture = Fixture()
    fixture.show()
    try expect(try fixture.presentation().rows == [FollowOverlayRow(text: "Connecting...", remainingPercent: nil)], "The first visible frame should clearly indicate loading in English")
    fixture.controller.updateSnapshot(snapshot(fiveHour: 12, weekly: 60))
    let result = try fixture.presentation()
    try expect(result.rows == [
        FollowOverlayRow(text: "Weekly 40% left", remainingPercent: 40),
        FollowOverlayRow(text: "5H 88% left", remainingPercent: 88)
    ], "The overlay must use English labels and the same remaining quota values, with weekly first")
}

private func testSingleQuotaAndTopAnchor() throws {
    let fixture = Fixture()
    fixture.show()
    fixture.controller.updateSnapshot(snapshot(fiveHour: 12, weekly: 60))
    let twoRows = try fixture.presentation()
    fixture.controller.updateSnapshot(snapshot(weekly: 60))
    let weeklyOnly = try fixture.presentation()
    try expect(weeklyOnly.rows == [FollowOverlayRow(text: "Weekly 40% left", remainingPercent: 40)], "Missing five-hour data must not become a zero value")
    try expect(weeklyOnly.frame.height < twoRows.frame.height, "A single quota should occupy a single-row overlay")
    try expect(weeklyOnly.frame.maxY == twoRows.frame.maxY, "Changing row count must preserve the top anchor")
    fixture.controller.updateSnapshot(snapshot(fiveHour: 12))
    try expect(try fixture.presentation().rows == [FollowOverlayRow(text: "5H 88% left", remainingPercent: 88)], "Missing weekly data must leave only the five-hour row")
}

private func testFailureClearsStaleQuotaAndRecovers() throws {
    let fixture = Fixture()
    fixture.show()
    fixture.controller.updateSnapshot(snapshot(fiveHour: 12, weekly: 60))
    fixture.controller.updateSnapshot(snapshot(status: "Connection failed"))
    try expect(try fixture.presentation().rows == [FollowOverlayRow(text: "Usage unavailable", remainingPercent: nil)], "A read failure must replace previously successful numbers")
    fixture.controller.updateSnapshot(snapshot(status: "Connecting..."))
    try expect(try fixture.presentation().rows == [FollowOverlayRow(text: "Connecting...", remainingPercent: nil)], "Reconnecting must not restore stale numbers")
    fixture.controller.updateSnapshot(snapshot(weekly: 55))
    try expect(try fixture.presentation().rows == [FollowOverlayRow(text: "Weekly 45% left", remainingPercent: 45)], "A successful retry must restore fresh quota values")
    fixture.controller.updateSnapshot(snapshot(status: "No usage data"))
    try expect(try fixture.presentation().rows.first?.remainingPercent == nil, "An empty result must not retain a previous quota")
}

private func testQuotaBoundaries() throws {
    let fixture = Fixture()
    fixture.show()
    fixture.controller.updateSnapshot(snapshot(fiveHour: 100, weekly: 0))
    try expect(try fixture.presentation().rows.map(\.remainingPercent) == [100, 0], "0% and 100% remaining must display correctly")
    fixture.controller.updateSnapshot(snapshot(fiveHour: 150, weekly: -20))
    try expect(try fixture.presentation().rows.map(\.remainingPercent) == [100, 0], "The shared remaining-quota calculation must clamp input outside 0–100")
}

private func testMovementAndResizePreserveOffset() throws {
    let fixture = Fixture()
    fixture.show()
    let initial = try fixture.presentation().frame
    fixture.tracker.send(frame: CGRect(x: 240, y: 130, width: 1000, height: 700))
    let moved = try fixture.presentation().frame
    try expect(moved.minX - initial.minX == 140 && moved.minY - initial.minY == -50, "Each live position update must move the overlay with the target in AppKit coordinates")
    fixture.tracker.send(frame: CGRect(x: 240, y: 130, width: 1200, height: 500))
    try expect(try fixture.presentation().frame == moved, "Resizing or collapsing the sidebar must preserve the window-relative anchor")
}

private func testSecondaryDisplayCoordinatesAndScreenChanges() throws {
    let fixture = Fixture()
    fixture.show()
    let initial = try fixture.presentation().frame
    fixture.tracker.send(frame: CGRect(x: -1340, y: -120, width: 1000, height: 700))
    let secondary = try fixture.presentation().frame
    try expect(secondary.minX - initial.minX == -1440, "A secondary screen left of the main screen must retain its negative coordinates")
    try expect(secondary.minY - initial.minY == 200, "A screen above the main display must convert top-left coordinates correctly")
    fixture.tracker.send(frame: CGRect(x: -1340, y: -120, width: 1000, height: 700), desktopTop: 1200)
    try expect(try fixture.presentation().frame.minY - secondary.minY == 300, "A changed desktop top must update the coordinate conversion")
}

private func testMultipleWindowsAndCodexRestart() throws {
    let fixture = Fixture()
    fixture.show()
    let firstWindow = try fixture.presentation()
    fixture.tracker.send(frame: CGRect(x: 400, y: 150, width: 800, height: 600))
    let secondWindow = try fixture.presentation()
    try expect(secondWindow.frame != firstWindow.frame, "Switching focused Codex windows must move the existing overlay")
    fixture.tracker.send(frame: nil)
    try fixture.expectHidden("The Codex process has exited")
    fixture.tracker.send(frame: CGRect(x: 400, y: 150, width: 800, height: 600))
    try expect(try fixture.presentation() == secondWindow, "A relaunched Codex window must recover without restarting Usage Float")
}

private func testUnreliableTargetsHideUntilRecovery() throws {
    let fixture = Fixture()
    fixture.show()
    let invalidFrames = [
        CGRect(x: 100, y: 80, width: 0, height: 700),
        CGRect(x: 100, y: 80, width: 1000, height: 0),
        CGRect(x: CGFloat.nan, y: 80, width: 1000, height: 700),
        CGRect(x: 100, y: CGFloat.infinity, width: 1000, height: 700)
    ]
    for frame in invalidFrames {
        fixture.tracker.send(frame: frame)
        try fixture.expectHidden("Unreliable geometry must not leave the overlay at an old position")
        fixture.tracker.send()
        try expect(fixture.presenter.visible != nil, "Recovering geometry must restore the overlay")
    }
    fixture.tracker.send(desktopTop: .infinity)
    try fixture.expectHidden("Invalid display geometry must hide the overlay")
}

private func testCollapseRefreshesTheCurrentTarget() throws {
    let fixture = Fixture()
    fixture.tracker.send()
    // A delayed workspace event must not let collapsing the main window use a cached Codex target.
    fixture.tracker.environment.focusedWindowFrame = nil
    fixture.controller.setMainWindowHidden(true)
    try fixture.expectHidden("Collapsing must recheck the target before rendering")
    fixture.tracker.send()
    try expect(fixture.presenter.visible != nil, "The overlay should recover on the next valid target event")
}

private func testStopIgnoresLateEventsAndData() throws {
    let fixture = Fixture()
    fixture.show()
    let lateEvent = fixture.tracker.onChange
    let oldEnvironment = fixture.tracker.environment
    fixture.controller.stop()
    try fixture.expectHidden("Stopping Usage Float must remove the overlay")
    try expect(!fixture.tracker.running, "Stopping must release the tracker lifecycle")
    lateEvent?(oldEnvironment)
    fixture.controller.updateSnapshot(snapshot(fiveHour: 12, weekly: 60))
    try fixture.expectHidden("A queued old target callback or quota update must not revive a stopped overlay")
}

private func testRestartIgnoresPreviousSessionEvents() throws {
    let fixture = Fixture()
    fixture.show()
    let previousSessionEvent = fixture.tracker.onChange
    let previousTarget = fixture.tracker.environment
    fixture.controller.stop()
    fixture.tracker.environment.focusedWindowFrame = nil
    fixture.controller.start()
    try fixture.expectHidden("A restarted controller has no focused Codex target")
    previousSessionEvent?(previousTarget)
    try fixture.expectHidden("A callback queued before stop must not restore an old target in the new session")
    fixture.tracker.send()
    try expect(fixture.presenter.visible != nil, "New-session target events must still recover the overlay")
}

private func testWindowIdentityReplacementRecovers() throws {
    let fixture = Fixture()
    fixture.controller.setMainWindowHidden(true)
    let frame = CGRect(x: 100, y: 80, width: 1000, height: 700)
    var identity = FollowWindowIdentityResolver()
    func publish(_ windows: [FollowWindowCandidate]) {
        fixture.tracker.send(frame: identity.isVisible(focusedFrame: frame, windows: windows) ? frame : nil)
    }
    publish([FollowWindowCandidate(id: 1, frame: frame)])
    try expect(fixture.presenter.visible != nil, "The initially resolved target should display its overlay")
    publish([])
    try fixture.expectHidden("A temporarily absent window must hide the overlay")
    publish([FollowWindowCandidate(id: 2, frame: frame)])
    try expect(fixture.presenter.visible != nil, "A replacement window-server identity must recover without an AX focus change")
}

private func testAmbiguousWindowIdentityStaysHidden() throws {
    let fixture = Fixture()
    fixture.controller.setMainWindowHidden(true)
    let frame = CGRect(x: 100, y: 80, width: 1000, height: 700)
    var identity = FollowWindowIdentityResolver()
    let windows = [FollowWindowCandidate(id: 1, frame: frame), FollowWindowCandidate(id: 2, frame: frame)]
    fixture.tracker.send(frame: identity.isVisible(focusedFrame: frame, windows: windows) ? frame : nil)
    try fixture.expectHidden("Ambiguous target geometry must not attach the overlay to an arbitrary window")
}

@main
private struct FollowOverlayBehaviorTests {
    static func main() {
        let tests: [(String, () throws -> Void)] = [
            ("visibility matrix and sampling eligibility", testVisibilityMatrix),
            ("focus and main-window recovery", testFocusAndMainWindowRecovery),
            ("permission revocation and recovery", testPermissionRevocationAndRecovery),
            ("loading and shared quota rows", testLoadingAndQuotaRows),
            ("single quota and stable top anchor", testSingleQuotaAndTopAnchor),
            ("data failure clears stale quota and recovers", testFailureClearsStaleQuotaAndRecovers),
            ("remaining-quota boundaries", testQuotaBoundaries),
            ("live movement and resize", testMovementAndResizePreserveOffset),
            ("secondary-display coordinates and screen changes", testSecondaryDisplayCoordinatesAndScreenChanges),
            ("focused-window switch and Codex restart", testMultipleWindowsAndCodexRestart),
            ("unreliable geometry and recovery", testUnreliableTargetsHideUntilRecovery),
            ("main-window collapse refreshes target", testCollapseRefreshesTheCurrentTarget),
            ("stop ignores queued events and quota updates", testStopIgnoresLateEventsAndData),
            ("restart ignores previous-session target events", testRestartIgnoresPreviousSessionEvents),
            ("window-server identity replacement recovers", testWindowIdentityReplacementRecovers),
            ("ambiguous window identity stays hidden", testAmbiguousWindowIdentityStaysHidden)
        ]
        var failures = 0
        for (name, test) in tests {
            do {
                try test()
                print("PASS \(name)")
            } catch {
                failures += 1
                FileHandle.standardError.write(Data("FAIL \(name): \(error)\n".utf8))
            }
        }
        print("\(tests.count - failures)/\(tests.count) follow-overlay behavior tests passed")
        if failures > 0 { exit(1) }
    }
}
