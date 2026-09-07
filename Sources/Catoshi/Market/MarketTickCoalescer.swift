import Foundation

struct BinanceTickSnapshot: Sendable {
    let price: Double
    let change24h: Double
    let receivedAt: Date
}

struct UpbitTickSnapshot: Sendable {
    let price: Double
    let receivedAt: Date
}

struct MarketTickBatch: Sendable {
    let binance: BinanceTickSnapshot?
    let upbitBTC: UpbitTickSnapshot?
    let upbitUSDT: UpbitTickSnapshot?

    var hasUpbit: Bool { upbitBTC != nil || upbitUSDT != nil }

    var latestUpbitReceivedAt: Date? {
        switch (upbitBTC?.receivedAt, upbitUSDT?.receivedAt) {
        case let (btc?, usdt?): return max(btc, usdt)
        case let (btc?, nil): return btc
        case let (nil, usdt?): return usdt
        case (nil, nil): return nil
        }
    }

    var isEmpty: Bool {
        binance == nil && !hasUpbit
    }
}

/// Coalesces bursty exchange WebSocket callbacks before they cross onto MainActor.
///
/// Raw socket messages are still consumed immediately. Only UI/model publication is
/// rate-limited, and each flush keeps the newest sample for every tracked stream. This
/// prevents a high-frequency Upbit stream from creating one MainActor task and one
/// SwiftUI invalidation per packet when the menu-bar text can only be read a few times
/// per second anyway.
final class MarketTickCoalescer: @unchecked Sendable {
    private let queue = DispatchQueue(label: "Catoshi.MarketTickCoalescer", qos: .utility)
    private var pendingBinance: BinanceTickSnapshot?
    private var pendingUpbitBTC: UpbitTickSnapshot?
    private var pendingUpbitUSDT: UpbitTickSnapshot?

    /// Keep one resumed timer source for the coalescer lifetime and re-arm it instead
    /// of allocating/cancelling a new DispatchSourceTimer every 0.5-1 second. A closed
    /// popover used to create up to roughly 3,600 one-shot timer sources per hour.
    private var flushTimer: DispatchSourceTimer?
    private var flushTimerArmed = false
    private var lastFlushUptimeNanoseconds: UInt64?

    private var foregroundUIVisible = false
    private var displayActive = true
    private var minimumInterval: TimeInterval = CatoshiRuntimePolicy.backgroundUIInterval

    private var onFlush: ((MarketTickBatch) -> Void)?

    init() {
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.setEventHandler { [weak self] in
            self?.flushLocked()
        }
        // A resumed dispatch source must never be left suspended at teardown. Park it
        // in the distant future until the first pending tick arms a real deadline.
        timer.schedule(deadline: .distantFuture, repeating: .never)
        timer.resume()
        flushTimer = timer
    }

    deinit {
        flushTimer?.setEventHandler {}
        flushTimer?.cancel()
    }

    func setOnFlush(_ callback: @escaping (MarketTickBatch) -> Void) {
        queue.sync {
            onFlush = callback
        }
    }

    func stop() {
        queue.sync {
            disarmFlushTimerLocked()
            flushTimer?.setEventHandler {}
            flushTimer?.cancel()
            flushTimer = nil
            pendingBinance = nil
            pendingUpbitBTC = nil
            pendingUpbitUSDT = nil
            onFlush = nil
        }
    }

    func setForegroundUIVisible(_ visible: Bool) {
        queue.async { [weak self] in
            guard let self else { return }
            self.foregroundUIVisible = visible
            self.updateIntervalLocked()
        }
    }

    func setDisplayActive(_ active: Bool) {
        queue.async { [weak self] in
            guard let self else { return }
            self.displayActive = active
            self.updateIntervalLocked()
        }
    }

    private func updateIntervalLocked() {
        let previousInterval = minimumInterval
        if !displayActive {
            minimumInterval = CatoshiRuntimePolicy.displaySleepUIInterval
        } else if foregroundUIVisible {
            minimumInterval = CatoshiRuntimePolicy.foregroundUIInterval
        } else {
            minimumInterval = CatoshiRuntimePolicy.backgroundUIInterval
        }

        // If the display wakes or the popover opens while a long low-power flush is
        // pending, re-arm the same timer against the faster cadence so fresh prices
        // appear promptly. Slower transitions are allowed to finish one already queued
        // flush; the ticker sockets are suspended on display sleep immediately after.
        if minimumInterval < previousInterval,
           flushTimerArmed,
           hasPendingTicksLocked() {
            armFlushTimerLocked()
        }
    }

    func submitBinance(price: Double, change24h: Double, receivedAt: Date = Date()) {
        queue.async { [weak self] in
            guard let self else { return }
            self.pendingBinance = BinanceTickSnapshot(
                price: price,
                change24h: change24h,
                receivedAt: receivedAt
            )
            self.scheduleFlushLocked()
        }
    }

    func submitUpbit(code: String, price: Double, receivedAt: Date = Date()) {
        queue.async { [weak self] in
            guard let self else { return }
            let snapshot = UpbitTickSnapshot(price: price, receivedAt: receivedAt)
            switch code {
            case "KRW-BTC": self.pendingUpbitBTC = snapshot
            case "KRW-USDT": self.pendingUpbitUSDT = snapshot
            default: return
            }
            self.scheduleFlushLocked()
        }
    }

    private func scheduleFlushLocked() {
        guard !flushTimerArmed else { return }
        armFlushTimerLocked()
    }

    private func armFlushTimerLocked() {
        guard let flushTimer else { return }

        let delay = nextFlushDelayLocked()
        let delayMilliseconds = max(0, Int((delay * 1_000).rounded()))
        let leewayMilliseconds: Int
        if !displayActive {
            leewayMilliseconds = 1_000
        } else if foregroundUIVisible {
            leewayMilliseconds = 30
        } else {
            leewayMilliseconds = 100
        }

        flushTimerArmed = true
        flushTimer.schedule(
            deadline: .now() + .milliseconds(delayMilliseconds),
            repeating: .never,
            leeway: .milliseconds(leewayMilliseconds)
        )
    }

    private func nextFlushDelayLocked(nowUptimeNanoseconds: UInt64 = DispatchTime.now().uptimeNanoseconds) -> TimeInterval {
        guard let lastFlushUptimeNanoseconds else { return 0 }
        let elapsedNanoseconds = nowUptimeNanoseconds >= lastFlushUptimeNanoseconds
            ? nowUptimeNanoseconds - lastFlushUptimeNanoseconds
            : 0
        let elapsed = TimeInterval(elapsedNanoseconds) / 1_000_000_000
        return max(0, minimumInterval - elapsed)
    }

    private func hasPendingTicksLocked() -> Bool {
        pendingBinance != nil || pendingUpbitBTC != nil || pendingUpbitUSDT != nil
    }

    private func disarmFlushTimerLocked() {
        guard flushTimerArmed else { return }
        flushTimerArmed = false
        flushTimer?.schedule(deadline: .distantFuture, repeating: .never)
    }

    private func flushLocked() {
        flushTimerArmed = false

        let batch = MarketTickBatch(
            binance: pendingBinance,
            upbitBTC: pendingUpbitBTC,
            upbitUSDT: pendingUpbitUSDT
        )
        pendingBinance = nil
        pendingUpbitBTC = nil
        pendingUpbitUSDT = nil
        lastFlushUptimeNanoseconds = DispatchTime.now().uptimeNanoseconds

        guard !batch.isEmpty else { return }
        onFlush?(batch)
    }
}
