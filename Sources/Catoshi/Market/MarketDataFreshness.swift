import Foundation

/// Receipt age is separate from the lookback of a metric (24h, 7D, etc.).
/// These limits allow missed polls without presenting indefinitely cached data as current.
enum MarketDataSource: CaseIterable {
    case macro, fast, investor

    var maximumAge: TimeInterval {
        switch self {
        case .macro: return 20 * 60
        case .fast: return 3 * 60
        case .investor: return 2 * 60 * 60
        }
    }

    var refreshInterval: TimeInterval {
        switch self {
        case .macro: return 540
        case .fast: return 50
        case .investor: return 1_800
        }
    }
}

enum MarketDataStatus: Equatable {
    case waiting, fresh, partial, stale, failed

    var allowsInterpretation: Bool { self == .fresh || self == .partial }

    func label(_ language: AppLanguage) -> String {
        switch self {
        case .waiting: return language.pick("데이터 대기", "Waiting")
        case .fresh: return language.pick("수신 정상", "Received")
        case .partial: return language.pick("일부 수신 실패", "Partial data")
        case .stale: return language.pick("오래된 데이터", "Stale data")
        case .failed: return language.pick("갱신 실패", "Refresh failed")
        }
    }
}

struct MarketRefreshState: Equatable {
    private(set) var lastAttemptAt: Date?
    private(set) var lastSuccessAt: Date?
    private(set) var lastFailureAt: Date?
    private(set) var isPartial = false
    private(set) var isInFlight = false

    mutating func didAttempt(at date: Date) {
        lastAttemptAt = date
        isInFlight = true
    }

    mutating func didCancel() { isInFlight = false }

    mutating func didSucceed(at date: Date, isPartial: Bool) {
        lastAttemptAt = date
        lastSuccessAt = date
        lastFailureAt = nil
        self.isPartial = isPartial
        isInFlight = false
    }

    mutating func didFail(at date: Date) {
        lastAttemptAt = date
        lastFailureAt = date
        isInFlight = false
    }

    func shouldRefresh(source: MarketDataSource, now: Date, force: Bool) -> Bool {
        // A manual click must not race an existing request for the same source.
        if isInFlight { return false }
        if force { return true }
        // Only completed attempts control the cadence: cancelling a cold-start
        // request must not hide its missing data for the entire source interval.
        let referenceDate = lastFailureAt ?? lastSuccessAt
        guard let referenceDate else { return true }
        let interval = lastFailureAt != nil ? 50 : source.refreshInterval
        let age = now.timeIntervalSince(referenceDate)
        return age < 0 || age >= interval
    }

    func status(updatedAt: Date?, source: MarketDataSource, now: Date) -> MarketDataStatus {
        if lastFailureAt != nil { return .failed }
        guard let updatedAt else { return .waiting }
        guard Self.isCurrent(updatedAt, maximumAge: source.maximumAge, now: now) else { return .stale }
        return isPartial ? .partial : .fresh
    }

    static func isCurrent(_ date: Date, maximumAge: TimeInterval, now: Date) -> Bool {
        let age = now.timeIntervalSince(date)
        // Tolerate a small provider clock skew, but never accept a wildly future timestamp.
        return age.isFinite && age >= -60 && age < maximumAge
    }
}

struct MarketContextFreshness {
    var macro = MarketRefreshState()
    var fast = MarketRefreshState()
    var investor = MarketRefreshState()

    subscript(source: MarketDataSource) -> MarketRefreshState {
        get {
            switch source {
            case .macro: return macro
            case .fast: return fast
            case .investor: return investor
            }
        }
        set {
            switch source {
            case .macro: macro = newValue
            case .fast: fast = newValue
            case .investor: investor = newValue
            }
        }
    }
}

struct MarketInterpretationInputs {
    let macro: MacroMarketSnapshot?
    let fast: FastMarketSnapshot?
    let investor: InvestorMarketSnapshot?

    init(macro: MacroMarketSnapshot?, fast: FastMarketSnapshot?, investor: InvestorMarketSnapshot?,
         freshness: MarketContextFreshness, now: Date) {
        self.macro = freshness.macro.status(updatedAt: macro?.updatedAt, source: .macro, now: now).allowsInterpretation
            && macro?.btcDominanceChange24hPP != nil && macro?.usdtDominanceChange24hPP != nil && macro?.total3Change24h != nil
            ? macro : nil
        self.fast = freshness.fast.status(updatedAt: fast?.updatedAt, source: .fast, now: now).allowsInterpretation ? fast : nil
        if freshness.investor.status(updatedAt: investor?.updatedAt, source: .investor, now: now).allowsInterpretation,
           let investor {
            // ETF flows are daily reports, not live quotes. A successful page fetch cannot
            // make an old report current. Seven calendar days allow weekends and holidays.
            let hasCurrentETF = Self.etfReportIsCurrent(investor.etfFlowDate, now: now)
            self.investor = InvestorMarketSnapshot(
                stablecoinSupplyUSD: investor.stablecoinSupplyUSD,
                stablecoinSupplyChange7d: investor.stablecoinSupplyChange7d,
                etfLatestFlowUSD: hasCurrentETF ? investor.etfLatestFlowUSD : nil,
                etfFiveDayFlowUSD: hasCurrentETF ? investor.etfFiveDayFlowUSD : nil,
                etfFlowDate: investor.etfFlowDate,
                btcReturn7d: investor.btcReturn7d,
                btcReturn30d: investor.btcReturn30d,
                btc200DMA: investor.btc200DMA,
                btcAbove200DMA: investor.btcAbove200DMA,
                updatedAt: investor.updatedAt
            )
        } else {
            self.investor = nil
        }
    }

    static func etfReportIsCurrent(_ date: Date?, now: Date) -> Bool {
        guard let date else { return false }
        return MarketRefreshState.isCurrent(date, maximumAge: 7 * 24 * 60 * 60, now: now)
    }
}

protocol MarketContextFetching {
    func fetchDomesticExchangeVolumes() async throws -> DomesticVolumeSnapshot
    func fetchMacroMarket() async throws -> MacroMarketSnapshot
    func fetchFastMarket() async throws -> FastMarketSnapshot
    func fetchInvestorMarket() async throws -> InvestorMarketSnapshot
}

extension MarketContextService: MarketContextFetching {}
