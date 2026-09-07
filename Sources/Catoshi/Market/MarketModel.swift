import Combine
import Foundation
import Network

struct Quote {
    let price: Double
    let change24h: Double?
}

struct PremiumSnapshot {
    let value: Double
    let change24h: Double?
}

struct Reference24h {
    let binanceBTCUSDT: Double
    let upbitBTCKRW: Double
    let upbitUSDTKRW: Double
}

struct HistoricalSeries {
    let binanceBTCUSDT: [Double]
    let upbitBTCKRW: [Double]
    let premium: [Double]
}

struct TimestampedPrice {
    let date: Date
    let price: Double
}

@MainActor
final class MarketModel: ObservableObject {
    @Published var binanceBTC: Quote?
    @Published var upbitBTC: Quote?
    // Supporting feed timestamps/USDT quote do not need their own objectWillChange
    // emissions. Visible price/premium updates already invalidate the UI, while the
    // shared low-frequency health supervisor reads these plain values when it needs them.
    var upbitUSDTKRW: Double?
    @Published var premium: PremiumSnapshot?
    var updatedAt: Date?
    @Published var binanceState: SocketConnectionState = .connecting
    @Published var upbitState: SocketConnectionState = .connecting
    var binanceLastTickAt: Date?
    var upbitLastTickAt: Date?
    @Published var networkAvailable = true
    @Published var binanceSparkline: [Double] = []
    @Published var upbitSparkline: [Double] = []
    @Published var premiumSparkline: [Double] = []
    @Published var menuBarLayoutSignature = "$--- │ ₩--- │ -- │ ●"
    @Published var showMenuBarBinance: Bool {
        didSet {
            Self.preferences.set(showMenuBarBinance, for: .showMenuBarBinance)
            refreshMenuBarLayoutSignature()
            configureSparklineRefresh()
        }
    }
    @Published var showMenuBarUpbit: Bool {
        didSet {
            Self.preferences.set(showMenuBarUpbit, for: .showMenuBarUpbit)
            refreshMenuBarLayoutSignature()
            configureSparklineRefresh()
        }
    }
    @Published var showMenuBarPremium: Bool {
        didSet {
            Self.preferences.set(showMenuBarPremium, for: .showMenuBarPremium)
            refreshMenuBarLayoutSignature()
            configureSparklineRefresh()
        }
    }
    @Published var showMenuBarBinanceSparkline: Bool {
        didSet {
            Self.preferences.set(showMenuBarBinanceSparkline, for: .showMenuBarBinanceSparkline)
            configureSparklineRefresh()
        }
    }
    @Published var showMenuBarUpbitSparkline: Bool {
        didSet {
            Self.preferences.set(showMenuBarUpbitSparkline, for: .showMenuBarUpbitSparkline)
            configureSparklineRefresh()
        }
    }
    @Published var showMenuBarPremiumSparkline: Bool {
        didSet {
            Self.preferences.set(showMenuBarPremiumSparkline, for: .showMenuBarPremiumSparkline)
            configureSparklineRefresh()
        }
    }
    @Published var showMenuBarBinance24h: Bool {
        didSet {
            Self.preferences.set(showMenuBarBinance24h, for: .showMenuBarBinance24h)
            refreshMenuBarLayoutSignature()
        }
    }
    @Published var showMenuBarUpbit24h: Bool {
        didSet {
            Self.preferences.set(showMenuBarUpbit24h, for: .showMenuBarUpbit24h)
            refreshMenuBarLayoutSignature()
        }
    }
    @Published var showMenuBarPremium24h: Bool {
        didSet {
            Self.preferences.set(showMenuBarPremium24h, for: .showMenuBarPremium24h)
            refreshMenuBarLayoutSignature()
        }
    }
    @Published var displayPalette: DisplayPalette {
        didSet {
            Self.preferences.set(displayPalette.rawValue, for: .displayPalette)
        }
    }

    @Published var appLanguage: AppLanguage {
        didSet {
            Self.preferences.set(appLanguage.rawValue, for: .appLanguage)
        }
    }

    @Published var appAppearance: AppAppearance {
        didSet {
            Self.preferences.set(appAppearance.rawValue, for: .appAppearance)
        }
    }

    @Published var catoshiCoat: CatoshiCoat {
        didSet {
            Self.preferences.set(catoshiCoat.rawValue, for: .catoshiCoat)
            catoshiMotion.restartAnimationClock()
        }
    }

    @Published var showCatoshi: Bool {
        didSet {
            Self.preferences.set(showCatoshi, for: .showCatoshi)
            guard oldValue != showCatoshi else { return }
            configureCatoshiRuntimeTasks()
        }
    }
    @Published var catoshiAnimationEnabled: Bool {
        didSet {
            Self.preferences.set(catoshiAnimationEnabled, for: .catoshiAnimationEnabled)
            guard oldValue != catoshiAnimationEnabled else { return }
            configureCatoshiRuntimeTasks()
        }
    }
    @Published var catoshiRandomLifeEnabled: Bool = true {
        didSet {
            Self.preferences.set(catoshiRandomLifeEnabled, for: .catoshiRandomLifeEnabled)
            guard oldValue != catoshiRandomLifeEnabled else { return }
            configureCatoshiRuntimeTasks()
        }
    }
    @Published var catoshiMarketReactionsEnabled: Bool = true {
        didSet {
            Self.preferences.set(catoshiMarketReactionsEnabled, for: .catoshiMarketReactionsEnabled)
            if !catoshiMarketReactionsEnabled {
                catoshiReactionLatch = nil
                lastCatoshiTriggerSeverity = 0
            }
        }
    }
    @Published var catoshiActivity: CatoshiActivity = .normal {
        didSet { Self.preferences.set(catoshiActivity.rawValue, for: .catoshiActivity) }
    }
    @Published var catoshiSensitivity: CatoshiSensitivity {
        didSet {
            Self.preferences.set(catoshiSensitivity.rawValue, for: .catoshiSensitivity)
            catoshiReactionLatch = nil
            lastCatoshiTriggerSeverity = 0
        }
    }
    @Published var catoshiCooldown: CatoshiCooldown {
        didSet { Self.preferences.set(catoshiCooldown.rawValue, for: .catoshiCooldown) }
    }
    @Published var catoshiDropReactionEnabled: Bool {
        didSet {
            Self.preferences.set(catoshiDropReactionEnabled, for: .catoshiDropReactionEnabled)
            if !catoshiDropReactionEnabled, let latch = catoshiReactionLatch, catoshiReactionDirection(latch) < 0 {
                catoshiReactionLatch = nil
                lastCatoshiTriggerSeverity = 0
            }
        }
    }
    let catoshiMotion = CatoshiMotionModel()

    @Published var fiveMinuteChange: Double?

    private static let preferences = PreferenceStore()
    let marketContext: MarketContextModel
    private let binance = BinanceTickerClient()
    private let upbit = UpbitTickerClient()
    private let history = HistoricalReferenceService()
    private let tickCoalescer = MarketTickCoalescer()
    private let pathMonitor = NWPathMonitor()
    private let pathMonitorQueue = DispatchQueue(label: "Catoshi.NetworkPath", qos: .utility)
    private var reference24h: Reference24h?
    private var referenceTask: Task<Void, Never>?
    private var sparklineTask: Task<Void, Never>?
    private var momentumSeedTask: Task<Void, Never>?
    private var catoshiResetTask: Task<Void, Never>?
    private var catoshiLifeTask: Task<Void, Never>?
    private var catoshiMicroTask: Task<Void, Never>?
    private var wakeRecoveryTask: Task<Void, Never>?
    private var recentBinancePrices: [TimestampedPrice] = []
    private var lastMomentumPruneAt = Date.distantPast
    private var displayActive = true
    private let momentumWindow: TimeInterval = 5 * 60
    private let momentumRetention: TimeInterval = 7 * 60
    private let momentumReferenceTolerance: TimeInterval = 90
    private var lastMomentumSeedAttemptAt = Date.distantPast
    private var lastCatoshiTriggerAt: Date?
    private var lastCatoshiTriggerSeverity = 0
    private var catoshiReactionLatch: CatoshiState?
    private var catoshiScriptedMicroActive = false
    private var catoshiMicroGeneration: UInt = 0
    private var catoshiMarketReactionActive = false
    private let modelStartedAt = Date()
    private var catoshiTerritoryMaxX: CGFloat = 0
    private var catoshiWaypointOffsets: [CGFloat] = []

