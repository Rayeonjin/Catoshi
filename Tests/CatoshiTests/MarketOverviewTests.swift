import XCTest
@testable import Catoshi

final class MarketOverviewTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 2_000_000_000)

    func testEveryCoreCombinationHasSpecificBilingualRead() {
        for language in AppLanguage.allCases {
            var titles = Set<String>()
            for btc in [-0.3, 0, 0.3] {
                for usdt in [-0.2, 0, 0.2] {
                    for cap in [-2.0, 0, 2.0] {
                        let read = make(language, btc: btc, usdt: usdt, cap: cap)
                        titles.insert(read.title)
                        XCTAssertFalse(read.title.contains("혼조·전환"))
                        XCTAssertFalse(read.title.contains("Mixed / transition"))
                        XCTAssertFalse(read.reversal.isEmpty)
                        XCTAssertNotNil(read.overview)
                        XCTAssertTrue(read.basis.contains("%"))
                    }
                }
            }
            XCTAssertTrue(titles.count >= 10)
        }
    }

    func testSmallChangesDifferFromConflictingSignalsIncludingBoundaries() {
        for language in AppLanguage.allCases {
            let quiet = make(language, btc: 0.15, usdt: -0.10, cap: 0.75)
            XCTAssertEqual(quiet.alignment, language.pick("변화 제한", "Limited movement"))
            XCTAssertTrue(quiet.overview?.supporting.isEmpty == true)
            XCTAssertTrue(quiet.overview?.cautions.isEmpty == true)
            let conflict = make(language, usdt: 0.1001, cap: 0.7501)
            XCTAssertEqual(conflict.alignment, language.pick("신호 엇갈림", "Conflicting signals"))
            XCTAssertTrue(conflict.overview?.supporting.contains { $0.contains("TOTAL3*") } == true)
            XCTAssertTrue(conflict.overview?.cautions.contains { $0.contains("USDT.D") } == true)
        }
    }

    func testRelativeBTCStrengthDoesNotBecomeBullishPriceClaim() {
        for language in AppLanguage.allCases {
            let read = make(language, btc: 0.3, usdt: -0.2, cap: -2, price: -4)
            XCTAssertEqual(read.alignment, language.pick("신호 엇갈림", "Conflicting signals"))
            XCTAssertTrue(read.overview?.cautions.contains { $0.contains("BTC 24h -4.00%") } == true)
            XCTAssertTrue(read.overview?.cautions.contains { $0.contains("TOTAL3*") } == true)
            let expansion = make(language, btc: 0.3, usdt: -0.2, cap: 2, price: -4)
            XCTAssertTrue(expansion.tone == .caution)
        }
    }

    func testWarningsAndSupportCoexistWithNumbers() {
        for language in AppLanguage.allCases {
            let read = make(language, btc: -0.3, usdt: -0.2, cap: 2, fast: fast(), investor: investor(), premium: 7)
            let overview = read.overview
            XCTAssertTrue(overview?.supporting.contains { $0.contains("TOTAL3* 24h +2.00%") } == true)
            XCTAssertTrue(overview?.cautions.contains { $0.contains("Funding +0.060%") } == true)
            XCTAssertTrue(overview?.cautions.contains { $0.contains("ETF") } == true)
            XCTAssertTrue(overview?.cautions.contains { $0.contains("+7.00%") } == true)
            XCTAssertTrue(overview?.cautions.contains { $0.contains("200DMA") } == true)
            XCTAssertTrue(overview?.coverage.contains(language.pick("수신 완료", "inputs available")) == true)
            XCTAssertTrue(overview?.limitations.contains("TOTAL3*") == true)
            XCTAssertEqual(read.dimensions.count, 7)
        }
    }

    func testStaleFailedAndMissingInputsCannotBecomeEvidence() {
        for language in AppLanguage.allCases {
            var failed = MarketContextFreshness()
            failed.fast.didFail(at: now)
            failed.investor.didFail(at: now)
            for state in [MarketContextFreshness(), failed] {
                let old = now.addingTimeInterval(-86_400)
                let read = makeMarketRead(macro: macro(btc: 0.3, usdt: 0, cap: 0),
                    fast: fast(at: state.fast.lastFailureAt == nil ? old : now),
                    investor: investor(at: state.investor.lastFailureAt == nil ? old : now),
                    freshness: state, premium: PremiumSnapshot(value: 10, change24h: 0),
                    btcChange24h: -5, btcChange5m: 0, language: language,
                    btcUpdatedAt: old, premiumUpdatedAt: old, now: now)
                XCTAssertTrue(read.overview?.supporting.isEmpty == true)
                XCTAssertTrue(read.overview?.cautions.isEmpty == true)
                XCTAssertTrue(read.overview?.coverage.contains("ETF") == true)
                XCTAssertTrue(read.overview?.coverage.contains("OI/Funding") == true)
            }
        }
    }

    func testExpiredOIAndETFReportAreExplicitlyUnconfirmed() {
        let old = now.addingTimeInterval(-10 * 86_400)
        let partialFast = FastMarketSnapshot(ethBTC: 0.04, ethBTCChange24h: 1, openInterestUSD: 4e10,
            openInterestChange1h: 8, fundingRatePercent: 0.06, updatedAt: now, openInterestFetchedAt: old)
        let source = investor()
        let oldReport = InvestorMarketSnapshot(stablecoinSupplyUSD: source.stablecoinSupplyUSD,
            stablecoinSupplyChange7d: 0, etfLatestFlowUSD: -1e9, etfFiveDayFlowUSD: -1e9, etfFlowDate: old,
            btcReturn7d: 0, btcReturn30d: 0, btc200DMA: 60_000, btcAbove200DMA: true, updatedAt: now)
        for language in AppLanguage.allCases {
            let read = make(language, fast: partialFast, investor: oldReport)
            XCTAssertTrue(read.overview?.cautions.isEmpty == true)
            XCTAssertTrue(read.overview?.coverage.contains("ETF") == true)
            XCTAssertTrue(read.overview?.coverage.contains("OI/Funding") == true)
        }
    }

    func testInvalidOrUnavailableMacroCannotProduceOverview() {
        for value in [Double.nan, Double.infinity] {
            let read = make(.korean, usdt: value)
            XCTAssertEqual(read.title, "시장 해석 보류")
            XCTAssertNil(read.overview)
        }
        let read = makeMarketRead(macro: nil, fast: fast(), investor: investor(), freshness: MarketContextFreshness(),
            premium: nil, btcChange24h: nil, btcChange5m: nil, language: .english, now: now)
        XCTAssertNil(read.overview)
    }

    func testExtremeFundingSurvivesMissingOIWithoutInventingPositionGrowth() {
        let partial = FastMarketSnapshot(ethBTC: 0.04, ethBTCChange24h: 0, openInterestUSD: nil,
            openInterestChange1h: nil, fundingRatePercent: 0.10, updatedAt: now)
        for language in AppLanguage.allCases {
            let read = make(language, fast: partial)
            XCTAssertTrue(read.overview?.cautions.contains { $0.contains("Funding +0.100%") } == true)
            XCTAssertTrue(read.overview?.coverage.contains("OI/Funding") == true)
        }
    }

    private func make(_ language: AppLanguage, btc: Double = 0, usdt: Double = 0, cap: Double = 0,
                      price: Double? = 0, fast: FastMarketSnapshot? = nil, investor: InvestorMarketSnapshot? = nil,
                      premium: Double? = nil) -> MarketRead {
        makeMarketRead(macro: macro(btc: btc, usdt: usdt, cap: cap), fast: fast, investor: investor,
            freshness: MarketContextFreshness(), premium: premium.map { PremiumSnapshot(value: $0, change24h: 0) },
            btcChange24h: price, btcChange5m: 0, language: language, btcUpdatedAt: now, premiumUpdatedAt: now, now: now)
    }

    private func macro(btc: Double, usdt: Double, cap: Double) -> MacroMarketSnapshot {
        MacroMarketSnapshot(btcDominance: 60, btcDominanceChange24hPP: btc, usdtDominance: 5,
            usdtDominanceChange24hPP: usdt, total3USD: 1e12, total3Change24h: cap, updatedAt: now)
    }

    private func fast(at date: Date? = nil) -> FastMarketSnapshot {
        FastMarketSnapshot(ethBTC: 0.04, ethBTCChange24h: 1, openInterestUSD: 4e10,
            openInterestChange1h: 8, fundingRatePercent: 0.06, updatedAt: date ?? now)
    }

    private func investor(at date: Date? = nil) -> InvestorMarketSnapshot {
        InvestorMarketSnapshot(stablecoinSupplyUSD: 2e11, stablecoinSupplyChange7d: -1,
            etfLatestFlowUSD: -2e8, etfFiveDayFlowUSD: -8e8, etfFlowDate: now.addingTimeInterval(-86_400),
            btcReturn7d: -2, btcReturn30d: -10, btc200DMA: 60_000, btcAbove200DMA: false, updatedAt: date ?? now)
    }
}
