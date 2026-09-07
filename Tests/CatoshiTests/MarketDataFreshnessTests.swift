import XCTest
@testable import Catoshi

final class MarketDataFreshnessTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 2_000_000_000)

    func testAgeLimitsIncludeBoundaryAndRejectFutureClockErrors() {
        let state = MarketRefreshState()
        for source in MarketDataSource.allCases {
            XCTAssertEqual(state.status(updatedAt: nil, source: source, now: now), .waiting)
            XCTAssertEqual(state.status(updatedAt: now.addingTimeInterval(-source.maximumAge + 0.001), source: source, now: now), .fresh)
            XCTAssertEqual(state.status(updatedAt: now.addingTimeInterval(-source.maximumAge), source: source, now: now), .stale)
            XCTAssertEqual(state.status(updatedAt: now.addingTimeInterval(60), source: source, now: now), .fresh)
            XCTAssertEqual(state.status(updatedAt: now.addingTimeInterval(61), source: source, now: now), .stale)
        }
    }

    func testAttemptDoesNotClearFailureAndOnlySuccessRecovers() {
        var state = MarketRefreshState()
        state.didSucceed(at: now, isPartial: false)
        state.didFail(at: now.addingTimeInterval(1))
        XCTAssertEqual(state.status(updatedAt: now, source: .macro, now: now.addingTimeInterval(2)), .failed)
        state.didAttempt(at: now.addingTimeInterval(3))
        XCTAssertEqual(state.status(updatedAt: now, source: .macro, now: now.addingTimeInterval(3)), .failed)
        XCTAssertFalse(state.shouldRefresh(source: .macro, now: now.addingTimeInterval(53), force: true))
        state.didCancel()
        XCTAssertFalse(state.shouldRefresh(source: .macro, now: now.addingTimeInterval(50), force: false))
        XCTAssertTrue(state.shouldRefresh(source: .macro, now: now.addingTimeInterval(51), force: false))
        state.didSucceed(at: now.addingTimeInterval(54), isPartial: true)
        XCTAssertNil(state.lastFailureAt)
        XCTAssertEqual(state.status(updatedAt: now, source: .macro, now: now.addingTimeInterval(54)), .partial)
    }

    func testCancelledColdStartCanRetryImmediatelyWithoutOverlappingRequests() {
        var state = MarketRefreshState()
        state.didAttempt(at: now)
        XCTAssertFalse(state.shouldRefresh(source: .macro, now: now, force: true))
        state.didCancel()
        XCTAssertTrue(state.shouldRefresh(source: .macro, now: now, force: false))
        XCTAssertEqual(state.status(updatedAt: nil, source: .macro, now: now), .waiting)
        state.didSucceed(at: now, isPartial: false)
        state.didAttempt(at: now.addingTimeInterval(1))
        state.didCancel()
        XCTAssertFalse(state.shouldRefresh(source: .macro, now: now.addingTimeInterval(2), force: false))
        XCTAssertEqual(state.status(updatedAt: now, source: .macro, now: now.addingTimeInterval(2)), .fresh)
    }

    func testStaleSnapshotsAreRemovedIndependently() {
        let inputs = MarketInterpretationInputs(
            macro: Fixtures.macro(now), fast: Fixtures.fast(now.addingTimeInterval(-180)),
            investor: Fixtures.investor(now.addingTimeInterval(-7_200)),
            freshness: MarketContextFreshness(), now: now)
        XCTAssertNotNil(inputs.macro)
        XCTAssertNil(inputs.fast)
        XCTAssertNil(inputs.investor)
    }

    func testPartialMacroCannotProduceDirectionalRead() {
        let macro = MacroMarketSnapshot(btcDominance: 60, btcDominanceChange24hPP: nil,
            usdtDominance: 5, usdtDominanceChange24hPP: nil, total3USD: 1e12,
            total3Change24h: nil, updatedAt: now)
        let read = makeMarketRead(macro: macro, fast: Fixtures.fast(now), investor: Fixtures.investor(now),
            freshness: MarketContextFreshness(), premium: nil, btcChange24h: nil, btcChange5m: nil, language: .english, now: now)
        XCTAssertEqual(read.title, "Market read paused")
        XCTAssertEqual(read.alignment, "Read paused")
        XCTAssertTrue(read.dimensions.allSatisfy { $0.signal == "Waiting" })
    }

    func testFreshFetchCannotMakeOldETFReportCurrent() {
        let reportDate = now.addingTimeInterval(-7 * 24 * 60 * 60)
        let inputs = MarketInterpretationInputs(macro: Fixtures.macro(now), fast: Fixtures.fast(now),
            investor: Fixtures.investor(now, reportDate: reportDate), freshness: MarketContextFreshness(), now: now)
        XCTAssertNil(inputs.investor?.etfFiveDayFlowUSD)
        XCTAssertNil(inputs.investor?.etfLatestFlowUSD)
        XCTAssertNotNil(inputs.investor?.btcReturn30d)
        XCTAssertNotNil(inputs.investor?.stablecoinSupplyChange7d)
        XCTAssertTrue(MarketInterpretationInputs.etfReportIsCurrent(reportDate.addingTimeInterval(1), now: now))
        XCTAssertFalse(MarketInterpretationInputs.etfReportIsCurrent(nil, now: now))
    }

    func testStaleAuxiliaryDataIsAbsentFromReadBasis() {
        let read = makeMarketRead(macro: Fixtures.macro(now), fast: Fixtures.fast(now.addingTimeInterval(-180)),
            investor: Fixtures.investor(now.addingTimeInterval(-7_200)), freshness: MarketContextFreshness(),
            premium: nil, btcChange24h: nil, btcChange5m: nil, language: .english, now: now)
        XCTAssertFalse(read.basis.contains("ETH/BTC"))
        XCTAssertFalse(read.basis.contains("ETF"))
        XCTAssertFalse(read.basis.contains("Funding"))
        XCTAssertTrue(read.alignment.contains("Some inputs excluded"))
    }

    func testUnknownAndStaleCoreQuoteTimesCannotAffectRead() {
        func read(premium: PremiumSnapshot?, change: Double?, date: Date?) -> MarketRead {
            makeMarketRead(macro: Fixtures.macro(now), fast: Fixtures.fast(now), investor: nil,
                freshness: MarketContextFreshness(), premium: premium, btcChange24h: change, btcChange5m: change,
                language: .english, btcUpdatedAt: date, premiumUpdatedAt: date, now: now)
        }
        let expected = read(premium: nil, change: nil, date: nil)
        for date in [nil, Optional(now.addingTimeInterval(-180))] {
            let actual = read(premium: PremiumSnapshot(value: 15, change24h: 10), change: -30, date: date)
            XCTAssertEqual(actual.summary, expected.summary)
            XCTAssertEqual(actual.basis, expected.basis)
        }
    }

    func testDomesticShareStatusPreservesFailuresAndPartialRetainedSnapshots() {
        let recent = now.addingTimeInterval(-30)
        let retainedIssue = DomesticRefreshIssue.partialDataRetainingLastComplete(maintenance: [.bithumb], unavailable: [.coinone])
        for (language, failed, absent, retained, partial) in [
            (AppLanguage.english, "Refresh failed; retained", "Refresh failed; no data", "Partial; last complete", "Partial"),
            (AppLanguage.korean, "갱신 실패 · 이전값", "갱신 실패 · 값 없음", "일부 누락 · 이전 전체값", "일부 누락")
        ] {
            // The numeric snapshot is complete and only 30 seconds old, but a
            // later failed/partial request must win over that recent timestamp.
            XCTAssertEqual(CatoshiShareMetadata.domesticStatus(updatedAt: recent, isPartial: false,
                issue: .refreshFailed, language: language, now: now), failed)
            XCTAssertEqual(CatoshiShareMetadata.domesticStatus(updatedAt: nil, isPartial: false,
                issue: .refreshFailed, language: language, now: now), absent)
            XCTAssertEqual(CatoshiShareMetadata.domesticStatus(updatedAt: recent, isPartial: false,
                issue: retainedIssue, language: language, now: now), retained)
            XCTAssertEqual(CatoshiShareMetadata.domesticStatus(updatedAt: recent, isPartial: false,
                issue: .partialData(maintenance: [], unavailable: [.coinone]), language: language, now: now), partial)
            XCTAssertEqual(CatoshiShareMetadata.domesticStatus(updatedAt: recent, isPartial: true,
                issue: nil, language: language, now: now), partial)
        }
        XCTAssertEqual(CatoshiShareMetadata.domesticStatus(updatedAt: now.addingTimeInterval(-1_200 + 0.001),
            isPartial: false, issue: nil, language: .english, now: now), "Received")
        XCTAssertEqual(CatoshiShareMetadata.domesticStatus(updatedAt: now.addingTimeInterval(-1_200),
            isPartial: false, issue: nil, language: .english, now: now), "Stale/waiting")
        XCTAssertEqual(CatoshiShareMetadata.domesticStatus(updatedAt: nil,
            isPartial: false, issue: nil, language: .english, now: now), "Stale/waiting")
    }

    func testLongShareSummaryFitsWithoutDroppingLateRiskSignals() {
        for language in AppLanguage.allCases {
            let read = makeMarketRead(macro: Fixtures.macro(now), fast: Fixtures.fast(now),
                investor: Fixtures.investor(now), freshness: MarketContextFreshness(),
                premium: PremiumSnapshot(value: 8, change24h: 1), btcChange24h: 2,
                btcChange5m: 0.2, language: language, btcUpdatedAt: now,
                premiumUpdatedAt: now, now: now)
            for format in CatoshiShareFormat.allCases {
                XCTAssertFalse(CatoshiShareSummary.fits(read.summary, format: format))
                let summary = CatoshiShareSummary.text(for: read, language: language, format: format)
                XCTAssertTrue(CatoshiShareSummary.fits(summary, format: format))
                XCTAssertTrue(summary.hasSuffix("."))
                XCTAssertFalse(summary.contains("…"))
                XCTAssertTrue(summary.hasPrefix(language.pick("BTC의 상대 점유율은", "BTC dominance is rising")))
                for badge in read.badges { XCTAssertTrue(summary.contains(badge)) }
                XCTAssertTrue(summary.contains(language.pick("롱 과열", "Crowded longs")))
                XCTAssertTrue(summary.contains(language.pick("국내 FOMO", "Korea FOMO")))
            }
        }
    }

    func testShortShareSummaryRemainsUnchanged() {
        for language in AppLanguage.allCases {
            let read = makeMarketRead(macro: nil, fast: nil, investor: nil,
                freshness: MarketContextFreshness(), premium: nil, btcChange24h: nil,
                btcChange5m: nil, language: language, now: now)
            for format in CatoshiShareFormat.allCases {
                XCTAssertTrue(CatoshiShareSummary.fits(read.summary, format: format))
                XCTAssertEqual(CatoshiShareSummary.text(for: read, language: language, format: format), read.summary)
            }
        }
    }

    func testShareCaptionPreservesFullTimestampAndUTCOffset() {
        let date = Date(timeIntervalSince1970: 0)
        for (offset, expected, compact) in [
            (9 * 3_600, "1970-01-01 09:00:00 +09:00", "01-01 09:00"),
            (-5 * 3_600, "1969-12-31 19:00:00 -05:00", "12-31 19:00")
        ] {
            let zone = TimeZone(secondsFromGMT: offset)!
            let full = CatoshiShareMetadata.time(date, full: true, timeZone: zone)
            XCTAssertEqual(full, expected)
            // Image metadata keeps its compact layout while copied captions retain
            // the year, seconds and timezone needed after the card is redistributed.
            XCTAssertEqual(CatoshiShareMetadata.time(date, timeZone: zone), compact)
            for language in [AppLanguage.korean, .english] {
                let content = CatoshiShareCaptionBuilder.content(section: .domestic, language: language,
                    observation: "24h observed " + full)
                XCTAssertTrue(content.fullCaption.contains(expected))
                XCTAssertTrue(content.systemText.contains(expected))
            }
        }
        XCTAssertEqual(CatoshiShareMetadata.time(nil, full: true, timeZone: TimeZone(secondsFromGMT: 0)!), "--")
    }

    @MainActor
    func testModelRetainsFailedNumbersButResumesInterpretationOnlyAfterRecovery() async {
        let clock = TestClock(now)
        let service = StubMarketService(date: now)
        let model = MarketContextModel(service: service, now: { clock.date }, startsBackgroundTasks: false)
        await model.refreshMarketData(force: true)
        XCTAssertEqual(model.status(for: .macro, at: clock.date), .fresh)
        XCTAssertNotNil(model.interpretationInputs(at: clock.date).macro)

        clock.date.addTimeInterval(1)
        service.fails = true
        await model.refreshMarketData(force: true)
        XCTAssertEqual(model.macro?.updatedAt, now)
        XCTAssertEqual(model.fast?.updatedAt, now)
        XCTAssertEqual(model.investor?.updatedAt, now)
        for source in MarketDataSource.allCases { XCTAssertEqual(model.status(for: source, at: clock.date), .failed) }
        let blocked = model.interpretationInputs(at: clock.date)
        XCTAssertNil(blocked.macro)
        XCTAssertNil(blocked.fast)
        XCTAssertNil(blocked.investor)

        clock.date.addTimeInterval(1)
        service.fails = false
        service.date = clock.date
        await model.refreshMarketData(force: true)
        for source in MarketDataSource.allCases { XCTAssertEqual(model.status(for: source, at: clock.date), .fresh) }
        XCTAssertEqual(model.macro?.updatedAt, clock.date)
        XCTAssertNotNil(model.interpretationInputs(at: clock.date).macro)
    }

    @MainActor
    func testCancellingModelFetchLeavesNoFailureAndCanRetry() async {
        let service = StubMarketService(date: now)
        service.waitsForCancellation = true
        let model = MarketContextModel(service: service, now: { self.now }, startsBackgroundTasks: false)
        let request = Task { await model.refreshMarketData(force: true) }
        while !MarketDataSource.allCases.allSatisfy({ model.freshness[$0].isInFlight }) {
            await Task.yield()
        }
        request.cancel()
        await request.value
        for source in MarketDataSource.allCases {
            XCTAssertFalse(model.freshness[source].isInFlight)
            XCTAssertNil(model.freshness[source].lastFailureAt)
            XCTAssertEqual(model.status(for: source, at: now), .waiting)
        }
        service.waitsForCancellation = false
        await model.refreshMarketData(force: false)
        for source in MarketDataSource.allCases { XCTAssertEqual(model.status(for: source, at: now), .fresh) }
    }

    @MainActor
    func testSourceCadencesAndPartialFailureDoNotReuseMissingFunding() async {
        let clock = TestClock(now)
        let service = StubMarketService(date: now)
        let model = MarketContextModel(service: service, now: { clock.date }, startsBackgroundTasks: false)
        await model.refreshMarketData(force: false)
        clock.date.addTimeInterval(60)
        service.date = clock.date
        service.fundingAvailable = false
        await model.refreshMarketData(force: false)
        XCTAssertEqual(service.macroCalls, 1)
        XCTAssertEqual(service.fastCalls, 2)
        XCTAssertEqual(service.investorCalls, 1)
        XCTAssertEqual(model.status(for: .fast, at: clock.date), .partial)
        XCTAssertNil(model.fast?.fundingRatePercent)
        XCTAssertNil(model.interpretationInputs(at: clock.date).fast?.fundingRatePercent)
        XCTAssertNotNil(model.interpretationInputs(at: clock.date).fast?.ethBTC)
    }

    @MainActor
    func testDomesticManualRefreshJoinsBackgroundRequestAndPublishesItsResult() async {
        let service = ControlledDomesticService()
        let model = MarketContextModel(service: service, now: { self.now }, startsBackgroundTasks: false)
        let background = Task { await model.refreshDomestic(force: true, publish: false) }
        await waitUntil { service.calls == 1 }
        var manualEntered = false
        let manual = Task {
            manualEntered = true
            await model.refreshDomestic(force: true, publish: true)
        }
        await waitUntil { manualEntered }
        XCTAssertEqual(service.calls, 1)
        XCTAssertEqual(service.maximumConcurrentCalls, 1)
        // A tab schedule can be cancelled while its shared fetch still has a
        // manual waiter. That caller must keep receiving the useful response.
        background.cancel()
        // Also let the pre-fix duplicate complete so a failing regression cannot hang.
        if service.calls > 1 { service.succeed(call: 2, snapshot: Fixtures.domestic(now)) }
        service.succeed(call: 1, snapshot: Fixtures.domestic(now))
        await background.value
        await manual.value
        XCTAssertEqual(model.domestic?.updatedAt, now)
        XCTAssertNil(model.domesticRefreshIssue)
        XCTAssertNil(model.domesticActivity)
    }

    @MainActor
    func testDomesticOlderResponseCannotReplaceNewerSnapshot() async {
        let service = ControlledDomesticService()
        let model = MarketContextModel(service: service, now: { self.now }, startsBackgroundTasks: false)
        let first = Task { await model.refreshDomestic(force: true, publish: true) }
        await waitUntil { service.calls == 1 }
        service.succeed(call: 1, snapshot: Fixtures.domestic(now))
        await first.value
        let second = Task { await model.refreshDomestic(force: true, publish: true) }
        await waitUntil { service.calls == 2 }
        service.succeed(call: 2, snapshot: Fixtures.domestic(now.addingTimeInterval(-1)))
        await second.value
        XCTAssertEqual(model.domestic?.updatedAt, now)
    }

    @MainActor
    func testDomesticBackgroundFailureSurvivesCachedPublication() async {
        let service = ControlledDomesticService()
        let model = MarketContextModel(service: service, now: { self.now }, startsBackgroundTasks: false)
        let initial = Task { await model.refreshDomestic(force: true, publish: false) }
        await waitUntil { service.calls == 1 }
        service.succeed(call: 1, snapshot: Fixtures.domestic(now))
        await initial.value
        let failed = Task { await model.refreshDomestic(force: true, publish: false) }
        await waitUntil { service.calls == 2 }
        service.fail(call: 2, error: URLError(.notConnectedToInternet))
        await failed.value
        await model.refreshDomestic(force: false, publish: true)
        XCTAssertEqual(service.calls, 2)
        XCTAssertEqual(model.domestic?.updatedAt, now)
        XCTAssertEqual(model.domesticRefreshIssue?.message(.english), DomesticRefreshIssue.refreshFailed.message(.english))
        let recovery = Task { await model.refreshDomestic(force: true, publish: false) }
        await waitUntil { service.calls == 3 }
        service.succeed(call: 3, snapshot: Fixtures.domestic(now.addingTimeInterval(1)))
        await recovery.value
        await model.refreshDomestic(force: false, publish: true)
        XCTAssertEqual(service.calls, 3)
        XCTAssertEqual(model.domestic?.updatedAt, now.addingTimeInterval(1))
        XCTAssertNil(model.domesticRefreshIssue)
    }

    @MainActor
    func testDomesticReconnectWaitsForCancelledFetchAndRetriesWithoutFailure() async {
        let service = ControlledDomesticService()
        let model = MarketContextModel(service: service, now: { self.now }, startsBackgroundTasks: false)
        let interrupted = Task { await model.refreshDomestic(force: true, publish: true) }
        await waitUntil { service.calls == 1 }
        model.setNetworkAvailable(false)
        model.setNetworkAvailable(true)
        var recoveryEntered = false
        let recovered = Task {
            recoveryEntered = true
            await model.refreshDomestic(force: false, publish: true)
        }
        await waitUntil { recoveryEntered }
        XCTAssertEqual(service.calls, 1)
        service.fail(call: 1, error: URLError(.cancelled))
        await interrupted.value
        await waitUntil { service.calls == 2 }
        XCTAssertNil(model.domesticRefreshIssue)
        service.succeed(call: 2, snapshot: Fixtures.domestic(now))
        await recovered.value
        XCTAssertEqual(service.maximumConcurrentCalls, 1)
        XCTAssertEqual(model.domestic?.updatedAt, now)
        XCTAssertNil(model.domesticRefreshIssue)
    }

    @MainActor
    func testDomesticCancelledResponseCannotPublishAfterDisplaySuspends() async {
        let service = ControlledDomesticService()
        let model = MarketContextModel(service: service, now: { self.now }, startsBackgroundTasks: false)
        let request = Task { await model.refreshDomestic(force: true, publish: true) }
        await waitUntil { service.calls == 1 }
        model.setDisplayActive(false)
        // Some services complete successfully despite cancellation. The model
        // must still discard the response and avoid reporting a fetch failure.
        service.succeed(call: 1, snapshot: Fixtures.domestic(now))
        await request.value
        XCTAssertNil(model.domestic)
        XCTAssertNil(model.domesticRefreshIssue)
        XCTAssertNil(model.domesticActivity)
    }

    @MainActor
    func testDomesticCoalescedPartialResultRetainsLastCompleteTotal() async {
        let service = ControlledDomesticService()
        let model = MarketContextModel(service: service, now: { self.now }, startsBackgroundTasks: false)
        let first = Task { await model.refreshDomestic(force: true, publish: true) }
        await waitUntil { service.calls == 1 }
        service.succeed(call: 1, snapshot: Fixtures.domestic(now))
        await first.value
        let background = Task { await model.refreshDomestic(force: true, publish: false) }
        await waitUntil { service.calls == 2 }
        var manualEntered = false
        let manual = Task {
            manualEntered = true
            await model.refreshDomestic(force: true, publish: true)
        }
        await waitUntil { manualEntered }
        XCTAssertEqual(service.calls, 2)
        let partial = DomesticVolumeSnapshot(
            entries: [.init(exchange: .upbit, krw24h: 2_000)],
            availability: DomesticExchange.allCases.map {
                DomesticExchangeAvailability(exchange: $0, state: $0 == .upbit ? .available : .unavailable)
            }, updatedAt: now.addingTimeInterval(1), isPartial: true)
        service.succeed(call: 2, snapshot: partial)
        await background.value
        await manual.value
        XCTAssertEqual(model.domestic?.updatedAt, now)
        XCTAssertEqual(model.domestic?.total, 5_000)
        XCTAssertEqual(model.domesticAvailability.filter { $0.state == .available }.count, 1)
        XCTAssertTrue(model.domesticRefreshIssue?.message(.english).contains("The last complete snapshot is being kept.") == true)
    }

    @MainActor
    private func waitUntil(_ condition: () -> Bool) async {
        for _ in 0..<1_000 {
            if condition() { return }
            await Task.yield()
        }
        XCTAssertTrue(condition())
    }
}

