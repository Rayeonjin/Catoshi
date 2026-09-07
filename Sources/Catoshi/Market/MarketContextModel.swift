import Combine
import Foundation

enum DomesticExchange: String, CaseIterable, Identifiable {
    case upbit
    case bithumb
    case coinone
    case korbit
    case gopax

    var id: String { rawValue }

    var label: String {
        switch self {
        case .upbit: return "Upbit"
        case .bithumb: return "Bithumb"
        case .coinone: return "Coinone"
        case .korbit: return "Korbit"
        case .gopax: return "GOPAX"
        }
    }
}

enum DomesticExchangeDataState: Equatable {
    case unknown
    case available
    case maintenance
    case unavailable
}

struct DomesticExchangeAvailability: Identifiable, Equatable {
    let exchange: DomesticExchange
    let state: DomesticExchangeDataState

    var id: String { exchange.rawValue }
}

struct DomesticExchangeVolume: Identifiable {
    let exchange: DomesticExchange
    let krw24h: Double

    var id: String { exchange.rawValue }
}

struct DomesticVolumeSnapshot {
    let entries: [DomesticExchangeVolume]
    let availability: [DomesticExchangeAvailability]
    let updatedAt: Date
    let isPartial: Bool

    var total: Double { entries.reduce(0) { $0 + $1.krw24h } }

    func share(for entry: DomesticExchangeVolume) -> Double {
        guard total > 0 else { return 0 }
        return entry.krw24h / total * 100
    }
}

struct MacroMarketSnapshot {
    let btcDominance: Double
    let btcDominanceChange24hPP: Double?
    let usdtDominance: Double
    let usdtDominanceChange24hPP: Double?
    let total3USD: Double
    let total3Change24h: Double?
    let updatedAt: Date
}

struct FastMarketSnapshot {
    let ethBTC: Double
    let ethBTCChange24h: Double
    let openInterestUSD: Double?
    let openInterestChange1h: Double?
    let fundingRatePercent: Double?
    let updatedAt: Date
}

struct InvestorMarketSnapshot {
    let stablecoinSupplyUSD: Double?
    let stablecoinSupplyChange7d: Double?
    let etfLatestFlowUSD: Double?
    let etfFiveDayFlowUSD: Double?
    let etfFlowDate: Date?
    let btcReturn7d: Double?
    let btcReturn30d: Double?
    let btc200DMA: Double?
    let btcAbove200DMA: Bool?
    let updatedAt: Date
}

enum MarketTrend: String {
    case up = "↑"
    case down = "↓"
    case flat = "→"
    case unknown = "·"
}

enum MarketReadTone {
    case constructive
    case caution
    case riskOff
    case neutral
}

struct MarketReadDimension: Identifiable {
    let id: String
    let label: String
    let signal: String
    let explanation: String
}

struct MarketRead {
    let title: String
    let summary: String
    let decision: String
    let reversal: String
    let basis: String
    let alignment: String
    let dimensions: [MarketReadDimension]
    let tone: MarketReadTone
    let badges: [String]
}


enum DomesticRefreshIssue {
    case partialData(maintenance: [DomesticExchange], unavailable: [DomesticExchange])
    case partialDataRetainingLastComplete(maintenance: [DomesticExchange], unavailable: [DomesticExchange])
    case refreshFailed

    func message(_ language: AppLanguage) -> String {
        switch self {
        case .partialData(let maintenance, let unavailable):
            return issueMessage(
                language,
                maintenance: maintenance,
                unavailable: unavailable,
                koreanSuffix: "현재 값은 정상 수신된 거래소만 부분 집계합니다.",
                englishSuffix: "The current total includes only exchanges that returned fresh data."
            )
        case .partialDataRetainingLastComplete(let maintenance, let unavailable):
            return issueMessage(
                language,
                maintenance: maintenance,
                unavailable: unavailable,
                koreanSuffix: "마지막 전체 데이터를 유지하고 있습니다.",
                englishSuffix: "The last complete snapshot is being kept."
            )
        case .refreshFailed:
            return language.pick(
                "거래소 거래대금을 갱신하지 못했습니다. 마지막 데이터를 유지합니다.",
                "Trading values could not be refreshed. The last snapshot is being kept."
            )
        }
    }

