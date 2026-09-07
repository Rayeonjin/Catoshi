import Foundation

final class HistoricalReferenceService {
    private let session: URLSession

    init() {
        session = URLSession(configuration: CatoshiNetworkRuntime.ephemeralConfiguration(
            requestTimeout: 10,
            resourceTimeout: 30
        ))
    }

    func fetchRecentBinanceMinutePrices(count: Int) async throws -> [TimestampedPrice] {
        let clampedCount = min(max(count, 2), 30)
        var components = URLComponents(string: "https://api.binance.com/api/v3/klines")!
        components.queryItems = [
            URLQueryItem(name: "symbol", value: "BTCUSDT"),
            URLQueryItem(name: "interval", value: "1m"),
            URLQueryItem(name: "limit", value: String(clampedCount))
        ]

        let (data, response) = try await session.data(from: components.url!)
        try validate(response)

        guard let rows = try JSONSerialization.jsonObject(with: data) as? [[Any]] else {
            throw MarketDataError.invalidResponse
        }

        return rows.compactMap { row in
            guard row.count > 6,
                  let closeText = row[4] as? String,
                  let close = Double(closeText),
                  let closeNumber = row[6] as? NSNumber else { return nil }
            return TimestampedPrice(
                date: Date(timeIntervalSince1970: closeNumber.doubleValue / 1000.0),
                price: close
            )
        }
        .sorted { $0.date < $1.date }
    }

    func fetchSparkline24Hours() async throws -> HistoricalSeries {
        async let binance = fetchBinance15MinuteSeries()
        async let upbitBTC = fetchUpbit15MinuteSeries(market: "KRW-BTC")
        async let upbitUSDT = fetchUpbit15MinuteSeries(market: "KRW-USDT")

        let (binanceSeries, upbitBTCSeries, upbitUSDTSeries) = try await (binance, upbitBTC, upbitUSDT)

        let binanceValues = binanceSeries.keys.sorted().compactMap { binanceSeries[$0] }
        let upbitValues = upbitBTCSeries.keys.sorted().compactMap { upbitBTCSeries[$0] }

        let commonBuckets = Set(binanceSeries.keys)
            .intersection(upbitBTCSeries.keys)
            .intersection(upbitUSDTSeries.keys)
            .sorted()

        let premiumValues = commonBuckets.compactMap { bucket -> Double? in
            guard let btcUSDT = binanceSeries[bucket],
                  let btcKRW = upbitBTCSeries[bucket],
                  let usdtKRW = upbitUSDTSeries[bucket],
                  btcUSDT > 0,
                  usdtKRW > 0 else { return nil }
            return ((btcKRW / (btcUSDT * usdtKRW)) - 1.0) * 100.0
        }

        return HistoricalSeries(
            binanceBTCUSDT: Array(binanceValues.suffix(97)),
            upbitBTCKRW: Array(upbitValues.suffix(97)),
            premium: Array(premiumValues.suffix(97))
        )
    }

    func fetchReference24HoursAgo() async throws -> Reference24h {
        let target = Date().addingTimeInterval(-86_400)

        async let binance = fetchBinancePrice(at: target)
        async let upbitBTC = fetchUpbitPrice(market: "KRW-BTC", at: target)
        async let upbitUSDT = fetchUpbitPrice(market: "KRW-USDT", at: target)

        let (binancePrice, upbitBTCPrice, upbitUSDTPrice) = try await (binance, upbitBTC, upbitUSDT)
        return Reference24h(
            binanceBTCUSDT: binancePrice,
            upbitBTCKRW: upbitBTCPrice,
            upbitUSDTKRW: upbitUSDTPrice
        )
    }