    init(startsBackgroundTasks: Bool = true) {
        marketContext = MarketContextModel(startsBackgroundTasks: startsBackgroundTasks)
        let preferences = Self.preferences
        catoshiCoat = preferences.stringEnum(.catoshiCoat, default: .calico)
        showCatoshi = preferences.bool(.showCatoshi, default: true)
        catoshiAnimationEnabled = preferences.bool(.catoshiAnimationEnabled, default: true)
        catoshiSensitivity = preferences.stringEnum(.catoshiSensitivity, default: .normal)
        catoshiCooldown = preferences.intEnum(.catoshiCooldown, default: .twoMinutes)
        catoshiDropReactionEnabled = preferences.bool(.catoshiDropReactionEnabled, default: true)
        catoshiRandomLifeEnabled = preferences.bool(.catoshiRandomLifeEnabled, default: true)
        catoshiMarketReactionsEnabled = preferences.bool(.catoshiMarketReactionsEnabled, default: true)
        catoshiActivity = preferences.stringEnum(.catoshiActivity, default: .normal)

        showMenuBarBinance = preferences.bool(.showMenuBarBinance, default: true)
        showMenuBarUpbit = preferences.bool(.showMenuBarUpbit, default: true)
        showMenuBarPremium = preferences.bool(.showMenuBarPremium, default: true)
        showMenuBarBinanceSparkline = preferences.bool(.showMenuBarBinanceSparkline, default: false)
        showMenuBarUpbitSparkline = preferences.bool(.showMenuBarUpbitSparkline, default: false)
        showMenuBarPremiumSparkline = preferences.bool(.showMenuBarPremiumSparkline, default: false)
        showMenuBarBinance24h = preferences.bool(.showMenuBarBinance24h, default: true)
        showMenuBarUpbit24h = preferences.bool(.showMenuBarUpbit24h, default: true)
        showMenuBarPremium24h = preferences.bool(.showMenuBarPremium24h, default: true)

        displayPalette = preferences.stringEnum(.displayPalette, default: .color)
        appLanguage = preferences.stringEnum(.appLanguage, default: .korean)
        appAppearance = preferences.stringEnum(.appAppearance, default: .system)

        binance.onState = { [weak self] state in
            Task { @MainActor in
                guard let self, self.binanceState != state else { return }
                self.binanceState = state
            }
        }

        upbit.onState = { [weak self] state in
            Task { @MainActor in
                guard let self, self.upbitState != state else { return }
                self.upbitState = state
            }
        }

        tickCoalescer.setOnFlush { [weak self] batch in
            Task { @MainActor in
                self?.applyTickBatch(batch)
            }
        }

        let tickBuffer = tickCoalescer
        binance.onTicker = { price, change in
            tickBuffer.submitBinance(price: price, change24h: change)
        }

        upbit.onTicker = { code, price in
            tickBuffer.submitUpbit(code: code, price: price)
        }

        pathMonitor.pathUpdateHandler = { [weak self] path in
            Task { @MainActor in
                guard let self else { return }
                let available = path.status == .satisfied
                let wasAvailable = self.networkAvailable
                if self.networkAvailable != available {
                    self.networkAvailable = available
                }

                // Stop retry loops and auxiliary polling while the Mac is offline.
                // NWPathMonitor becomes the single source of truth for resuming work.
                // The screen can be off while the Mac itself remains awake. There is
                // no value in keeping high-frequency public ticker sockets alive when
                // nothing can be seen, so socket runtime follows both network and display.
                let socketRuntimeAvailable = available && self.displayActive
                self.binance.setNetworkAvailable(socketRuntimeAvailable)
                self.upbit.setNetworkAvailable(socketRuntimeAvailable)
                self.marketContext.setNetworkAvailable(available)

                if available && !wasAvailable && self.displayActive {
                    self.startReferenceRefresh()
                    self.seedMomentumHistory()
                    self.configureSparklineRefresh()
                } else if !available && wasAvailable {
                    self.referenceTask?.cancel()
                    self.referenceTask = nil
                    self.sparklineTask?.cancel()
                    self.sparklineTask = nil
                    self.momentumSeedTask?.cancel()
                    self.momentumSeedTask = nil
                }
            }
        }
        if startsBackgroundTasks {
            pathMonitor.start(queue: pathMonitorQueue)
            binance.start()
            upbit.start()
            startReferenceRefresh()
            seedMomentumHistory()
            configureCatoshiRuntimeTasks()
            configureSparklineRefresh()
        }
    }

    deinit {
        referenceTask?.cancel()
        sparklineTask?.cancel()
        momentumSeedTask?.cancel()
        catoshiResetTask?.cancel()
        catoshiLifeTask?.cancel()
        catoshiMicroTask?.cancel()
        wakeRecoveryTask?.cancel()
        pathMonitor.cancel()
    }

    func prepareForTermination() {
        referenceTask?.cancel()
        referenceTask = nil
        sparklineTask?.cancel()
        sparklineTask = nil
        momentumSeedTask?.cancel()
        momentumSeedTask = nil
        catoshiResetTask?.cancel()
        catoshiResetTask = nil
        catoshiLifeTask?.cancel()
        catoshiLifeTask = nil
        catoshiMicroTask?.cancel()
        catoshiMicroTask = nil
        wakeRecoveryTask?.cancel()
        wakeRecoveryTask = nil
        marketContext.prepareForTermination()
        tickCoalescer.stop()
        pathMonitor.cancel()
        binance.stop()
        upbit.stop()
    }

    /// Publishes at most one consolidated MainActor update per coalescer interval.
    /// Binance and both Upbit symbols are applied together, so premium calculation and
    /// SwiftUI invalidation happen once per batch rather than once per raw socket packet.
    private func applyTickBatch(_ batch: MarketTickBatch) {
        var binanceTickDate: Date?
        var premiumInputsChanged = false

        if let tick = batch.binance {
            binanceLastTickAt = tick.receivedAt
            if quoteDiffers(binanceBTC, price: tick.price, change24h: tick.change24h) {
                binanceBTC = Quote(price: tick.price, change24h: tick.change24h)
                premiumInputsChanged = true
            }
            // Keep momentum timestamps moving even when several trades/ticker packets
            // repeat the same visible price. The sliding 5m reference can still change.
            recordBinancePrice(tick.price, at: tick.receivedAt)
            binanceTickDate = tick.receivedAt
        }

        if batch.hasUpbit {
            if let latestUpbitDate = batch.latestUpbitReceivedAt {
                upbitLastTickAt = latestUpbitDate
            }

            if let tick = batch.upbitBTC {
                let change = reference24h.flatMap {
                    percentChange(current: tick.price, previous: $0.upbitBTCKRW)
                }
                if quoteDiffers(upbitBTC, price: tick.price, change24h: change) {
                    upbitBTC = Quote(price: tick.price, change24h: change)
                    premiumInputsChanged = true
                }
            }

            if let tick = batch.upbitUSDT, upbitUSDTKRW != tick.price {
                upbitUSDTKRW = tick.price
                premiumInputsChanged = true
            }
        }

        if let binanceTickDate {
            updateFiveMinuteChange(now: binanceTickDate)
        }

        // Premium and status-item layout only depend on the three price inputs above.
        // Repeated same-price packets are common enough on active markets that avoiding
        // the formatting/premium path here saves permanent MainActor work without
        // changing feed timestamps, momentum sampling or connection-health behavior.
        if premiumInputsChanged {
            recalculate()
        } else if binanceBTC != nil, upbitBTC != nil, upbitUSDTKRW != nil {
            // Preserve the previous last-feed-time semantics without rebuilding premium
            // or the status-bar layout for a packet whose visible values are identical.
            // `updatedAt` is intentionally not @Published.
            updatedAt = Date()
        }
    }

    private func quoteDiffers(_ current: Quote?, price: Double, change24h: Double?) -> Bool {
        guard let current else { return true }
        return current.price != price || current.change24h != change24h
    }

    /// Pauses visible and high-frequency runtime work when macOS turns the display off.
    /// Public ticker sockets are suspended too: no user can see the menu bar while the
    /// display sleeps, and reconnecting them on wake is cheaper than processing hours of
    /// unseen ticks on a laptop. Network reachability itself continues to be monitored.
    func setDisplayActive(_ active: Bool) {
        guard displayActive != active else { return }
        displayActive = active
        tickCoalescer.setDisplayActive(active)
        marketContext.setDisplayActive(active)
        binance.setNetworkAvailable(networkAvailable && active)
        upbit.setNetworkAvailable(networkAvailable && active)
        configureCatoshiRuntimeTasks()

        if active {
            startReferenceRefresh()
            seedMomentumHistory()
            configureSparklineRefresh()
        } else {
            wakeRecoveryTask?.cancel()
            wakeRecoveryTask = nil
            referenceTask?.cancel()
            referenceTask = nil
            sparklineTask?.cancel()
            sparklineTask = nil
            momentumSeedTask?.cancel()
            momentumSeedTask = nil
        }
    }

