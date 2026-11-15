import Foundation

/// Bounded relaunch policy for the external `codex app-server` child process.
///
/// The client relaunches that child whenever it exits, stops answering, or the
/// Codex CLI is replaced by an app update. Relaunching is what keeps the menu bar
/// reading alive, but an unbounded relaunch turns a changed CLI handshake or an
/// expired login into an endless fork/exec loop that the user never sees.
///
/// This policy puts a ceiling on that work: exponential backoff, a hard delay
/// cap, and a slow sustained probe once the fast attempts are exhausted. Any
/// successful handshake resets it, so an ordinary Codex restart still recovers
/// within a couple of seconds.
struct RestartPolicy {
    let baseDelay: TimeInterval
    let maxDelay: TimeInterval
    let maxAttempts: Int
    let sustainedDelay: TimeInterval

    private(set) var attempts = 0

    init(
        baseDelay: TimeInterval = 2,
        maxDelay: TimeInterval = 60,
        maxAttempts: Int = 6,
        sustainedDelay: TimeInterval = 300
    ) {
        precondition(baseDelay > 0, "baseDelay must be positive")
        precondition(maxDelay >= baseDelay, "maxDelay must not be shorter than baseDelay")
        precondition(maxAttempts >= 0, "maxAttempts must not be negative")
        precondition(sustainedDelay >= maxDelay, "sustainedDelay must not be shorter than maxDelay")
        self.baseDelay = baseDelay
        self.maxDelay = maxDelay
        self.maxAttempts = maxAttempts
        self.sustainedDelay = sustainedDelay
    }

    /// True once the fast retries are spent and the policy only probes slowly.
    var isSustained: Bool { attempts >= maxAttempts }

    /// Delay before the next relaunch, and records that attempt.
    mutating func nextDelay() -> TimeInterval {
        let delay: TimeInterval
        if isSustained {
            delay = sustainedDelay
        } else {
            delay = min(baseDelay * pow(2, Double(attempts)), maxDelay)
        }
        attempts += 1
        return delay
    }

    /// A successful handshake clears the failure history.
    mutating func recordSuccess() {
        attempts = 0
    }
}