    private func fetchBinance15MinuteSeries() async throws -> [Int64: Double] {
        var components = URLComponents(string: "https://api.binance.com/api/v3/klines")!
        components.queryItems = [
            URLQueryItem(name: "symbol", value: "BTCUSDT"),
            URLQueryItem(name: "interval", value: "15m"),
            URLQueryItem(name: "limit", value: "97")
        ]

        let (data, response) = try await session.data(from: components.url!)
        try validate(response)

        guard let rows = try JSONSerialization.jsonObject(with: data) as? [[Any]] else {
            throw MarketDataError.invalidResponse
        }

        var result: [Int64: Double] = [:]
        for row in rows where row.count > 4 {
            guard let openNumber = row[0] as? NSNumber,
                  let closeText = row[4] as? String,
                  let close = Double(closeText) else { continue }
            let bucket = (openNumber.int64Value / 1000 / 900) * 900
            result[bucket] = close
        }
        return result
    }

    private func fetchUpbit15MinuteSeries(market: String) async throws -> [Int64: Double] {
        var components = URLComponents(string: "https://api.upbit.com/v1/candles/minutes/15")!
        components.queryItems = [
            URLQueryItem(name: "market", value: market),
            URLQueryItem(name: "count", value: "97")
        ]

        let (data, response) = try await session.data(from: components.url!)
        try validate(response)

        let candles = try JSONDecoder().decode([UpbitSeriesCandle].self, from: data)
        var result: [Int64: Double] = [:]
        for candle in candles {
            guard let date = Formatters.upbitUTC.date(from: candle.candleDateTimeUTC) else { continue }
            let bucket = (Int64(date.timeIntervalSince1970) / 900) * 900
            result[bucket] = candle.tradePrice
        }
        return result
    }

    private func fetchBinancePrice(at date: Date) async throws -> Double {
        let minuteStart = floor(date.timeIntervalSince1970 / 60.0) * 60.0
        let startMs = Int64(minuteStart * 1000.0)
        let endMs = startMs + 59_999

        var components = URLComponents(string: "https://api.binance.com/api/v3/klines")!
        components.queryItems = [
            URLQueryItem(name: "symbol", value: "BTCUSDT"),
            URLQueryItem(name: "interval", value: "1m"),
            URLQueryItem(name: "startTime", value: String(startMs)),
            URLQueryItem(name: "endTime", value: String(endMs)),
            URLQueryItem(name: "limit", value: "1")
        ]

        let (data, response) = try await session.data(from: components.url!)
        try validate(response)

        guard let rows = try JSONSerialization.jsonObject(with: data) as? [[Any]],
              let row = rows.first,
              row.count > 4,
              let closeText = row[4] as? String,
              let close = Double(closeText) else {
            throw MarketDataError.invalidResponse
        }

        return close
    }

    private func fetchUpbitPrice(market: String, at date: Date) async throws -> Double {
        let minuteStart = floor(date.timeIntervalSince1970 / 60.0) * 60.0
        let exclusiveEnd = Date(timeIntervalSince1970: minuteStart + 60.0)

        var components = URLComponents(string: "https://api.upbit.com/v1/candles/minutes/1")!
        components.queryItems = [
            URLQueryItem(name: "market", value: market),
            URLQueryItem(name: "to", value: iso8601(exclusiveEnd)),
            URLQueryItem(name: "count", value: "1")
        ]

        let (data, response) = try await session.data(from: components.url!)
        try validate(response)

        guard let candle = try JSONDecoder().decode([UpbitMinuteCandle].self, from: data).first else {
            throw MarketDataError.invalidResponse
        }

        return candle.tradePrice
    }

    private func validate(_ response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse,
              (200..<300).contains(http.statusCode) else {
            throw MarketDataError.httpError
        }
    }
}

enum MarketDataError: Error {
    case invalidResponse
    case httpError
}

struct BinanceTicker: Decodable {
    let c: String
    let P: String
}

struct UpbitSimpleTicker: Decodable {
    let code: String?
    let tradePrice: Double?

    enum CodingKeys: String, CodingKey {
        case code = "cd"
        case tradePrice = "tp"
    }
}

struct UpbitMinuteCandle: Decodable {
    let tradePrice: Double

    enum CodingKeys: String, CodingKey {
        case tradePrice = "trade_price"
    }
}

struct UpbitSeriesCandle: Decodable {
    let candleDateTimeUTC: String
    let tradePrice: Double

    enum CodingKeys: String, CodingKey {
        case candleDateTimeUTC = "candle_date_time_utc"
        case tradePrice = "trade_price"
    }
}