    private func issueMessage(
        _ language: AppLanguage,
        maintenance: [DomesticExchange],
        unavailable: [DomesticExchange],
        koreanSuffix: String,
        englishSuffix: String
    ) -> String {
        let maintenanceNames = maintenance.map(\.label).joined(separator: ", ")
        let unavailableNames = unavailable.map(\.label).joined(separator: ", ")

        var koreanParts: [String] = []
        var englishParts: [String] = []
        if !maintenanceNames.isEmpty {
            koreanParts.append("\(maintenanceNames) 점검 중")
            englishParts.append("\(maintenanceNames) under maintenance")
        }
        if !unavailableNames.isEmpty {
            koreanParts.append("\(unavailableNames) 데이터 수신 불가")
            englishParts.append("\(unavailableNames) data unavailable")
        }

        let koreanPrefix = koreanParts.isEmpty ? "일부 거래소 데이터 수신 실패" : koreanParts.joined(separator: " · ")
        let englishPrefix = englishParts.isEmpty ? "Some exchange data is unavailable" : englishParts.joined(separator: " · ")
        return language.pick("\(koreanPrefix) · \(koreanSuffix)", "\(englishPrefix) · \(englishSuffix)")
    }
}

enum MarketContextFocus {
    case none
    case market
    case domestic
}

@MainActor
final class MarketContextModel: ObservableObject {
    @Published var domestic: DomesticVolumeSnapshot?
    @Published var macro: MacroMarketSnapshot?
    @Published var fast: FastMarketSnapshot?
    @Published var investor: InvestorMarketSnapshot?
    @Published var isRefreshing = false
    @Published private(set) var freshness = MarketContextFreshness()
    @Published var domesticRefreshIssue: DomesticRefreshIssue?
    @Published var domesticActivity: DomesticActivitySnapshot?
    @Published var domesticAvailability: [DomesticExchangeAvailability] = DomesticExchange.allCases.map {
        DomesticExchangeAvailability(exchange: $0, state: .unknown)
    }

    private let service: any MarketContextFetching
    private let now: () -> Date
    private let backgroundWorkEnabled: Bool
    private lazy var activityRadar = DomesticActivityRadarEngine()
    private var refreshLoopTask: Task<Void, Never>?
    private var domesticRadarTask: Task<Void, Never>?
    private var manualRefreshTask: Task<Void, Never>?
    private var popoverVisible = false
    private var networkAvailable = true
    private var displayActive = true
    private var focus: MarketContextFocus = .none
    private var latestDomesticSnapshot: DomesticVolumeSnapshot?
    private var lastDomesticFetchAt: Date?
    private var domesticFetchTask: Task<Void, Never>?
    private var domesticPublishRequested = false

    init(service: any MarketContextFetching = MarketContextService(),
         now: @escaping () -> Date = Date.init,
         startsBackgroundTasks: Bool = true) {
        self.service = service
        self.now = now
        backgroundWorkEnabled = startsBackgroundTasks
        // Materialize a recent persisted radar reading immediately when available. The
        // Domestic tab is a viewer of this background state, not the owner of measurement.
        if startsBackgroundTasks { domesticActivity = activityRadar.latestSnapshot() }

        // Start the lightweight aggregate radar automatically. A cold start takes one
        // snapshot after a short delay, then temporarily samples every three minutes
        // until a rolling 15-minute window exists. Existing persisted history is reused.
        if startsBackgroundTasks { restartDomesticRadarLoop(initialDelay: 20) }
    }