    /// The popover gets a slightly quicker UI cadence while visible. Raw market data
    /// continues to stream at the exchange rate in both modes; only publication to the
    /// observable UI model changes.
    func setPopoverVisible(_ visible: Bool) {
        tickCoalescer.setForegroundUIVisible(visible)
    }

    private func seedMomentumHistory() {
        guard networkAvailable, displayActive else { return }
        let now = Date()
        guard now.timeIntervalSince(lastMomentumSeedAttemptAt) >= 60 else { return }
        lastMomentumSeedAttemptAt = now

        momentumSeedTask?.cancel()
        momentumSeedTask = Task { [weak self] in
            guard let self else { return }
            do {
                let points = try await self.history.fetchRecentBinanceMinutePrices(count: 7)
                guard !Task.isCancelled else { return }
                self.mergeMomentumSeed(points)
                self.updateFiveMinuteChange()
            } catch {
                // The live WebSocket ring buffer becomes sufficient after five minutes.
                // A later live tick may request another one-off seed after the throttle
                // interval if a long connection gap still leaves no valid reference.
            }
        }
    }

    private func mergeMomentumSeed(_ points: [TimestampedPrice]) {
        guard !points.isEmpty else { return }
        let firstLiveDate = recentBinancePrices.first?.date
        let historical = points.filter { point in
            guard let firstLiveDate else { return true }
            return point.date < firstLiveDate
        }
        recentBinancePrices = (historical + recentBinancePrices).sorted { $0.date < $1.date }
        pruneMomentumHistory(now: Date())
    }

    private func recordBinancePrice(_ price: Double, at date: Date) {
        // Five-minute momentum does not benefit from 2-4 samples per second. Keep at
        // most one point per second to reduce array churn while preserving ample
        // precision for the 90-second reference tolerance.
        if let last = recentBinancePrices.last, date.timeIntervalSince(last.date) < 1.0 {
            recentBinancePrices[recentBinancePrices.count - 1] = TimestampedPrice(date: date, price: price)
        } else {
            recentBinancePrices.append(TimestampedPrice(date: date, price: price))
        }
        if date.timeIntervalSince(lastMomentumPruneAt) >= CatoshiRuntimePolicy.momentumPruneInterval || recentBinancePrices.count > 900 {
            pruneMomentumHistory(now: date)
        }
    }

    private func pruneMomentumHistory(now: Date) {
        lastMomentumPruneAt = now
        let cutoff = now.addingTimeInterval(-momentumRetention)
        if let firstKept = recentBinancePrices.firstIndex(where: { $0.date >= cutoff }) {
            if firstKept > 0 { recentBinancePrices.removeFirst(firstKept) }
        } else if !recentBinancePrices.isEmpty {
            recentBinancePrices.removeAll(keepingCapacity: true)
        }
    }

    private func updateFiveMinuteChange(now: Date = Date()) {
        guard let current = binanceBTC?.price else { return }
        let target = now.addingTimeInterval(-momentumWindow)

        // Prefer the latest sample at or before the five-minute target. Startup
        // candles cover the first few minutes; afterward the reference comes from the
        // live Binance WebSocket ring buffer. If a long connection gap leaves the
        // reference too old, request a throttled one-off REST reseed instead of showing
        // a misleading 5-minute move.
        guard let reference = momentumReference(atOrBefore: target),
              target.timeIntervalSince(reference.date) <= momentumReferenceTolerance,
              reference.price > 0 else {
            if fiveMinuteChange != nil { fiveMinuteChange = nil }
            seedMomentumHistory()
            return
        }

        let change = ((current / reference.price) - 1.0) * 100.0
        // The UI renders two decimals. Ignore sub-0.005pp publication noise while
        // still evaluating the raw move for Catoshi's reaction thresholds.
        if fiveMinuteChange.map({ abs($0 - change) >= 0.005 }) ?? true {
            fiveMinuteChange = change
        }
        evaluateCatoshiMomentum(change)
    }

    /// Finds the newest sample at or before the target in O(log n). The live buffer is
    /// kept sorted and normally contains roughly seven minutes of one-second samples;
    /// avoiding a reverse linear scan removes a small but permanent cost from the
    /// 1-2 Hz always-on tick publication path.
    private func momentumReference(atOrBefore target: Date) -> TimestampedPrice? {
        guard !recentBinancePrices.isEmpty else { return nil }

        var low = 0
        var high = recentBinancePrices.count
        while low < high {
            let mid = low + (high - low) / 2
            if recentBinancePrices[mid].date <= target {
                low = mid + 1
            } else {
                high = mid
            }
        }

        let index = low - 1
        return index >= 0 ? recentBinancePrices[index] : nil
    }

    private func setCatoshiState(_ state: CatoshiState) {
        catoshiMotion.transition(to: state)
    }

    func updateCatoshiTerritory(maxOffset: CGFloat) {
        let sanitized = max(0, maxOffset)
        guard abs(sanitized - catoshiTerritoryMaxX) > 0.5 else { return }
        catoshiTerritoryMaxX = sanitized

        // Display settings can shrink the territory while the cat is away from HOME.
        // Clamp it back inside the newly visible range without changing market values'
        // layout. This update happens only when the status-item width changes.
        if catoshiMotion.positionX > sanitized {
            catoshiMotion.setPosition(sanitized, duration: 0.16)
        }
    }

    /// Receives stop locations measured from the real status-bar separators. The UI
    /// converts separator centers into mascot offsets, so navigation points keep their
    /// semantic meaning even when prices, 24h changes or sparklines change width.
    func updateCatoshiWaypoints(_ offsets: [CGFloat]) {
        // Store raw non-negative offsets because preference delivery order is not
        // guaranteed. They are clamped against the latest territory width when a route
        // is actually built, so a waypoint update arriving before width measurement is
        // still preserved.
        let sorted = offsets.map { max(0, $0) }.sorted()
        var deduplicated: [CGFloat] = []
        for value in sorted where deduplicated.last.map({ abs($0 - value) > 2 }) ?? true {
            deduplicated.append(value)
        }
        guard deduplicated != catoshiWaypointOffsets else { return }
        catoshiWaypointOffsets = deduplicated
    }

    private func sanitizedWaypointOffsets(_ offsets: [CGFloat]) -> [CGFloat] {
        guard catoshiTerritoryMaxX > 0 else { return [] }
        let sorted = offsets
            .map { min(catoshiTerritoryMaxX, max(0, $0)) }
            .filter { $0 > 4 && $0 < catoshiTerritoryMaxX - 2 }
            .sorted()

        var result: [CGFloat] = []
        for value in sorted where result.last.map({ abs($0 - value) > 7 }) ?? true {
            result.append(value)
        }
        return result
    }

    private var hasRoamingTerritory: Bool {
        catoshiTerritoryMaxX > 4
    }

    /// HOME is x=0. A small doorstep point keeps most ordinary walks local. Remaining
    /// points come from real market separators, with the visible far edge as the final
    /// rare destination. This turns the menu bar into a route instead of one long rail.
    private var catoshiNavigationWaypoints: [CGFloat] {
        guard hasRoamingTerritory else { return [0] }

        var points: [CGFloat] = [0]
        let doorstep = min(18, max(8, catoshiTerritoryMaxX * 0.10))
        if doorstep < catoshiTerritoryMaxX - 7 { points.append(doorstep) }
        points.append(contentsOf: sanitizedWaypointOffsets(catoshiWaypointOffsets))
        points.append(catoshiTerritoryMaxX)

        var deduplicated: [CGFloat] = []
        for point in points.sorted() where deduplicated.last.map({ abs($0 - point) > 7 }) ?? true {
            deduplicated.append(point)
        }
        return deduplicated
    }

    private enum CatoshiExcursion {
        case patrol
        case curious
        case happy
    }