private final class TestClock {
    var date: Date
    init(_ date: Date) { self.date = date }
}

private enum Fixtures {
    static func domestic(_ date: Date) -> DomesticVolumeSnapshot {
        DomesticVolumeSnapshot(entries: DomesticExchange.allCases.map { DomesticExchangeVolume(exchange: $0, krw24h: 1_000) },
            availability: DomesticExchange.allCases.map { DomesticExchangeAvailability(exchange: $0, state: .available) },
            updatedAt: date, isPartial: false)
    }

    static func macro(_ date: Date) -> MacroMarketSnapshot {
        MacroMarketSnapshot(btcDominance: 60, btcDominanceChange24hPP: 0.3, usdtDominance: 5,
            usdtDominanceChange24hPP: -0.2, total3USD: 1e12, total3Change24h: 2, updatedAt: date)
    }

    static func fast(_ date: Date, fundingAvailable: Bool = true) -> FastMarketSnapshot {
        FastMarketSnapshot(ethBTC: 0.04, ethBTCChange24h: 1, openInterestUSD: 4e10,
            openInterestChange1h: 6, fundingRatePercent: fundingAvailable ? 0.1 : nil, updatedAt: date)
    }

    static func investor(_ date: Date, reportDate: Date? = nil) -> InvestorMarketSnapshot {
        InvestorMarketSnapshot(stablecoinSupplyUSD: 2e11, stablecoinSupplyChange7d: 1,
            etfLatestFlowUSD: 2e8, etfFiveDayFlowUSD: 8e8, etfFlowDate: reportDate ?? date.addingTimeInterval(-86_400),
            btcReturn7d: 3, btcReturn30d: 10, btc200DMA: 60_000, btcAbove200DMA: true, updatedAt: date)
    }
}