    deinit {
        refreshLoopTask?.cancel()
        domesticRadarTask?.cancel()
        manualRefreshTask?.cancel()
        domesticFetchTask?.cancel()
    }

    func prepareForTermination() {
        refreshLoopTask?.cancel()
        refreshLoopTask = nil
        domesticRadarTask?.cancel()
        domesticRadarTask = nil
        manualRefreshTask?.cancel()
        manualRefreshTask = nil
        domesticFetchTask?.cancel()
        if backgroundWorkEnabled { activityRadar.flush() }
    }


    func setDisplayActive(_ active: Bool) {
        guard displayActive != active else { return }
        displayActive = active

        if active {
            restartFocusedLoop()
            restartDomesticRadarLoop(initialDelay: 2)
        } else {
            refreshLoopTask?.cancel()
            refreshLoopTask = nil
            domesticRadarTask?.cancel()
            domesticRadarTask = nil
            manualRefreshTask?.cancel()
            manualRefreshTask = nil
            domesticFetchTask?.cancel()
            if isRefreshing { isRefreshing = false }
        }
    }

    func setNetworkAvailable(_ available: Bool) {
        guard networkAvailable != available else { return }
        networkAvailable = available

        if available && displayActive {
            restartFocusedLoop()
            restartDomesticRadarLoop(initialDelay: 2)
        } else {
            refreshLoopTask?.cancel()
            refreshLoopTask = nil
            domesticRadarTask?.cancel()
            domesticRadarTask = nil
            manualRefreshTask?.cancel()
            manualRefreshTask = nil
            domesticFetchTask?.cancel()
            if isRefreshing { isRefreshing = false }
        }
    }

    func setPopoverVisible(_ visible: Bool) {
        guard popoverVisible != visible else { return }
        popoverVisible = visible
        restartFocusedLoop()
        // Do not reset the background schedule just because the user opens the
        // Price/Market/Guide tabs. Only a visible Domestic tab changes cadence.
        if backgroundWorkEnabled, focus == .domestic {
            restartDomesticRadarLoop(
                initialDelay: visible ? 0 : activityRadar.preferredBackgroundCadence()
            )
        }
    }

    func setFocus(_ newFocus: MarketContextFocus) {
        guard focus != newFocus else { return }
        let previousFocus = focus
        focus = newFocus

        restartFocusedLoop()
        // Entering Domestic immediately switches to the 1-minute visible cadence.
        // Leaving it resumes the adaptive warm-start/steady background cadence.
        if backgroundWorkEnabled, previousFocus == .domestic || newFocus == .domestic {
            restartDomesticRadarLoop(
                initialDelay: popoverVisible && newFocus == .domestic
                    ? 0
                    : activityRadar.preferredBackgroundCadence()
            )
        }
    }

    func refreshNow() {
        guard networkAvailable, displayActive else { return }
        manualRefreshTask?.cancel()
        manualRefreshTask = Task { [weak self] in
            guard let self else { return }
            self.isRefreshing = true
            defer { self.isRefreshing = false }
            await self.refreshFocusedData(force: true)
        }
    }

