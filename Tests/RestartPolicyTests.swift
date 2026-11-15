import Foundation

private struct TestFailure: Error, CustomStringConvertible {
    let description: String
}

private func expect(_ condition: @autoclosure () throws -> Bool, _ message: String) throws {
    if try !condition() { throw TestFailure(description: message) }
}

private func testBackoffGrowsAndCaps() throws {
    var policy = RestartPolicy(baseDelay: 2, maxDelay: 60, maxAttempts: 6, sustainedDelay: 300)
    let expected: [TimeInterval] = [2, 4, 8, 16, 32, 60]
    for delay in expected {
        try expect(policy.nextDelay() == delay, "Expected \(delay)s before the next relaunch")
    }
    try expect(policy.isSustained, "Six failed attempts must exhaust the fast retries")
}

private func testSustainedProbeStopsAccelerating() throws {
    var policy = RestartPolicy(baseDelay: 2, maxDelay: 60, maxAttempts: 2, sustainedDelay: 300)
    try expect(policy.nextDelay() == 2, "First attempt uses the base delay")
    try expect(policy.nextDelay() == 4, "Second attempt doubles")
    try expect(policy.isSustained, "Two attempts exhaust this policy")
    for _ in 0..<5 {
        try expect(policy.nextDelay() == 300, "A sustained probe keeps a fixed slow cadence")
    }
}

private func testSuccessResetsTheCeiling() throws {
    var policy = RestartPolicy(baseDelay: 2, maxDelay: 60, maxAttempts: 2, sustainedDelay: 300)
    _ = policy.nextDelay()
    _ = policy.nextDelay()
    try expect(policy.isSustained, "The policy is sustained before recovery")
    policy.recordSuccess()
    try expect(!policy.isSustained, "A successful handshake restarts the fast retries")
    try expect(policy.nextDelay() == 2, "Recovery returns to the base delay")
}

private func testZeroAttemptsMeansImmediateSustainedProbe() throws {
    var policy = RestartPolicy(baseDelay: 2, maxDelay: 60, maxAttempts: 0, sustainedDelay: 300)
    try expect(policy.isSustained, "An exhausted budget starts sustained")
    try expect(policy.nextDelay() == 300, "With no fast retries only the slow probe remains")
}

@main
private enum RestartPolicyTestRunner {
    static func main() {
        runRestartPolicyTests()
    }
}

private func runRestartPolicyTests() {
    let tests: [(String, () throws -> Void)] = [
        ("backoff grows and caps", testBackoffGrowsAndCaps),
        ("sustained probe stops accelerating", testSustainedProbeStopsAccelerating),
        ("success resets the ceiling", testSuccessResetsTheCeiling),
        ("zero attempts means immediate sustained probe", testZeroAttemptsMeansImmediateSustainedProbe)
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
    print("\(tests.count - failures)/\(tests.count) restart policy tests passed")
    if failures > 0 { exit(1) }
}

