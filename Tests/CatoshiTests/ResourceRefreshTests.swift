import Foundation
import XCTest
@testable import Catoshi

final class ResourceRefreshTests: XCTestCase {
    func testVenueBackoffSkipsOnlyFailedVenueAndManualRefreshRecovers() async throws {
        let fixture = ResourceFixture()
        fixture.upbitFails = true
        let session = fixture.session()
        defer { session.invalidateAndCancel() }
        let clock = ResourceClock()
        let service = MarketContextService(session: session, now: { clock.date })
        _ = try await service.fetchDomesticExchangeVolumes()
        clock.advance(60)
        let skipped = try await service.fetchDomesticExchangeVolumes()
        XCTAssertEqual(fixture.count("/v1/ticker/all"), 1)
        XCTAssertEqual(fixture.count("/public/ticker/ALL_KRW"), 2)
        XCTAssertTrue(skipped.isPartial)
        XCTAssertFalse(skipped.entries.contains { $0.exchange == .upbit })
        XCTAssertEqual(skipped.availability.first { $0.exchange == .upbit }?.state, .unavailable)

        clock.advance(120) // first retry after 3 minutes
        _ = try await service.fetchDomesticExchangeVolumes()
        XCTAssertEqual(fixture.count("/v1/ticker/all"), 2)
        clock.advance(299)
        _ = try await service.fetchDomesticExchangeVolumes()
        XCTAssertEqual(fixture.count("/v1/ticker/all"), 2)
        clock.advance(1) // second retry after 5 minutes
        _ = try await service.fetchDomesticExchangeVolumes()
        XCTAssertEqual(fixture.count("/v1/ticker/all"), 3)
        clock.advance(899)
        _ = try await service.fetchDomesticExchangeVolumes()
        XCTAssertEqual(fixture.count("/v1/ticker/all"), 3)
        clock.advance(1) // subsequent retries after 15 minutes
        _ = try await service.fetchDomesticExchangeVolumes()
        XCTAssertEqual(fixture.count("/v1/ticker/all"), 4)
        fixture.upbitFails = false
        let recovered = try await service.fetchDomesticExchangeVolumes(force: true)
        XCTAssertEqual(fixture.count("/v1/ticker/all"), 5)
        XCTAssertFalse(recovered.isPartial)
        XCTAssertEqual(recovered.entries.first { $0.exchange == .upbit }?.krw24h, 1000)
        _ = try await service.fetchDomesticExchangeVolumes()
        XCTAssertEqual(fixture.count("/v1/ticker/all"), 6)
    }

    func testOIIsReusedForFiveMinutesWithoutRetimestampingAndFailureIsNotHidden() async throws {
        let fixture = ResourceFixture()
        let session = fixture.session()
        defer { session.invalidateAndCancel() }
        let clock = ResourceClock()
        let service = MarketContextService(session: session, now: { clock.date })
        let first = try await service.fetchFastMarket()
        clock.advance(60)
        let second = try await service.fetchFastMarket()
        XCTAssertEqual(fixture.count("/futures/data/openInterestHist"), 1)
        XCTAssertEqual(fixture.count("/api/v3/ticker/24hr"), 2)
        XCTAssertEqual(second.openInterestFetchedAt, first.openInterestFetchedAt)
        XCTAssertEqual(second.updatedAt, clock.date)
        clock.advance(240)
        let refreshed = try await service.fetchFastMarket()
        XCTAssertEqual(fixture.count("/futures/data/openInterestHist"), 2)
        XCTAssertEqual(refreshed.openInterestFetchedAt, clock.date)
        _ = try await service.fetchFastMarket(force: true)
        XCTAssertEqual(fixture.count("/futures/data/openInterestHist"), 3)
        fixture.oiFails = true
        clock.advance(300)
        let failed = try await service.fetchFastMarket()
        XCTAssertNil(failed.openInterestUSD)
        XCTAssertNil(failed.openInterestFetchedAt)
        XCTAssertNotNil(failed.fundingRatePercent)
        XCTAssertEqual(fixture.count("/futures/data/openInterestHist"), 4)
    }

    func testExpiredOIIsExcludedEvenIfOtherFastValuesWereJustReceived() {
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        let fast = FastMarketSnapshot(ethBTC: 0.04, ethBTCChange24h: 1, openInterestUSD: 1e10,
            openInterestChange1h: 10, fundingRatePercent: 0.1, updatedAt: now,
            openInterestFetchedAt: now.addingTimeInterval(-CatoshiRuntimePolicy.openInterestMaximumAge))
        let inputs = MarketInterpretationInputs(macro: nil, fast: fast, investor: nil, freshness: MarketContextFreshness(), now: now)
        XCTAssertNil(inputs.fast?.openInterestUSD)
        XCTAssertNil(inputs.fast?.openInterestChange1h)
        XCTAssertEqual(inputs.fast?.fundingRatePercent, 0.1)
        XCTAssertEqual(inputs.fast?.ethBTC, 0.04)
    }

