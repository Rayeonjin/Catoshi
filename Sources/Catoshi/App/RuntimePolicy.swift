import Foundation

/// Centralized resource policy for an always-on menu-bar app.
///
/// Catoshi intentionally keeps raw exchange sockets live while publishing to SwiftUI
/// at a human-readable cadence. Keeping these values in one place makes performance
/// regressions visible during review instead of scattering wake-up intervals through
/// several models and socket clients.
enum CatoshiRuntimePolicy {
    /// Menu-bar publication while the popover is closed. Raw WebSocket packets are
    /// still consumed immediately; only the newest value crosses to MainActor.
    static let backgroundUIInterval: TimeInterval = 1.0

    /// The open popover gets a quicker but still human-readable cadence.
    static let foregroundUIInterval: TimeInterval = 0.5

    /// Fallback cadence for any tick already queued as the display turns off. Normal
    /// screen-sleep handling suspends the ticker sockets entirely.
    static let displaySleepUIInterval: TimeInterval = 60.0

    /// One shared app-level supervisor replaces per-socket watchdog wakeups.
    static let feedHealthInterval: TimeInterval = 10.0
    static let feedHealthTolerance: TimeInterval = 2.5
    static let healthDisplayStaleThreshold: TimeInterval = 20.0
    static let staleFeedThreshold: TimeInterval = 24.0

    /// Socket keep-alive checks piggyback on the shared health supervisor instead of
    /// owning two additional repeating timers. Active ticker traffic suppresses pings;
    /// an idle connected socket gets at most one probe per minimum interval.
    static let socketIdlePingThreshold: TimeInterval = 18.0
    static let socketPingMinimumInterval: TimeInterval = 30.0

    /// 24h references and optional sparklines do not need five-minute polling. Ten
    /// minutes halves the auxiliary REST traffic while keeping 24h comparisons useful.
    static let referenceRefreshInterval: TimeInterval = 10 * 60
    static let referenceRetryInterval: TimeInterval = 60
    static let sparklineRefreshInterval: TimeInterval = 10 * 60

    /// Avoid shifting the five-minute momentum array on every one-second sample.
    static let momentumPruneInterval: TimeInterval = 30.0
}
