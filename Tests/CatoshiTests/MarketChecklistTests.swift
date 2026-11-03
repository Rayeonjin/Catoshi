import XCTest
@testable import Catoshi

final class MarketChecklistTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 2_000_000_000)

    func testRiskThresholdsAreInclusiveOrderedAndLimitedInBothLanguages() {
        for language in AppLanguage.allCases {
            let read = make(language, oi: 5, funding: 0.05, premium: 5, etf: -500_000_000, stable: -0.5)
            let prefixes = language == .english
                ? ["Leverage crowding:", "Korean overheating:", "Weak spot demand:", "Shrinking liquidity:"]
                : ["레버리지 과밀:", "국내 과열:", "현물 수요 약화:", "유동성 축소:"]
            XCTAssertEqual(read.checklist.count, 4)
            for (item, prefix) in zip(read.checklist, prefixes) { XCTAssertTrue(item.hasPrefix(prefix)) }
            XCTAssertFalse(read.decision.isEmpty)
            XCTAssertFalse(read.reversal.isEmpty)
            XCTAssertFalse(read.basis.isEmpty)
        }
    }

    func testValuesBelowThresholdsUseAlignmentFallback() {
        for language in AppLanguage.allCases {
            let read = make(language, oi: 4.999, funding: 0.0499, premium: 4.999, etf: -499_999_999, stable: -0.4999)
            XCTAssertEqual(read.checklist.count, 1)
            XCTAssertTrue(read.checklist[0].hasPrefix(language == .english ? "Alignment check:" : "정렬 확인:"))
        }
    }

    func testNegativeFundingAndExtremeFundingAlsoProduceLeverageCheck() {
        for language in AppLanguage.allCases {
            for (oi, funding) in [(5.0, -0.05), (0.0, 0.10), (0.0, -0.10)] {
                let read = make(language, oi: oi, funding: funding)
                XCTAssertEqual(read.checklist.count, 1)
                XCTAssertTrue(read.checklist[0].hasPrefix(language == .english ? "Leverage crowding:" : "레버리지 과밀:"))
            }
        }
    }

    func testMissingOrStaleMacroShowsOnlyDataChecks() {
        for language in AppLanguage.allCases {
            for macro in [nil, self.macro(at: now.addingTimeInterval(-MarketDataSource.macro.maximumAge))] {
                let read = makeMarketRead(macro: macro, fast: fast(oi: 10, funding: 0.1), investor: investor(etf: -1e9, stable: -1),
                    freshness: MarketContextFreshness(), premium: PremiumSnapshot(value: 10, change24h: 0),
                    btcChange24h: 0, btcChange5m: 0, language: language, btcUpdatedAt: now, premiumUpdatedAt: now, now: now)
                XCTAssertEqual(read.checklist.count, 1)
                XCTAssertTrue(read.checklist[0].hasPrefix(language == .english ? (macro == nil ? "Waiting for data:" : "Check data freshness first:") : (macro == nil ? "데이터 대기:" : "데이터 갱신 확인:")))
            }
        }
    }

    func testStaleInputsAndMissingDerivativeValuesCannotAddRiskChecks() {
        for language in AppLanguage.allCases {
            let old = now.addingTimeInterval(-86_400)
            let stale = makeMarketRead(macro: macro(), fast: fast(oi: 10, funding: 0.1, at: old),
                investor: investor(etf: -1e9, stable: -1, at: old), freshness: MarketContextFreshness(),
                premium: PremiumSnapshot(value: 10, change24h: 0), btcChange24h: 0, btcChange5m: 0,
                language: language, btcUpdatedAt: now, premiumUpdatedAt: old, now: now)
            XCTAssertEqual(stale.checklist.count, 1)
            XCTAssertTrue(stale.checklist[0].hasPrefix(language == .english ? "Alignment check:" : "정렬 확인:"))
            for (oi, funding) in [(nil, Optional(0.1)), (Optional(10.0), nil)] {
                let read = make(language, oi: oi, funding: funding)
                XCTAssertEqual(read.checklist.count, 1)
                XCTAssertTrue(read.checklist[0].hasPrefix(language == .english ? "Alignment check:" : "정렬 확인:"))
            }
        }
    }

    func testFailedRefreshAndOldETFReportsCannotLeakIntoChecks() {
        for language in AppLanguage.allCases {
            var freshness = MarketContextFreshness()
            freshness.fast.didFail(at: now)
            let failed = makeMarketRead(macro: macro(), fast: fast(oi: 10, funding: 0.1), investor: nil,
                freshness: freshness, premium: nil, btcChange24h: nil, btcChange5m: nil, language: language, now: now)
            XCTAssertEqual(failed.checklist.count, 1)
            XCTAssertTrue(failed.checklist[0].hasPrefix(language == .english ? "Alignment check:" : "정렬 확인:"))
            let oldReport = makeMarketRead(macro: macro(), fast: nil,
                investor: investor(etf: -1e9, stable: -1, report: now.addingTimeInterval(-10 * 86_400)),
                freshness: MarketContextFreshness(), premium: nil, btcChange24h: nil, btcChange5m: nil, language: language, now: now)
            XCTAssertEqual(oldReport.checklist.count, 1)
            XCTAssertTrue(oldReport.checklist[0].hasPrefix(language == .english ? "Shrinking liquidity:" : "유동성 축소:"))
        }
    }

    private func make(_ language: AppLanguage, oi: Double? = 0, funding: Double? = 0, premium: Double = 0, etf: Double = 0, stable: Double = 0) -> MarketRead {
        makeMarketRead(macro: macro(), fast: fast(oi: oi, funding: funding), investor: investor(etf: etf, stable: stable),
            freshness: MarketContextFreshness(), premium: PremiumSnapshot(value: premium, change24h: 0),
            btcChange24h: 0, btcChange5m: 0, language: language, btcUpdatedAt: now, premiumUpdatedAt: now, now: now)
    }

    private func macro(at date: Date? = nil) -> MacroMarketSnapshot {
        MacroMarketSnapshot(btcDominance: 60, btcDominanceChange24hPP: 0.3, usdtDominance: 5, usdtDominanceChange24hPP: -0.2,
            total3USD: 1e12, total3Change24h: 2, updatedAt: date ?? now)
    }

    private func fast(oi: Double?, funding: Double?, at date: Date? = nil) -> FastMarketSnapshot {
        FastMarketSnapshot(ethBTC: 0.04, ethBTCChange24h: 1, openInterestUSD: 4e10, openInterestChange1h: oi,
            fundingRatePercent: funding, updatedAt: date ?? now)
    }

    private func investor(etf: Double, stable: Double, at date: Date? = nil, report: Date? = nil) -> InvestorMarketSnapshot {
        InvestorMarketSnapshot(stablecoinSupplyUSD: 2e11, stablecoinSupplyChange7d: stable, etfLatestFlowUSD: 0,
            etfFiveDayFlowUSD: etf, etfFlowDate: report ?? now.addingTimeInterval(-86_400), btcReturn7d: 0,
            btcReturn30d: 0, btc200DMA: 60_000, btcAbove200DMA: true, updatedAt: date ?? now)
    }
}