@MainActor
private final class ControlledDomesticService: MarketContextFetching {
    private var pending: [Int: CheckedContinuation<DomesticVolumeSnapshot, Error>] = [:]
    private(set) var calls = 0
    private(set) var maximumConcurrentCalls = 0

    func fetchDomesticExchangeVolumes() async throws -> DomesticVolumeSnapshot {
        calls += 1
        let call = calls
        return try await withCheckedThrowingContinuation { continuation in
            pending[call] = continuation
            maximumConcurrentCalls = max(maximumConcurrentCalls, pending.count)
        }
    }

    func succeed(call: Int, snapshot: DomesticVolumeSnapshot) {
        pending.removeValue(forKey: call)?.resume(returning: snapshot)
    }

    func fail(call: Int, error: Error) {
        pending.removeValue(forKey: call)?.resume(throwing: error)
    }

    func fetchMacroMarket() async throws -> MacroMarketSnapshot { throw URLError(.notConnectedToInternet) }
    func fetchFastMarket() async throws -> FastMarketSnapshot { throw URLError(.notConnectedToInternet) }
    func fetchInvestorMarket() async throws -> InvestorMarketSnapshot { throw URLError(.notConnectedToInternet) }
}

private final class StubMarketService: MarketContextFetching {
    var date: Date
    var fails = false
    var fundingAvailable = true
    var waitsForCancellation = false
    var macroCalls = 0
    var fastCalls = 0
    var investorCalls = 0
    init(date: Date) { self.date = date }

    func fetchDomesticExchangeVolumes() async throws -> DomesticVolumeSnapshot { throw URLError(.notConnectedToInternet) }
    func fetchMacroMarket() async throws -> MacroMarketSnapshot {
        macroCalls += 1
        if waitsForCancellation { try await Task.sleep(for: .seconds(30)) }
        if fails { throw URLError(.notConnectedToInternet) }
        return Fixtures.macro(date)
    }
    func fetchFastMarket() async throws -> FastMarketSnapshot {
        fastCalls += 1
        if waitsForCancellation { try await Task.sleep(for: .seconds(30)) }
        if fails { throw URLError(.notConnectedToInternet) }
        return Fixtures.fast(date, fundingAvailable: fundingAvailable)
    }
    func fetchInvestorMarket() async throws -> InvestorMarketSnapshot {
        investorCalls += 1
        if waitsForCancellation { try await Task.sleep(for: .seconds(30)) }
        if fails { throw URLError(.notConnectedToInternet) }
        return Fixtures.investor(date)
    }
}