    func testChartSelectionReusesExistingStreamsAndDownloadsOnlyMissingInputs() async throws {
        let fixture = ResourceFixture()
        let session = fixture.session()
        defer { session.invalidateAndCancel() }
        let clock = ResourceClock()
        let service = HistoricalReferenceService(session: session, now: { clock.date })
        let btcOnly = SparklineSelection(binance: true, upbit: false, premium: false)
        _ = try await service.fetchSparkline24Hours(selection: btcOnly)
        XCTAssertEqual(fixture.total, 1)
        clock.advance(1)
        _ = try await service.fetchSparkline24Hours(selection: SparklineSelection(binance: true, upbit: true, premium: false))
        XCTAssertEqual(fixture.total, 2)
        let all = try await service.fetchSparkline24Hours(selection: .all)
        XCTAssertEqual(fixture.total, 3)
        XCTAssertFalse(all.premium.isEmpty)
        let remaining = await service.nextSparklineRefreshDelay(selection: .all)
        XCTAssertEqual(remaining, 599)
        clock.advance(599)
        _ = try await service.fetchSparkline24Hours(selection: btcOnly)
        XCTAssertEqual(fixture.total, 4)
    }

    func testReferenceWakeReuseDoesNotExtendCacheLifetimeAndExpiredFailureThrows() async throws {
        let fixture = ResourceFixture()
        let session = fixture.session()
        defer { session.invalidateAndCancel() }
        let clock = ResourceClock()
        let service = HistoricalReferenceService(session: session, now: { clock.date })
        _ = try await service.fetchReference24HoursAgo()
        XCTAssertEqual(fixture.total, 3)
        clock.advance(60)
        _ = try await service.fetchReference24HoursAgo()
        XCTAssertEqual(fixture.total, 3)
        let remaining = await service.nextReferenceRefreshDelay()
        XCTAssertEqual(remaining, 540)
        clock.advance(540)
        fixture.allFail = true
        do {
            _ = try await service.fetchReference24HoursAgo()
            XCTFail("An expired reference must not hide a failed request")
        } catch {}
        let expired = await service.nextReferenceRefreshDelay()
        XCTAssertEqual(expired, 0)
        fixture.allFail = false
        _ = try await service.fetchReference24HoursAgo()
        let fresh = await service.nextReferenceRefreshDelay()
        XCTAssertEqual(fresh, 600)
    }

    func testCancelledReferenceDoesNotPopulateCacheAndCanRetry() async throws {
        let fixture = ResourceFixture()
        fixture.delay = 0.2
        let session = fixture.session()
        defer { session.invalidateAndCancel() }
        let service = HistoricalReferenceService(session: session)
        let request = Task { try await service.fetchReference24HoursAgo() }
        for _ in 0..<1000 {
            if fixture.total > 0 { break }
            try await Task.sleep(for: .milliseconds(1))
        }
        XCTAssertTrue(fixture.total > 0)
        request.cancel()
        do {
            _ = try await request.value
            XCTFail("Cancelled reference unexpectedly succeeded")
        } catch {}
        let remaining = await service.nextReferenceRefreshDelay()
        XCTAssertEqual(remaining, 0)
        fixture.delay = 0
        _ = try await service.fetchReference24HoursAgo()
        let fresh = await service.nextReferenceRefreshDelay()
        XCTAssertTrue(fresh > 0)
    }

    @MainActor
    func testPartialRadarCanSettleAndRecoveredVenueGetsWarmStart() {
        let radar = DomesticActivityRadarEngine(persistenceEnabled: false)
        let start = Date(timeIntervalSince1970: 2_000_000_000)
        func snapshot(_ minute: Int, recovered: Bool) -> DomesticVolumeSnapshot {
            let venues = DomesticExchange.allCases.filter { recovered || $0 != .upbit }
            return DomesticVolumeSnapshot(entries: venues.map { DomesticExchangeVolume(exchange: $0, krw24h: 1000 + Double(minute)) },
                availability: DomesticExchange.allCases.map { DomesticExchangeAvailability(exchange: $0, state: venues.contains($0) ? .available : .unavailable) },
                updatedAt: start.addingTimeInterval(Double(minute * 60)), isPartial: !recovered)
        }
        for minute in stride(from: 0, through: 15, by: 3) { _ = radar.ingest(snapshot(minute, recovered: false)) }
        XCTAssertEqual(radar.preferredBackgroundCadence(now: start.addingTimeInterval(15 * 60)), 900)
        _ = radar.ingest(snapshot(18, recovered: true))
        XCTAssertEqual(radar.preferredBackgroundCadence(now: start.addingTimeInterval(18 * 60)), 180)
        for minute in stride(from: 21, through: 33, by: 3) { _ = radar.ingest(snapshot(minute, recovered: true)) }
        XCTAssertEqual(radar.preferredBackgroundCadence(now: start.addingTimeInterval(33 * 60)), 900)
    }