    /// HOME remains the resting base, but ordinary patrols should visibly use the
    /// menu-bar territory. Nearby stops are still preferred while Upbit/premium visits
    /// happen often enough to make the whole strip feel inhabited rather than decorative.
    private func catoshiExcursionTarget(_ excursion: CatoshiExcursion) -> CGFloat {
        let candidates = Array(catoshiNavigationWaypoints.dropFirst())
        guard !candidates.isEmpty else { return 0 }
        guard candidates.count > 1 else { return candidates[0] }

        let baseWeights: [Double]
        switch excursion {
        case .patrol:
            baseWeights = [32, 28, 21, 13, 6]
        case .curious:
            baseWeights = [18, 24, 27, 20, 11]
        case .happy:
            baseWeights = [12, 20, 26, 25, 17]
        }

        let tailWeight = baseWeights.last ?? 1
        var weights: [Double] = []
        for index in candidates.indices {
            if index < baseWeights.count {
                weights.append(baseWeights[index])
            } else {
                weights.append(max(0.25, tailWeight / Double(index - baseWeights.count + 2)))
            }
        }

        let total = weights.reduce(0, +)
        var roll = Double.random(in: 0..<total)
        for (index, weight) in weights.enumerated() {
            if roll < weight { return candidates[index] }
            roll -= weight
        }
        return candidates[0]
    }

    private func fleeEdgeTarget() -> CGFloat {
        // HOME is the safe resting space immediately to the left of Binance.
        0
    }

    private func sleepCatoshi(_ seconds: Double) async -> Bool {
        try? await Task.sleep(for: .seconds(seconds))
        return !Task.isCancelled
    }

    /// Resting poses should not snap directly into locomotion. A short get-up sequence
    /// gives the body time to shift from seated/loafed weight into a standing silhouette.
    private func standCatoshiIfNeeded() async -> Bool {
        switch catoshiMotion.state {
        case .sit, .loaf, .sleep:
            setCatoshiState(.standUp)
            return await sleepCatoshi(0.43)
        default:
            return true
        }
    }

    /// The reverse transition is used after arriving at a waypoint or HOME. It is kept
    /// intentionally short so it reads as weight transfer, not as a separate trick.
    @discardableResult
    private func settleCatoshiIntoSit() async -> Bool {
        if catoshiMotion.state == .sit { return true }
        switch catoshiMotion.state {
        case .idle, .walk, .turn, .standUp, .happy, .zoomies, .rocket, .flee, .stretch, .alert:
            setCatoshiState(.sitDown)
            guard await sleepCatoshi(0.43) else { return false }
            setCatoshiState(.sit)
            return true
        default:
            setCatoshiState(.sit)
            return !Task.isCancelled
        }
    }

    /// A dedicated three-frame pivot now masks the facing change. The front-facing
    /// middle frame is where the mirror direction changes, so the cat turns through its
    /// body instead of behaving like a card being flipped around the Y axis.
    private func turnCatoshiIfNeeded(toward target: CGFloat, movingState: CatoshiState) async -> Bool {
        let delta = target - catoshiMotion.positionX
        guard abs(delta) > 0.3 else { return true }
        let desiredFacing: CGFloat = delta >= 0 ? 1 : -1
        guard desiredFacing != catoshiMotion.facing else { return true }

        let sprinting = movingState == .zoomies || movingState == .rocket || movingState == .flee
        setCatoshiState(.turn)

        if sprinting {
            guard await sleepCatoshi(0.08) else { return false }
            catoshiMotion.setFacing(desiredFacing)
            guard await sleepCatoshi(0.11) else { return false }
        } else {
            // At 8 fps this flips direction during turn2, the narrow/front-facing pose.
            guard await sleepCatoshi(0.14) else { return false }
            catoshiMotion.setFacing(desiredFacing)
            guard await sleepCatoshi(0.22) else { return false }
        }

        setCatoshiState(movingState)
        return !Task.isCancelled
    }

    /// Advances one locomotion frame at a time. Each frame moves a fixed number of
    /// points and the SwiftUI offset animation lasts exactly that frame interval. This
    /// explicitly couples paws and horizontal displacement and removes long easing
    /// glides from ordinary walking.
    @discardableResult
    private func moveCatoshiNaturally(
        to target: CGFloat,
        movingState: CatoshiState,
        strideScale: Double = 1.0
    ) async -> Bool {
        let clamped = min(catoshiTerritoryMaxX, max(0, target))
        guard abs(clamped - catoshiMotion.positionX) > 0.3 else { return true }
        guard await standCatoshiIfNeeded() else { return false }
        guard await turnCatoshiIfNeeded(toward: clamped, movingState: movingState) else { return false }
        if catoshiMotion.state != movingState { setCatoshiState(movingState) }

        let frameInterval = max(0.06, movingState.travelFrameInterval)
        let stride = max(1.2, CGFloat(movingState.travelPointsPerFrame * max(0.72, strideScale)))
        let direction: CGFloat = clamped >= catoshiMotion.positionX ? 1 : -1

        catoshiMotion.setMoveDuration(frameInterval)

        while abs(clamped - catoshiMotion.positionX) > 0.3 {
            let remaining = abs(clamped - catoshiMotion.positionX)
            let distance = min(stride, remaining)
            catoshiMotion.setPosition(catoshiMotion.positionX + direction * distance)
            guard await sleepCatoshi(frameInterval) else { return false }
        }

        if abs(catoshiMotion.positionX - clamped) > 0.05 {
            catoshiMotion.setPosition(clamped)
        }
        return true
    }

    private func catoshiRoute(to target: CGFloat) -> [CGFloat] {
        let clamped = min(catoshiTerritoryMaxX, max(0, target))
        let current = catoshiMotion.positionX
        guard abs(clamped - current) > 0.3 else { return [] }

        let points = catoshiNavigationWaypoints
        var route: [CGFloat]
        if clamped > current {
            route = points.filter { $0 > current + 1 && $0 <= clamped + 1 }
        } else {
            route = Array(points.filter { $0 < current - 1 && $0 >= clamped - 1 }.reversed())
        }

        if route.last.map({ abs($0 - clamped) > 1 }) ?? true {
            route.append(clamped)
        }
        return route
    }

    @discardableResult
    private func pauseCatoshiAtWaypoint(_ range: ClosedRange<Double> = 0.28...0.62) async -> Bool {
        setCatoshiState(.idle)
        let micro = [CatoshiMicroMotion.blink, .earTwitch, .tailFlick].randomElement() ?? .blink
        catoshiMotion.setMicroMotion(micro, active: true)
        guard await sleepCatoshi(min(Double.random(in: range), 0.42)) else { return false }
        catoshiMotion.clearMicroMotion()
        return await sleepCatoshi(Double.random(in: 0.05...0.12))
    }

    @discardableResult
    private func moveCatoshiViaWaypoints(
        to target: CGFloat,
        movingState: CatoshiState = .walk,
        pauseAtIntermediateStops: Bool = true,
        strideScale: Double = 1.0
    ) async -> Bool {
        let route = catoshiRoute(to: target)
        guard !route.isEmpty else { return true }

        for (index, stop) in route.enumerated() {
            guard await moveCatoshiNaturally(
                to: stop,
                movingState: movingState,
                strideScale: strideScale
            ) else { return false }

            if pauseAtIntermediateStops && index + 1 < route.count {
                guard await pauseCatoshiAtWaypoint() else { return false }
            }
        }
        return true
    }

    @discardableResult
    private func returnCatoshiHome(
        movingState: CatoshiState = .walk,
        pauseAtWaypoints: Bool = true
    ) async -> Bool {
        guard catoshiMotion.positionX > 1 else { return true }
        let sprinting = movingState == .zoomies || movingState == .rocket || movingState == .flee
        if sprinting || !pauseAtWaypoints {
            return await moveCatoshiNaturally(to: 0, movingState: movingState)
        }
        return await moveCatoshiViaWaypoints(to: 0, movingState: movingState, pauseAtIntermediateStops: true)
    }

    /// Full-territory sprints are reserved for explicit market reactions. Fast motion
    /// is therefore meaningful instead of becoming the baseline daily-life behavior.
    @discardableResult
    private func runCatoshiSprints(
        state: CatoshiState,
        passes: Int,
        strideScaleRange: ClosedRange<Double> = 0.95...1.12
    ) async -> Bool {
        guard hasRoamingTerritory else {
            setCatoshiState(state)
            return await sleepCatoshi(Double.random(in: 0.6...1.0))
        }

        var target: CGFloat = catoshiMotion.positionX > catoshiTerritoryMaxX * 0.55
            ? 0
            : catoshiTerritoryMaxX
        for index in 0..<passes {
            let scale = Double.random(in: strideScaleRange)
            guard await moveCatoshiNaturally(to: target, movingState: state, strideScale: scale) else { return false }
            if index + 1 < passes {
                guard await sleepCatoshi(Double.random(in: 0.05...0.12)) else { return false }
                target = target > 0 ? 0 : catoshiTerritoryMaxX
            }
        }
        return true
    }

