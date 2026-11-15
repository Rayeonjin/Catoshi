import XCTest
@testable import Catoshi

final class MarketCalculationTests: XCTestCase {
    let now = Date(timeIntervalSince1970: 2_000_000_000)
    func testOIQuantityAndObservationValidation() {
        let stamp: Int64 = 2_000_000_000_000
        XCTAssertEqual(MarketCalculationRules.openInterestChange([(stamp - 3_600_000, 100), (stamp, 100)], now: now), 0)
        XCTAssertNil(MarketCalculationRules.openInterestChange([(stamp - 7_200_000, 100), (stamp, 110)], now: now))
        XCTAssertNil(MarketCalculationRules.openInterestChange([(stamp - 3_600_000, 100), (stamp, 110)], now: now.addingTimeInterval(4500)))
        XCTAssertNil(MarketCalculationRules.openInterestChange([(stamp - 3_600_000, 0), (stamp, 110)], now: now))
        XCTAssertNil(MarketCalculationRules.openInterestChange([(stamp - 3_600_000, 100), (stamp, 110)], now: now.addingTimeInterval(-1)))
    }
    func testMacroClockMismatchAndMissingDateRejectChanges() {
        let date = ISO8601DateFormatter().string(from: now)
        XCTAssertTrue(MarketCalculationRules.synchronized([date, date, date], reference: now))
        XCTAssertFalse(MarketCalculationRules.synchronized([date, nil, date], reference: now))
        XCTAssertFalse(MarketCalculationRules.synchronized([date, date, date], reference: now.addingTimeInterval(121)))
    }
    func testETFDuplicateDatesDoNotBecomeExtraTradingDays() {
        let previous = now.addingTimeInterval(-86400)
        let rows = MarketCalculationRules.uniqueDailyFlows([(now, 1), (now, 1), (previous, 2)], now: now)
        XCTAssertEqual(rows.count, 2)
        XCTAssertTrue(MarketCalculationRules.uniqueDailyFlows([(now, 1), (now, 2)], now: now).isEmpty)
    }
    func testUnclosedDailyCandleCannotChangeTrend() {
        let start = now.timeIntervalSince1970 * 1000 - 200 * 86_400_000
        var rows: [[Any]] = (0..<200).map { i in [0, "0", "0", "0", "100", "0", start + Double(i) * 86_400_000] }
        rows.append([0, "0", "0", "0", "999999", "0", now.timeIntervalSince1970 * 1000 + 1])
        XCTAssertEqual(MarketCalculationRules.closedDailyPrices(rows, now: now).count, 200)
        XCTAssertEqual(MarketCalculationRules.closedDailyPrices(rows, now: now).last, 100)
        rows.remove(at: 100)
        XCTAssertTrue(MarketCalculationRules.closedDailyPrices(rows, now: now).isEmpty)
    }
    func testConsistentNeutralAndSimultaneousFundingRisk() {
        for language in AppLanguage.allCases {
            XCTAssertEqual(MarketReadRules.price(day: 0, short: nil, language: language).signal,
                MarketReadRules.price(day: 0, short: 0, language: language).signal)
            let lev = MarketReadRules.leverage(oi: -5, funding: 0.1, language: language)
            XCTAssertTrue(lev.signal.contains(language.pick("펀딩", "funding")))
            XCTAssertTrue(MarketReadRules.leverage(oi: nil, funding: 0.1, language: language).signal.contains(language.pick("펀딩", "Funding")))
            XCTAssertEqual(MarketReadRules.leadership(btc: .up, total3: .up, eth: .up, language: language).signal, language.pick("BTC 상대 우위", "BTC relative leadership"))
        }
    }
}