    func testCacheRejectsClockRollbackAndExpiryBoundary() {
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        let cached = FreshValue(value: 1, receivedAt: now)
        XCTAssertEqual(cached.remaining(at: now.addingTimeInterval(-1), lifetime: 600), 0)
        XCTAssertEqual(cached.remaining(at: now.addingTimeInterval(600), lifetime: 600), 0)
        XCTAssertEqual(cached.remaining(at: now.addingTimeInterval(599), lifetime: 600), 1)
    }
}

private final class ResourceClock {
    private let lock = NSLock()
    private var value = Date(timeIntervalSince1970: 2_000_000_000)
    var date: Date { lock.lock(); defer { lock.unlock() }; return value }
    func advance(_ seconds: TimeInterval) { lock.lock(); defer { lock.unlock() }; value.addTimeInterval(seconds) }
}

private final class ResourceFixture {
    private let lock = NSLock()
    private var counts: [String: Int] = [:]
    var upbitFails = false
    var oiFails = false
    var allFail = false
    var delay: TimeInterval = 0
    var total: Int { lock.lock(); defer { lock.unlock() }; return counts.values.reduce(0, +) }
    func count(_ path: String) -> Int { lock.lock(); defer { lock.unlock() }; return counts[path] ?? 0 }
    func session() -> URLSession {
        ResourceProtocol.fixture = self
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [ResourceProtocol.self]
        return URLSession(configuration: configuration)
    }
    func response(_ request: URLRequest) -> (Int, Data) {
        lock.lock(); defer { lock.unlock() }
        let path = request.url!.path
        counts[path, default: 0] += 1
        if allFail || (upbitFails && path == "/v1/ticker/all") || (oiFails && path == "/futures/data/openInterestHist") { return (503, Data("unavailable".utf8)) }
        let body: String
        switch path {
        case "/api/v3/ticker/24hr": body = #"{"lastPrice":"0.04","priceChangePercent":"1"}"#
        case "/fapi/v1/premiumIndex": body = #"{"lastFundingRate":"0.0001"}"#
        case "/futures/data/openInterestHist": body = #"[{"sumOpenInterestValue":"1000000","timestamp":1000},{"sumOpenInterestValue":"1100000","timestamp":2000}]"#
        case "/v1/ticker/all": body = #"[{"acc_trade_price_24h":1000}]"#
        case "/public/ticker/ALL_KRW": body = #"{"status":"0000","data":{}}"#
        case "/public/v2/ticker_new/KRW": body = #"{"result":"success","tickers":[]}"#
        case "/v2/tickers": body = #"{"success":true,"data":[]}"#
        case "/tickers": body = "[]"
        case "/api/v3/klines":
            let stamp = Int64(ISO8601DateFormatter().date(from: "2026-11-09T00:00:00Z")!.timeIntervalSince1970 * 1000)
            body = "[[\(stamp),\"0\",\"0\",\"0\",\"1000\",\"0\",\(stamp + 59999)]]"
        case "/v1/candles/minutes/15": body = #"[{"candle_date_time_utc":"2026-11-09T00:00:00","trade_price":10000}]"#
        case "/v1/candles/minutes/1": body = #"[{"trade_price":10000}]"#
        default: return (404, Data())
        }
        return (200, Data(body.utf8))
    }
}

private final class ResourceProtocol: URLProtocol {
    static var fixture: ResourceFixture?
    private var delivery: DispatchWorkItem?
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        guard let fixture = Self.fixture else { return }
        let (status, data) = fixture.response(request)
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: "HTTP/1.1", headerFields: nil)!
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            self.client?.urlProtocol(self, didLoad: data)
            self.client?.urlProtocolDidFinishLoading(self)
        }
        delivery = work
        DispatchQueue.global().asyncAfter(deadline: .now() + fixture.delay, execute: work)
    }
    override func stopLoading() { delivery?.cancel() }
}