    /// Daily-life zoomies stay around HOME and the first nearby stop. Crossing the
    /// entire quote strip is intentionally reserved for market-driven excitement.
    @discardableResult
    private func runCatoshiLocalZoomies() async -> Bool {
        let points = catoshiNavigationWaypoints
        guard points.count > 1 else {
            setCatoshiState(.zoomies)
            return await sleepCatoshi(0.7)
        }

        let nearbyIndex = min(points.count - 1, 2)
        let nearby = points[nearbyIndex]
        guard await moveCatoshiNaturally(to: nearby, movingState: .zoomies, strideScale: 0.90) else { return false }
        guard await moveCatoshiNaturally(to: 0, movingState: .zoomies, strideScale: 0.92) else { return false }
        if Bool.random() {
            guard await moveCatoshiNaturally(to: nearby, movingState: .zoomies, strideScale: 0.88) else { return false }
            return await moveCatoshiNaturally(to: 0, movingState: .zoomies, strideScale: 0.92)
        }
        return true
    }

    private enum CatoshiRoutine {
        case patrol
        case settle
        case grooming
        case nap
        case curious
        case mischief
        case rareLookAround
        case rareBigStretch
        case rareStartle
    }

    private func configureCatoshiRuntimeTasks() {
        let motionAvailable = displayActive && showCatoshi && catoshiAnimationEnabled

        if motionAvailable {
            if catoshiRandomLifeEnabled && !catoshiMarketReactionActive {
                startCatoshiLife()
            } else {
                catoshiLifeTask?.cancel()
                catoshiLifeTask = nil
                if !catoshiMarketReactionActive && catoshiMotion.state != .idle {
                    setCatoshiState(.idle)
                }
            }
            startCatoshiMicroLife()
            return
        }

        catoshiResetTask?.cancel()
        catoshiResetTask = nil
        catoshiLifeTask?.cancel()
        catoshiLifeTask = nil
        catoshiMicroTask?.cancel()
        catoshiMicroTask = nil
        catoshiMarketReactionActive = false
        catoshiReactionLatch = nil
        lastCatoshiTriggerSeverity = 0
        catoshiScriptedMicroActive = false
        catoshiMicroGeneration &+= 1
        catoshiMotion.clearMicroMotion()
        setCatoshiState(.idle)
    }