    private func restartFocusedLoop() {
        refreshLoopTask?.cancel()
        refreshLoopTask = nil

        // Domestic data has its own adaptive radar loop: 1 minute while visible,
        // a short three-minute warm-start cadence until 15m data exists, then 15m.
        guard backgroundWorkEnabled, networkAvailable, displayActive, popoverVisible, focus != .none, focus != .domestic else { return }

        refreshLoopTask = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                await self.refreshFocusedData(force: false)
                try? await Task.sleep(for: .seconds(60))
            }
        }
    }

    private func restartDomesticRadarLoop(initialDelay: TimeInterval) {
        domesticRadarTask?.cancel()
        domesticRadarTask = nil

        guard backgroundWorkEnabled, networkAvailable, displayActive else { return }

        domesticRadarTask = Task { [weak self] in
            guard let self else { return }

            if initialDelay > 0 {
                try? await Task.sleep(for: .seconds(initialDelay))
                if Task.isCancelled { return }
            }

            while !Task.isCancelled {
                let isVisible = self.popoverVisible && self.focus == .domestic
                await self.refreshDomestic(force: false, publish: isVisible)
                let cadence: TimeInterval = isVisible
                    ? 60
                    : self.activityRadar.preferredBackgroundCadence()
                try? await Task.sleep(for: .seconds(cadence))
            }
        }
    }

    private func refreshFocusedData(force: Bool) async {
        guard networkAvailable, displayActive else { return }
        switch focus {
        case .none:
            return
        case .market:
            await refreshMarketData(force: force)
        case .domestic:
            await refreshDomestic(force: force, publish: true)
        }
    }

    /// Coalesces the radar and manual refresh; internal for offline concurrency tests.
    func refreshDomestic(force: Bool, publish: Bool) async {
        guard networkAvailable, displayActive, !Task.isCancelled else { return }
        if let inFlight = domesticFetchTask {
            domesticPublishRequested = domesticPublishRequested || publish
            await inFlight.value
            // A reconnect may join the previous, cancelled request while it unwinds.
            // Wait for it to finish before starting the replacement request.
            if inFlight.isCancelled, !Task.isCancelled, networkAvailable, displayActive {
                await refreshDomestic(force: force, publish: publish)
            }
            return
        }
        if !force,
           let lastDomesticFetchAt,
           now().timeIntervalSince(lastDomesticFetchAt) >= 0,
           now().timeIntervalSince(lastDomesticFetchAt) < 50,
           let cached = latestDomesticSnapshot {
            if publish { publishDomestic(cached, preservingRefreshFailure: true) }
            return
        }

        domesticPublishRequested = publish
        // The model owns this request. Cancelling a tab's schedule must not discard
        // a response that another visible/manual caller is already waiting for.
        let request = Task { [weak self] in
            guard let self else { return }
            defer {
                self.domesticFetchTask = nil
                self.domesticPublishRequested = false
            }
            do {
                let snapshot = try await self.service.fetchDomesticExchangeVolumes()
                guard !Task.isCancelled else { return }
                if let cached = self.latestDomesticSnapshot, snapshot.updatedAt < cached.updatedAt {
                    if self.domesticPublishRequested {
                        self.publishDomestic(cached, preservingRefreshFailure: true)
                    }
                    return
                }

                self.latestDomesticSnapshot = snapshot
                self.lastDomesticFetchAt = self.now()
                self.domesticRefreshIssue = nil
                if self.domesticAvailability != snapshot.availability {
                    self.domesticAvailability = snapshot.availability
                }

                // Offline previews/tests must not create or persist a user radar.
                if self.backgroundWorkEnabled {
                    let activity = self.activityRadar.ingest(snapshot)
                    if self.domesticActivity != activity {
                        self.domesticActivity = activity
                    }
                }
                if self.domesticPublishRequested {
                    self.publishDomestic(snapshot)
                }
            } catch {
                guard !Task.isCancelled,
                      !(error is CancellationError),
                      (error as? URLError)?.code != .cancelled else { return }
                // Retain failures even when the radar requested data off screen.
                // Showing a cached snapshot later does not constitute recovery.
                self.domesticRefreshIssue = .refreshFailed
            }
        }
        domesticFetchTask = request
        await request.value
    }

    private func publishDomestic(_ snapshot: DomesticVolumeSnapshot, preservingRefreshFailure: Bool = false) {
        let previousIssue = domesticRefreshIssue
        defer {
            if preservingRefreshFailure, case .refreshFailed? = previousIssue {
                domesticRefreshIssue = previousIssue
            }
        }
        let maintenance = snapshot.availability.compactMap { item in
            item.state == .maintenance ? item.exchange : nil
        }
        let unavailable = snapshot.availability.compactMap { item in
            item.state == .unavailable ? item.exchange : nil
        }

        if snapshot.isPartial, let current = domestic, !current.isPartial {
            // Keep the last complete 24h snapshot so pie/share denominators do not silently
            // change, while the activity radar continues per venue from the fresh partial data.
            domesticRefreshIssue = .partialDataRetainingLastComplete(
                maintenance: maintenance,
                unavailable: unavailable
            )
            return
        }

        if domestic?.updatedAt != snapshot.updatedAt {
            domestic = snapshot
        }

        if snapshot.isPartial {
            domesticRefreshIssue = .partialData(
                maintenance: maintenance,
                unavailable: unavailable
            )
        } else {
            domesticRefreshIssue = nil
        }
    }

    /// Runs the existing three source cadences. Internal for deterministic failure/recovery tests.
    func refreshMarketData(force: Bool) async {
        guard networkAvailable, displayActive else { return }
        async let macro: Void = refreshMacro(force: force)
        async let fast: Void = refreshFast(force: force)
        async let investor: Void = refreshInvestor(force: force)
        _ = await (macro, fast, investor)
    }

    func status(for source: MarketDataSource, at date: Date = Date()) -> MarketDataStatus {
        let updatedAt: Date?
        switch source {
        case .macro: updatedAt = macro?.updatedAt
        case .fast: updatedAt = fast?.updatedAt
        case .investor: updatedAt = investor?.updatedAt
        }
        return freshness[source].status(updatedAt: updatedAt, source: source, now: date)
    }

    func interpretationInputs(at date: Date = Date()) -> MarketInterpretationInputs {
        MarketInterpretationInputs(macro: macro, fast: fast, investor: investor, freshness: freshness, now: date)
    }

    private func refreshMacro(force: Bool) async {
        guard freshness.macro.shouldRefresh(source: .macro, now: now(), force: force) else { return }
        freshness.macro.didAttempt(at: now())
        do {
            let snapshot = try await service.fetchMacroMarket()
            if Task.isCancelled {
                freshness.macro.didCancel()
                return
            }
            macro = snapshot
            freshness.macro.didSucceed(at: now(), isPartial:
                snapshot.btcDominanceChange24hPP == nil || snapshot.usdtDominanceChange24hPP == nil || snapshot.total3Change24h == nil)
        } catch {
            if Task.isCancelled {
                freshness.macro.didCancel()
                return
            }
            freshness.macro.didFail(at: now())
        }
    }

    private func refreshFast(force: Bool) async {
        guard freshness.fast.shouldRefresh(source: .fast, now: now(), force: force) else { return }
        freshness.fast.didAttempt(at: now())
        do {
            let snapshot = try await service.fetchFastMarket()
            if Task.isCancelled {
                freshness.fast.didCancel()
                return
            }
            fast = snapshot
            freshness.fast.didSucceed(at: now(), isPartial:
                snapshot.openInterestUSD == nil || snapshot.openInterestChange1h == nil || snapshot.fundingRatePercent == nil)
        } catch {
            if Task.isCancelled {
                freshness.fast.didCancel()
                return
            }
            freshness.fast.didFail(at: now())
        }
    }

    private func refreshInvestor(force: Bool) async {
        guard freshness.investor.shouldRefresh(source: .investor, now: now(), force: force) else { return }
        freshness.investor.didAttempt(at: now())
        do {
            let snapshot = try await service.fetchInvestorMarket()
            if Task.isCancelled {
                freshness.investor.didCancel()
                return
            }
            investor = snapshot
            freshness.investor.didSucceed(at: now(), isPartial:
                snapshot.stablecoinSupplyChange7d == nil || snapshot.etfFiveDayFlowUSD == nil || snapshot.btcReturn30d == nil)
        } catch {
            if Task.isCancelled {
                freshness.investor.didCancel()
                return
            }
            freshness.investor.didFail(at: now())
        }
    }
}