    private func startCatoshiLife() {
        guard showCatoshi, catoshiAnimationEnabled, catoshiRandomLifeEnabled, !catoshiMarketReactionActive else {
            catoshiLifeTask?.cancel()
            catoshiLifeTask = nil
            return
        }
        catoshiLifeTask?.cancel()
        catoshiLifeTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                let delay = Double.random(in: self.catoshiActivity.nextActionDelay)
                try? await Task.sleep(for: .seconds(delay))
                if Task.isCancelled { return }

                guard self.canRunDailyLife else { continue }
                let routine = self.nextDailyRoutine()
                await self.runDailyRoutine(routine)
                if Task.isCancelled { return }
                // Keep the routine's final resting pose. The next routine knows how to
                // stand up from sit/loaf, so forcing idle here would reintroduce a snap.
            }
        }
    }

    private var canRunDailyLife: Bool {
        displayActive && showCatoshi && catoshiAnimationEnabled && catoshiRandomLifeEnabled && !catoshiMarketReactionActive
    }

    private func pauseDailyLife(_ seconds: Double) async -> Bool {
        try? await Task.sleep(for: .seconds(seconds))
        return !Task.isCancelled && canRunDailyLife
    }

    /// Scripted micro motions let a daily-life sequence read as one intentional action
    /// instead of a collection of unrelated random twitches. The normal micro-life loop
    /// yields while this flag is set, so two writers never fight over the same tiny pose.
    @discardableResult
    private func playCatoshiMicro(_ motion: CatoshiMicroMotion, duration: Double) async -> Bool {
        guard canRunDailyLife else { return false }
        catoshiScriptedMicroActive = true
        // Invalidate an ordinary micro-motion that may already be sleeping. That task
        // checks this generation before it clears the pose, so it cannot erase the
        // scripted motion midway through the sequence.
        catoshiMicroGeneration &+= 1
        let generation = catoshiMicroGeneration
        defer {
            if catoshiMicroGeneration == generation {
                catoshiScriptedMicroActive = false
                catoshiMotion.clearMicroMotion()
            }
        }

        catoshiMotion.setMicroMotion(motion, active: true)
        guard await pauseDailyLife(duration) else { return false }
        catoshiMotion.setMicroMotion(motion, active: false)
        return await pauseDailyLife(motion == .blink ? 0.10 : 0.16)
    }

    /// A short arrival sequence gives the cat a reason to stop: settle, look, then rest.
    /// It uses existing frames only, so this improves behavioral continuity without adding
    /// a new animation clock or increasing the menu-bar rendering cadence.
    @discardableResult
    private func observeCatoshiAtRest() async -> Bool {
        guard await settleCatoshiIntoSit() else { return false }
        guard await pauseDailyLife(Double.random(in: 0.35...0.75)) else { return false }
        guard await playCatoshiMicro(.earTwitch, duration: Double.random(in: 0.20...0.28)) else { return false }
        if Int.random(in: 0..<100) < 62 {
            guard await playCatoshiMicro(.blink, duration: Double.random(in: 0.16...0.22)) else { return false }
        }
        return true
    }

    /// Turns in place without beginning a walking leg. This is intentionally rare and
    /// provides a lightweight 'look over the shoulder' behavior using the existing turn art.
    @discardableResult
    private func pivotCatoshiInPlace() async -> Bool {
        guard canRunDailyLife else { return false }
        let originalFacing = catoshiMotion.facing
        setCatoshiState(.turn)
        guard await pauseDailyLife(0.14) else { return false }
        catoshiMotion.setFacing(-originalFacing)
        guard await pauseDailyLife(0.24) else { return false }
        setCatoshiState(.idle)
        guard await pauseDailyLife(Double.random(in: 0.45...0.90)) else { return false }
        guard await playCatoshiMicro(.earTwitch, duration: 0.24) else { return false }
        setCatoshiState(.turn)
        guard await pauseDailyLife(0.14) else { return false }
        catoshiMotion.setFacing(originalFacing)
        guard await pauseDailyLife(0.24) else { return false }
        setCatoshiState(.idle)
        return true
    }

    private func runDailyRoutine(_ routine: CatoshiRoutine) async {
        guard canRunDailyLife else { return }

        switch routine {
        case .patrol:
            let target = catoshiExcursionTarget(.patrol)
            guard await moveCatoshiViaWaypoints(to: target, movingState: .walk) else { return }
            // Arrive, inspect the spot, then settle there instead of snapping directly
            // from walking into a long static sit. HOME remains a base, not a leash.
            guard await pauseCatoshiAtWaypoint(0.65...1.15) else { return }
            guard await observeCatoshiAtRest() else { return }
            _ = await pauseDailyLife(Double.random(in: 3.0...7.0))

        case .settle:
            guard await returnCatoshiHome() else { return }
            guard await settleCatoshiIntoSit() else { return }
            guard await pauseDailyLife(Double.random(in: 2.0...4.0)) else { return }
            setCatoshiState(.loaf)
            _ = await pauseDailyLife(Double.random(in: 15...38))

        case .grooming:
            guard await returnCatoshiHome() else { return }
            guard await observeCatoshiAtRest() else { return }
            guard await pauseDailyLife(Double.random(in: 0.7...1.4)) else { return }
            setCatoshiState(.groom)
            guard await pauseDailyLife(Double.random(in: 7...14)) else { return }
            setCatoshiState(.sit)
            if Int.random(in: 0..<100) < 55 {
                guard await playCatoshiMicro(.settle, duration: Double.random(in: 0.35...0.48)) else { return }
            }
            _ = await pauseDailyLife(Double.random(in: 2...4))

        case .nap:
            guard await returnCatoshiHome() else { return }
            setCatoshiState(.loaf)
            guard await pauseDailyLife(Double.random(in: 4...9)) else { return }
            setCatoshiState(.sleep)
            guard await pauseDailyLife(Double.random(in: 35...105)) else { return }
            setCatoshiState(.stretch)
            guard await pauseDailyLife(Double.random(in: 2.8...4.2)) else { return }
            guard await settleCatoshiIntoSit() else { return }
            _ = await pauseDailyLife(Double.random(in: 1.5...3.5))

        case .curious:
            // Curiosity starts from wherever Catoshi currently is instead of making an
            // artificial HOME reset before every trip. A small 'notice -> move -> inspect'
            // sequence makes the trip feel motivated rather than randomly teleported in state.
            guard await settleCatoshiIntoSit() else { return }
            guard await playCatoshiMicro(.earTwitch, duration: Double.random(in: 0.20...0.28)) else { return }
            guard await pauseDailyLife(Double.random(in: 0.5...1.0)) else { return }
            let target = catoshiExcursionTarget(.curious)
            guard await moveCatoshiViaWaypoints(to: target, movingState: .walk) else { return }
            guard await pauseCatoshiAtWaypoint(0.7...1.3) else { return }
            guard await observeCatoshiAtRest() else { return }
            _ = await pauseDailyLife(Double.random(in: 4...8))

        case .mischief:
            guard await playCatoshiMicro(.tailFlick, duration: 0.34) else { return }
            guard await runCatoshiLocalZoomies() else { return }
            guard await settleCatoshiIntoSit() else { return }
            _ = await pauseDailyLife(Double.random(in: 1.0...2.0))

        case .rareLookAround:
            guard await standCatoshiIfNeeded() else { return }
            guard await pivotCatoshiInPlace() else { return }
            guard await settleCatoshiIntoSit() else { return }
            _ = await pauseDailyLife(Double.random(in: 2.0...4.0))

        case .rareBigStretch:
            guard await returnCatoshiHome() else { return }
            guard await settleCatoshiIntoSit() else { return }
            setCatoshiState(.loaf)
            guard await pauseDailyLife(Double.random(in: 2.0...4.0)) else { return }
            setCatoshiState(.stretch)
            guard await pauseDailyLife(Double.random(in: 3.0...4.0)) else { return }
            guard await settleCatoshiIntoSit() else { return }
            guard await playCatoshiMicro(.blink, duration: 0.20) else { return }
            _ = await pauseDailyLife(Double.random(in: 2.0...4.0))

        case .rareStartle:
            guard await returnCatoshiHome() else { return }
            setCatoshiState(.loaf)
            guard await pauseDailyLife(Double.random(in: 3.0...6.0)) else { return }
            setCatoshiState(.sleep)
            guard await pauseDailyLife(Double.random(in: 5.0...10.0)) else { return }
            setCatoshiState(.scared)
            guard await pauseDailyLife(Double.random(in: 0.55...0.80)) else { return }
            guard await settleCatoshiIntoSit() else { return }
            guard await playCatoshiMicro(.blink, duration: 0.18) else { return }
            setCatoshiState(.loaf)
            _ = await pauseDailyLife(Double.random(in: 3.0...6.0))
        }
    }

    private func nextDailyRoutine() -> CatoshiRoutine {
        let hour = Calendar.current.component(.hour, from: Date())

        // Rare behaviors are deliberately outside the normal percentage table so they
        // stay surprising. Together they account for ~2% of daily-life selections.
        let rareRoll = Int.random(in: 0..<1000)
        if rareRoll < 8 { return .rareLookAround }
        if rareRoll < 15 { return .rareBigStretch }
        if rareRoll < 20 { return .rareStartle }

        let roll = Int.random(in: 0..<100)

        // HOME is a resting base, not a leash. At Normal activity the choice is now
        // close to 52% home routines / 48% roaming routines. Patrol/curious routines
        // also linger away from HOME, so observed territory use is much more balanced.
        if hour >= 23 || hour < 7 {
            if roll < 45 { return .nap }
            if roll < 70 { return .settle }
            if roll < 85 { return .grooming }
            if roll < 95 { return .patrol }
            return .curious
        }

        if hour >= 7 && hour < 10 {
            if roll < 22 { return .grooming }
            if roll < 40 { return .settle }
            if roll < 55 { return .nap }
            if roll < 83 { return .patrol }
            if roll < 98 { return .curious }
            return .mischief
        }

        switch catoshiActivity {
        case .quiet:
            if roll < 25 { return .settle }
            if roll < 50 { return .nap }
            if roll < 70 { return .grooming }
            if roll < 88 { return .patrol }
            if roll < 98 { return .curious }
            return .mischief
        case .normal:
            if roll < 18 { return .settle }
            if roll < 34 { return .nap }
            if roll < 52 { return .grooming }
            if roll < 80 { return .patrol }
            if roll < 95 { return .curious }
            return .mischief
        case .playful:
            if roll < 12 { return .settle }
            if roll < 22 { return .nap }
            if roll < 35 { return .grooming }
            if roll < 70 { return .patrol }
            if roll < 90 { return .curious }
            return .mischief
        }
    }

    private func startCatoshiMicroLife() {
        guard displayActive, showCatoshi, catoshiAnimationEnabled else {
            catoshiMicroTask?.cancel()
            catoshiMicroTask = nil
            return
        }
        catoshiMicroTask?.cancel()
        catoshiMicroTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                let resting = self.catoshiMotion.state == .sleep || self.catoshiMotion.state == .loaf
                let delay = resting ? Double.random(in: 3.2...6.5) : Double.random(in: 4.5...11.5)
                try? await Task.sleep(for: .seconds(delay))
                if Task.isCancelled { return }

                guard self.showCatoshi,
                      self.catoshiAnimationEnabled,
                      !self.catoshiMarketReactionActive,
                      !self.catoshiScriptedMicroActive,
                      !self.catoshiMotion.state.needsTimeline else { continue }

                let motion: CatoshiMicroMotion
                switch self.catoshiMotion.state {
                case .sleep:
                    motion = Bool.random() ? .breathe : .settle
                case .loaf:
                    motion = [CatoshiMicroMotion.breathe, .breathe, .blink, .settle].randomElement() ?? .breathe
                case .sit:
                    motion = [CatoshiMicroMotion.blink, .blink, .earTwitch, .tailFlick, .settle].randomElement() ?? .blink
                case .idle:
                    motion = [CatoshiMicroMotion.blink, .blink, .earTwitch, .tailFlick].randomElement() ?? .blink
                default:
                    motion = .none
                }
                guard motion != .none else { continue }

                let generation = self.catoshiMicroGeneration
                self.catoshiMotion.setMicroMotion(motion, active: true)
                let duration: Double
                switch motion {
                case .breathe: duration = Double.random(in: 1.0...1.5)
                case .blink: duration = Double.random(in: 0.16...0.24)
                case .earTwitch: duration = Double.random(in: 0.20...0.30)
                case .tailFlick: duration = Double.random(in: 0.28...0.42)
                case .settle: duration = Double.random(in: 0.35...0.55)
                case .none: duration = 0
                }
                try? await Task.sleep(for: .seconds(duration))
                if Task.isCancelled { return }
                guard generation == self.catoshiMicroGeneration,
                      !self.catoshiScriptedMicroActive,
                      !self.catoshiMarketReactionActive else { continue }
                self.catoshiMotion.setMicroMotion(motion, active: false)
                try? await Task.sleep(for: .seconds(motion == .blink ? 0.12 : 0.20))
                if Task.isCancelled { return }
                if generation == self.catoshiMicroGeneration,
                   !self.catoshiScriptedMicroActive,
                   !self.catoshiMarketReactionActive {
                    self.catoshiMotion.clearMicroMotion()
                }
            }
        }
    }

    private func catoshiReactionState(for change: Double) -> CatoshiState? {
        if change >= catoshiSensitivity.rocketThreshold { return .rocket }
        if change >= catoshiSensitivity.zoomiesThreshold { return .zoomies }
        if change >= catoshiSensitivity.happyThreshold { return .happy }
        guard catoshiDropReactionEnabled else { return nil }
        if change <= catoshiSensitivity.panicThreshold { return .flee }
        if change <= catoshiSensitivity.crashThreshold { return .scared }
        if change <= catoshiSensitivity.dipThreshold { return .alert }
        return nil
    }

    private func catoshiReactionDirection(_ state: CatoshiState) -> Int {
        switch state {
        case .happy, .zoomies, .rocket: return 1
        case .alert, .scared, .flee: return -1
        default: return 0
        }
    }

    private func catoshiReactionEntryMagnitude(_ state: CatoshiState) -> Double {
        switch state {
        case .happy, .alert: return catoshiSensitivity.happyThreshold
        case .zoomies, .scared: return catoshiSensitivity.zoomiesThreshold
        case .rocket, .flee: return catoshiSensitivity.rocketThreshold
        default: return .infinity
        }
    }

    /// Entry and release use different thresholds. Once a market reaction fires, the
    /// signal must retreat meaningfully before the same band can arm again. This stops
    /// a 5-minute change hovering around one boundary from repeatedly waking the cat.
    private func shouldReleaseCatoshiReactionLatch(_ state: CatoshiState, change: Double) -> Bool {
        let releaseMagnitude = catoshiReactionEntryMagnitude(state) * 0.70
        switch catoshiReactionDirection(state) {
        case 1: return change < releaseMagnitude
        case -1: return change > -releaseMagnitude
        default: return true
        }
    }

    private func evaluateCatoshiMomentum(_ change: Double) {
        guard displayActive, showCatoshi, catoshiAnimationEnabled, catoshiMarketReactionsEnabled else { return }

        let previousLatch = catoshiReactionLatch
        if let previousLatch, shouldReleaseCatoshiReactionLatch(previousLatch, change: change) {
            catoshiReactionLatch = nil
        }

        guard let desired = catoshiReactionState(for: change) else {
            if catoshiReactionLatch == nil, abs(change) < catoshiSensitivity.happyThreshold * 0.45 {
                lastCatoshiTriggerSeverity = 0
            }
            return
        }

        if let activeLatch = catoshiReactionLatch {
            let sameDirection = catoshiReactionDirection(activeLatch) == catoshiReactionDirection(desired)
            // The same band, or a less severe band in the same direction, stays latched.
            // A stronger move may escalate immediately even during the configured cooldown.
            if sameDirection && desired.severity <= activeLatch.severity { return }
        }

        let now = Date()
        let cooldownElapsed = lastCatoshiTriggerAt.map {
            now.timeIntervalSince($0) >= TimeInterval(catoshiCooldown.rawValue)
        } ?? true
        let escalated = desired.severity > lastCatoshiTriggerSeverity
        let reversed = previousLatch.map {
            catoshiReactionDirection($0) != 0
                && catoshiReactionDirection($0) != catoshiReactionDirection(desired)
        } ?? false

        // Arm the band even when cooldown suppresses the animation. This prevents a
        // continuously elevated signal from firing the moment the cooldown clock expires;
        // it must first leave the band and genuinely re-enter.
        catoshiReactionLatch = desired
        guard cooldownElapsed || escalated || reversed else { return }

        lastCatoshiTriggerAt = now
        lastCatoshiTriggerSeverity = desired.severity
        performMarketReaction(desired)
    }

    private func performMarketReaction(_ desired: CatoshiState) {
        catoshiResetTask?.cancel()
        catoshiLifeTask?.cancel()
        catoshiMarketReactionActive = true
        catoshiScriptedMicroActive = false
        catoshiMicroGeneration &+= 1
        catoshiMotion.clearMicroMotion()

        catoshiResetTask = Task { [weak self] in
            guard let self else { return }

            switch desired {
            case .happy:
                guard await self.settleCatoshiIntoSit() else { return }
                guard await self.sleepCatoshi(0.28) else { return }
                self.setCatoshiState(.happy)
                guard await self.sleepCatoshi(1.2) else { return }
                let target = self.catoshiExcursionTarget(.happy)
                guard await self.moveCatoshiViaWaypoints(
                    to: target,
                    movingState: .happy,
                    pauseAtIntermediateStops: false,
                    strideScale: 1.08
                ) else { return }
                guard await self.returnCatoshiHome(pauseAtWaypoints: false) else { return }

            case .zoomies:
                self.setCatoshiState(.happy)
                guard await self.sleepCatoshi(0.42) else { return }
                guard await self.runCatoshiSprints(state: .zoomies, passes: 4) else { return }
                guard await self.returnCatoshiHome(movingState: .zoomies, pauseAtWaypoints: false) else { return }
                guard await self.settleCatoshiIntoSit() else { return }
                guard await self.sleepCatoshi(0.45) else { return }

            case .rocket:
                self.setCatoshiState(.happy)
                guard await self.sleepCatoshi(0.32) else { return }
                guard await self.runCatoshiSprints(state: .rocket, passes: 5, strideScaleRange: 1.02...1.18) else { return }
                guard await self.returnCatoshiHome(movingState: .rocket, pauseAtWaypoints: false) else { return }
                self.setCatoshiState(.happy)
                guard await self.sleepCatoshi(0.65) else { return }

            case .alert:
                guard await self.returnCatoshiHome(pauseAtWaypoints: false) else { return }
                guard await self.settleCatoshiIntoSit() else { return }
                guard await self.sleepCatoshi(0.18) else { return }
                self.setCatoshiState(.alert)
                guard await self.sleepCatoshi(3.5) else { return }

            case .scared:
                self.setCatoshiState(.alert)
                guard await self.sleepCatoshi(0.22) else { return }
                guard await self.returnCatoshiHome(movingState: .flee, pauseAtWaypoints: false) else { return }
                self.setCatoshiState(.scared)
                guard await self.sleepCatoshi(3.6) else { return }
                self.setCatoshiState(.loaf)
                guard await self.sleepCatoshi(1.4) else { return }

            case .flee:
                self.setCatoshiState(.scared)
                guard await self.sleepCatoshi(0.24) else { return }
                let target = self.fleeEdgeTarget()
                guard await self.moveCatoshiNaturally(to: target, movingState: .flee, strideScale: 1.08) else { return }
                self.setCatoshiState(.loaf)
                guard await self.sleepCatoshi(1.8) else { return }

            default:
                guard await self.returnCatoshiHome(pauseAtWaypoints: false) else { return }
                self.setCatoshiState(desired)
                guard await self.sleepCatoshi(4.0) else { return }
            }

            guard !Task.isCancelled else { return }
            if self.catoshiMotion.state != .sit && self.catoshiMotion.state != .loaf && self.catoshiMotion.state != .sleep {
                guard await self.settleCatoshiIntoSit() else { return }
            }
            self.catoshiMarketReactionActive = false
            self.configureCatoshiRuntimeTasks()
        }
    }

    func previewCatoshi(_ state: CatoshiState) {
        catoshiResetTask?.cancel()
        catoshiLifeTask?.cancel()
        catoshiMarketReactionActive = true
        catoshiScriptedMicroActive = false
        catoshiMicroGeneration &+= 1
        catoshiMotion.clearMicroMotion()

        catoshiResetTask = Task { [weak self] in
            guard let self else { return }

            switch state {
            case .walk:
                let target = self.catoshiExcursionTarget(.curious)
                guard await self.moveCatoshiViaWaypoints(to: target, movingState: .walk) else { return }
                guard await self.sleepCatoshi(0.5) else { return }
                guard await self.returnCatoshiHome() else { return }
            case .turn:
                let points = self.catoshiNavigationWaypoints
                if self.catoshiMotion.positionX < 6, let nearby = points.dropFirst().first {
                    guard await self.moveCatoshiNaturally(to: nearby, movingState: .walk) else { return }
                }
                guard await self.turnCatoshiIfNeeded(toward: 0, movingState: .walk) else { return }
                guard await self.moveCatoshiNaturally(to: 0, movingState: .walk) else { return }
            case .zoomies:
                guard await self.runCatoshiSprints(state: .zoomies, passes: 3) else { return }
                guard await self.returnCatoshiHome(movingState: .zoomies, pauseAtWaypoints: false) else { return }
            case .rocket:
                guard await self.runCatoshiSprints(state: .rocket, passes: 4, strideScaleRange: 1.00...1.16) else { return }
                guard await self.returnCatoshiHome(movingState: .rocket, pauseAtWaypoints: false) else { return }
            case .flee:
                let target = self.fleeEdgeTarget()
                guard await self.moveCatoshiNaturally(to: target, movingState: .flee) else { return }
                guard await self.sleepCatoshi(1.0) else { return }
            default:
                guard await self.returnCatoshiHome() else { return }
                self.setCatoshiState(state)
                let seconds: Double = state == .sleep || state == .loaf ? 6 : 4
                guard await self.sleepCatoshi(seconds) else { return }
            }

            guard !Task.isCancelled else { return }
            self.catoshiMarketReactionActive = false
            self.setCatoshiState(.idle)
            self.configureCatoshiRuntimeTasks()
        }
    }

    func superviseFeedHealth(now: Date = Date()) {
        guard networkAvailable, displayActive, now.timeIntervalSince(modelStartedAt) > 20 else { return }

        // Reuse this one low-frequency supervisor for conservative idle keep-alives.
        // Active ticker traffic suppresses the probes, so normal market activity adds
        // no ping wakeups of its own.
        binance.performMaintenance(now: now)
        upbit.performMaintenance(now: now)

        let binanceStale = binanceState == .connected && binanceLastTickAt.map {
            now.timeIntervalSince($0) > CatoshiRuntimePolicy.staleFeedThreshold
        } ?? true
        let upbitStale = upbitState == .connected && upbitLastTickAt.map {
            now.timeIntervalSince($0) > CatoshiRuntimePolicy.staleFeedThreshold
        } ?? true

        // Receive failures/disconnected handshakes already own an exponential backoff
        // loop inside each client. The shared supervisor intervenes only in the distinct
        // half-open case: URLSession reports a connected feed but useful ticker data has
        // stopped. This prevents the supervisor from cancelling a client's pending retry.
        if binanceStale {
            binanceState = .connecting
            binance.reconnectNow()
        }
        if upbitStale {
            upbitState = .connecting
            upbit.reconnectNow()
        }
    }

    func reconnectFeeds() {
        guard networkAvailable, displayActive else { return }
        if binanceState != .connecting { binanceState = .connecting }
        if upbitState != .connecting { upbitState = .connecting }
        binance.reconnectNow()
        upbit.reconnectNow()
    }

    func handleSystemWake() {
        setDisplayActive(true)
        // screensDidWake normally reconnects the sockets immediately. Do not tear down
        // that fresh connection again. Track the delayed wake check so repeated sleep/wake
        // notifications cannot leave orphaned recovery tasks behind.
        wakeRecoveryTask?.cancel()
        wakeRecoveryTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(3.0))
            guard !Task.isCancelled, let self else { return }
            self.superviseFeedHealth(now: Date())
            self.wakeRecoveryTask = nil
        }
        guard showCatoshi, catoshiAnimationEnabled else { return }
        previewCatoshi(.stretch)
    }

    func resetDisplaySettings() {
        showCatoshi = true
        showMenuBarBinance = true
        showMenuBarUpbit = true
        showMenuBarPremium = true
        showMenuBarBinance24h = true
        showMenuBarUpbit24h = true
        showMenuBarPremium24h = true
        showMenuBarBinanceSparkline = false
        showMenuBarUpbitSparkline = false
        showMenuBarPremiumSparkline = false
        displayPalette = .color
    }

    func resetCatoshiSettings() {
        catoshiCoat = .calico
        catoshiAnimationEnabled = true
        catoshiRandomLifeEnabled = true
        catoshiMarketReactionsEnabled = true
        catoshiActivity = .normal
        catoshiSensitivity = .normal
        catoshiCooldown = .twoMinutes
        catoshiDropReactionEnabled = true
        catoshiMarketReactionActive = false
        configureCatoshiRuntimeTasks()
        catoshiMotion.reset()
        lastCatoshiTriggerAt = nil
        lastCatoshiTriggerSeverity = 0
    }

    private func startReferenceRefresh() {
        referenceTask?.cancel()
        referenceTask = nil
        guard networkAvailable, displayActive else { return }
        referenceTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                guard self.networkAvailable else { return }

                let nextDelay: TimeInterval
                do {
                    let reference = try await self.history.fetchReference24HoursAgo()
                    if Task.isCancelled { return }
                    self.apply(reference: reference)
                    nextDelay = CatoshiRuntimePolicy.referenceRefreshInterval
                } catch {
                    // A wake/network handoff can briefly fail before Wi-Fi settles. Retry
                    // the important 24h reference sooner without spinning aggressively.
                    nextDelay = CatoshiRuntimePolicy.referenceRetryInterval
                }

                try? await Task.sleep(for: .seconds(nextDelay))
            }
        }
    }

    private func configureSparklineRefresh() {
        sparklineTask?.cancel()
        sparklineTask = nil

        let needsSparkline =
            (showMenuBarBinance && showMenuBarBinanceSparkline) ||
            (showMenuBarUpbit && showMenuBarUpbitSparkline) ||
            (showMenuBarPremium && showMenuBarPremiumSparkline)

        guard needsSparkline, networkAvailable, displayActive else { return }
        startSparklineRefresh()
    }

    private func startSparklineRefresh() {
        sparklineTask?.cancel()
        sparklineTask = nil
        guard networkAvailable, displayActive else { return }
        sparklineTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                guard self.networkAvailable else { return }

                do {
                    let series = try await self.history.fetchSparkline24Hours()
                    if Task.isCancelled { return }
                    self.binanceSparkline = series.binanceBTCUSDT
                    self.upbitSparkline = series.upbitBTCKRW
                    self.premiumSparkline = series.premium
                } catch {
                    // Mini charts are auxiliary. Keep live prices working and retry later.
                }

                try? await Task.sleep(for: .seconds(CatoshiRuntimePolicy.sparklineRefreshInterval))
            }
        }
    }

    private func apply(reference: Reference24h) {
        reference24h = reference

        if let current = upbitBTC?.price {
            upbitBTC = Quote(
                price: current,
                change24h: percentChange(current: current, previous: reference.upbitBTCKRW)
            )
        }

        recalculate()
    }

    private func recalculate() {
        if let btcKRW = upbitBTC?.price,
           let btcUSDT = binanceBTC?.price,
           let usdtKRW = upbitUSDTKRW,
           btcUSDT > 0,
           usdtKRW > 0 {

            let currentPremium = ((btcKRW / (btcUSDT * usdtKRW)) - 1.0) * 100.0

            let delta = reference24h.map { ref -> Double in
                let premium24hAgo = ((ref.upbitBTCKRW / (ref.binanceBTCUSDT * ref.upbitUSDTKRW)) - 1.0) * 100.0
                return currentPremium - premium24hAgo
            }

            let nextPremium = PremiumSnapshot(value: currentPremium, change24h: delta)
            if shouldPublishPremium(nextPremium) {
                premium = nextPremium
            }
            updatedAt = Date()
        }

        refreshMenuBarLayoutSignature()
    }

    private func shouldPublishPremium(_ next: PremiumSnapshot) -> Bool {
        guard let current = premium else { return true }
        if abs(current.value - next.value) >= 0.005 { return true }
        switch (current.change24h, next.change24h) {
        case (nil, nil):
            return false
        case let (lhs?, rhs?):
            return abs(lhs - rhs) >= 0.005
        default:
            return true
        }
    }

    private func refreshMenuBarLayoutSignature() {
        var parts: [String] = []

        if showMenuBarBinance {
            let binanceText: String
            if let quote = binanceBTC {
                let change = showMenuBarBinance24h ? (quote.change24h.map { "  " + compactChange($0) } ?? "") : ""
                binanceText = "\(formatUSDMenu(quote.price))\(change)"
            } else {
                binanceText = "$---"
            }
            parts.append(binanceText)
        }

        if showMenuBarUpbit {
            let upbitText: String
            if let quote = upbitBTC {
                let change = showMenuBarUpbit24h ? (quote.change24h.map { "  " + compactChange($0) } ?? "") : ""
                upbitText = "\(formatKRWMenu(quote.price, language: appLanguage))\(change)"
            } else {
                upbitText = "₩---"
            }
            parts.append(upbitText)
        }

        if showMenuBarPremium {
            let premiumText: String
            if let premium {
                if showMenuBarPremium24h, let delta = premium.change24h {
                    premiumText = "\(formatPercent(premium.value))  \(compactPpChange(delta))"
                } else {
                    premiumText = formatPercent(premium.value)
                }
            } else {
                premiumText = "--"
            }
            parts.append(premiumText)
        }

        // The health light has fixed geometry. Normalize changing digits so status-item
        // width is remeasured only when the rendered text shape can actually change
        // (digit count, suffix, sign, visibility), not on every price tick.
        parts.append("●")
        let signature = parts
            .map(normalizedLayoutToken)
            .joined(separator: "   │   ")
        if menuBarLayoutSignature != signature {
            menuBarLayoutSignature = signature
        }
    }

    private func normalizedLayoutToken(_ text: String) -> String {
        String(text.map { character in
            character.wholeNumberValue == nil ? character : "0"
        })
    }
}
