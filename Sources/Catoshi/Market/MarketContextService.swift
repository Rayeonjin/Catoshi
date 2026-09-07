import Foundation

final class MarketContextService {
    private let session: URLSession

    init() {
        session = URLSession(configuration: CatoshiNetworkRuntime.ephemeralConfiguration(
            requestTimeout: 12,
            resourceTimeout: 35
        ))
    }

    func fetchDomesticExchangeVolumes() async throws -> DomesticVolumeSnapshot {
        async let upbit = fetchUpbitResult()
        async let bithumb = fetchBithumbResult()
        async let coinone = fetchCoinoneResult()
        async let korbit = fetchKorbitResult()
        async let gopax = fetchGopaxResult()

        let values = await (upbit, bithumb, coinone, korbit, gopax)
        let results = [values.0, values.1, values.2, values.3, values.4]

        let entries = results.compactMap { result -> DomesticExchangeVolume? in
            guard let value = result.volume, value.isFinite, value >= 0 else { return nil }
            return DomesticExchangeVolume(exchange: result.exchange, krw24h: value)
        }
        let availability = results.map {
            DomesticExchangeAvailability(exchange: $0.exchange, state: $0.state)
        }

        return DomesticVolumeSnapshot(
            entries: entries,
            availability: availability,
            updatedAt: Date(),
            isPartial: entries.count != DomesticExchange.allCases.count
        )
    }

    func fetchMacroMarket() async throws -> MacroMarketSnapshot {
        async let globalRequest = fetchCoinGeckoGlobal()
        async let coinMarketsRequest: [CoinGeckoCoinMarket]? = try? fetchCoinGeckoCoreMarkets()

        let global = try await globalRequest
        let coinMarkets = await coinMarketsRequest

        guard let totalCurrent = global.data.totalMarketCap["usd"], totalCurrent > 0 else {
            throw MarketContextError.invalidResponse
        }

        let btcCurrent = totalCurrent * global.data.marketCapPercentage.btc / 100
        let ethCurrent = totalCurrent * global.data.marketCapPercentage.eth / 100
        let total3Current = max(0, totalCurrent - btcCurrent - ethCurrent)

        var btcChangePP: Double?
        var usdtChangePP: Double?
        var total3Change: Double?

        if let coinMarkets,
           let btc = coinMarkets.first(where: { $0.id == "bitcoin" }),
           let eth = coinMarkets.first(where: { $0.id == "ethereum" }),
           let usdt = coinMarkets.first(where: { $0.id == "tether" }),
           let btcCap = btc.marketCap,
           let ethCap = eth.marketCap,
           let usdtCap = usdt.marketCap,
           let btcCapChange = btc.marketCapChange24h,
           let ethCapChange = eth.marketCapChange24h,
           let usdtCapChange = usdt.marketCapChange24h {

            let totalFactor = 1 + global.data.marketCapChangePercentage24hUsd / 100
            if abs(totalFactor) > 0.000_001 {
                let totalPrevious = totalCurrent / totalFactor
                let btcPrevious = btcCap - btcCapChange
                let ethPrevious = ethCap - ethCapChange
                let usdtPrevious = usdtCap - usdtCapChange

                if totalPrevious > 0, btcPrevious >= 0, ethPrevious >= 0, usdtPrevious >= 0 {
                    let previousBTCDominance = btcPrevious / totalPrevious * 100
                    let previousUSDTDominance = usdtPrevious / totalPrevious * 100
                    btcChangePP = global.data.marketCapPercentage.btc - previousBTCDominance
                    usdtChangePP = global.data.marketCapPercentage.usdt - previousUSDTDominance

                    let total3Previous = totalPrevious - btcPrevious - ethPrevious
                    if total3Previous > 0 {
                        total3Change = (total3Current / total3Previous - 1) * 100
                    }
                }
            }
        }

        return MacroMarketSnapshot(
            btcDominance: global.data.marketCapPercentage.btc,
            btcDominanceChange24hPP: btcChangePP,
            usdtDominance: global.data.marketCapPercentage.usdt,
            usdtDominanceChange24hPP: usdtChangePP,
            total3USD: total3Current,
            total3Change24h: total3Change,
            updatedAt: Date(timeIntervalSince1970: TimeInterval(global.data.updatedAt))
        )
    }

    func fetchFastMarket() async throws -> FastMarketSnapshot {
        async let ethBTCTask = fetchETHBTCTicker()
        async let oiTask: OpenInterestSummary? = try? fetchOpenInterestSummary()
        async let fundingTask: Double? = try? fetchFundingRatePercent()

        let ethTicker = try await ethBTCTask
        let oi = await oiTask
        let funding = await fundingTask

        return FastMarketSnapshot(
            ethBTC: ethTicker.lastPrice,
            ethBTCChange24h: ethTicker.priceChangePercent,
            openInterestUSD: oi?.currentUSD,
            openInterestChange1h: oi?.change1h,
            fundingRatePercent: funding,
            updatedAt: Date()
        )
    }

    func fetchInvestorMarket() async throws -> InvestorMarketSnapshot {
        async let stableTask: StablecoinSupplySummary? = try? fetchStablecoinSupplySummary()
        async let etfTask: ETFFlowSummary? = try? fetchFarsideETFFlowSummary()
        async let trendTask: BitcoinTrendSummary? = try? fetchBitcoinTrendSummary()

        let stable = await stableTask
        let etf = await etfTask
        let trend = await trendTask

        guard stable != nil || etf != nil || trend != nil else {
            throw MarketContextError.noData
        }

        return InvestorMarketSnapshot(
            stablecoinSupplyUSD: stable?.currentUSD,
            stablecoinSupplyChange7d: stable?.change7d,
            etfLatestFlowUSD: etf?.latestUSD,
            etfFiveDayFlowUSD: etf?.fiveDayUSD,
            etfFlowDate: etf?.date,
            btcReturn7d: trend?.return7d,
            btcReturn30d: trend?.return30d,
            btc200DMA: trend?.ma200,
            btcAbove200DMA: trend?.above200DMA,
            updatedAt: Date()
        )
    }

    private func fetchStablecoinSupplySummary() async throws -> StablecoinSupplySummary {
        let url = URL(string: "https://stablecoins.llama.fi/stablecoins?includePrices=false")!
        let (data, response) = try await session.data(from: url)
        try validate(response)

        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let assets = root["peggedAssets"] as? [[String: Any]] else {
            throw MarketContextError.invalidResponse
        }

        var current = 0.0
        var previousWeek = 0.0
        var found: Set<String> = []

        for asset in assets {
            guard let symbol = (asset["symbol"] as? String)?.uppercased(),
                  symbol == "USDT" || symbol == "USDC" else { continue }
            guard let circulating = asset["circulating"] as? [String: Any],
                  let prev = asset["circulatingPrevWeek"] as? [String: Any],
                  let currentValue = numericValue(circulating["peggedUSD"]),
                  let previousValue = numericValue(prev["peggedUSD"]) else { continue }
            current += currentValue
            previousWeek += previousValue
            found.insert(symbol)
        }

        guard found.contains("USDT"), found.contains("USDC"), previousWeek > 0 else {
            throw MarketContextError.invalidResponse
        }

        return StablecoinSupplySummary(
            currentUSD: current,
            change7d: (current / previousWeek - 1) * 100
        )
    }

    private func fetchBitcoinTrendSummary() async throws -> BitcoinTrendSummary {
        let urls = [
            URL(string: "https://api.binance.com/api/v3/klines?symbol=BTCUSDT&interval=1d&limit=201")!,
            URL(string: "https://data-api.binance.vision/api/v3/klines?symbol=BTCUSDT&interval=1d&limit=201")!
        ]

        var lastError: Error = MarketContextError.noData
        for url in urls {
            do {
                let (data, response) = try await session.data(from: url)
                try validate(response)
                guard let rows = try JSONSerialization.jsonObject(with: data) as? [[Any]] else {
                    throw MarketContextError.invalidResponse
                }
                let closes = rows.compactMap { row -> Double? in
                    guard row.count > 4 else { return nil }
                    return numericValue(row[4])
                }
                guard closes.count >= 200,
                      let latest = closes.last, latest > 0 else {
                    throw MarketContextError.invalidResponse
                }

                let sevenBase = closes[closes.count - min(8, closes.count)]
                let thirtyBase = closes[closes.count - min(31, closes.count)]
                guard sevenBase > 0, thirtyBase > 0 else { throw MarketContextError.invalidResponse }
                let maWindow = closes.suffix(200)
                let ma200 = maWindow.reduce(0, +) / Double(maWindow.count)

                return BitcoinTrendSummary(
                    return7d: (latest / sevenBase - 1) * 100,
                    return30d: (latest / thirtyBase - 1) * 100,
                    ma200: ma200,
                    above200DMA: latest >= ma200
                )
            } catch {
                lastError = error
            }
        }
        throw lastError
    }

    private func fetchFarsideETFFlowSummary() async throws -> ETFFlowSummary {
        let url = URL(string: "https://farside.co.uk/btc/")!
        var request = URLRequest(url: url)
        request.setValue("Mozilla/5.0 (Macintosh; Catoshi/\(AppMetadata.version))", forHTTPHeaderField: "User-Agent")
        request.setValue("text/html,application/xhtml+xml", forHTTPHeaderField: "Accept")
        let (data, response) = try await session.data(for: request)
        try validate(response)

        guard let html = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) else {
            throw MarketContextError.invalidResponse
        }

        let rows = extractHTMLRows(html)
        var points: [(date: Date, totalUSD: Double)] = []
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "dd MMM yyyy"

        for cells in rows {
            guard cells.count >= 3 else { continue }
            let dateText = cells[0].trimmingCharacters(in: .whitespacesAndNewlines)
            guard let date = formatter.date(from: dateText) else { continue }
            let fundCells = cells.dropFirst().dropLast()
            let numericFundCount = fundCells.compactMap(parseFarsideMillions).count
            guard let totalMillions = parseFarsideMillions(cells.last ?? "") else { continue }
            // Ignore placeholder rows where every fund is still '-' and Total is mechanically 0.0.
            if numericFundCount == 0 && abs(totalMillions) < 0.000_001 { continue }
            points.append((date, totalMillions * 1_000_000))
        }

        points.sort { $0.date < $1.date }
        guard let latest = points.last else { throw MarketContextError.noData }
        let fiveDay = points.suffix(5).reduce(0.0) { $0 + $1.totalUSD }
        return ETFFlowSummary(latestUSD: latest.totalUSD, fiveDayUSD: fiveDay, date: latest.date)
    }

    private func extractHTMLRows(_ html: String) -> [[String]] {
        let options: NSRegularExpression.Options = [.caseInsensitive, .dotMatchesLineSeparators]
        guard let rowRegex = try? NSRegularExpression(pattern: "<tr[^>]*>(.*?)</tr>", options: options),
              let cellRegex = try? NSRegularExpression(pattern: "<t[dh][^>]*>(.*?)</t[dh]>", options: options),
              let tagRegex = try? NSRegularExpression(pattern: "<[^>]+>", options: options) else { return [] }
        let ns = html as NSString
        return rowRegex.matches(in: html, range: NSRange(location: 0, length: ns.length)).map { rowMatch in
            let innerRange = rowMatch.range(at: 1)
            let inner = ns.substring(with: innerRange)
            let innerNS = inner as NSString
            return cellRegex.matches(in: inner, range: NSRange(location: 0, length: innerNS.length)).map { cellMatch in
                let raw = innerNS.substring(with: cellMatch.range(at: 1))
                let rawNS = raw as NSString
                let stripped = tagRegex.stringByReplacingMatches(in: raw, range: NSRange(location: 0, length: rawNS.length), withTemplate: " ")
                return decodeBasicHTMLEntities(stripped)
                    .replacingOccurrences(of: "\u{00a0}", with: " ")
                    .replacingOccurrences(of: "\n", with: " ")
                    .split(whereSeparator: { $0.isWhitespace })
                    .joined(separator: " ")
            }
        }
    }

    private func decodeBasicHTMLEntities(_ text: String) -> String {
        text.replacingOccurrences(of: "&nbsp;", with: " ")
            .replacingOccurrences(of: "&#160;", with: " ")
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&minus;", with: "-")
            .replacingOccurrences(of: "&ndash;", with: "-")
            .replacingOccurrences(of: "&#8211;", with: "-")
    }

    private func parseFarsideMillions(_ text: String) -> Double? {
        var cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: ",", with: "")
            .replacingOccurrences(of: "−", with: "-")
        if cleaned.isEmpty || cleaned == "-" { return nil }
        var negative = false
        if cleaned.hasPrefix("(") && cleaned.hasSuffix(")") {
            negative = true
            cleaned.removeFirst()
            cleaned.removeLast()
        }
        guard let value = Double(cleaned) else { return nil }
        return negative ? -value : value
    }

    private func numericValue(_ value: Any?) -> Double? {
        switch value {
        case let number as NSNumber: return number.doubleValue
        case let string as String: return Double(string)
        case let double as Double: return double
        case let int as Int: return Double(int)
        case let int64 as Int64: return Double(int64)
        default: return nil
        }
    }

    private func fetchCoinGeckoGlobal() async throws -> CoinGeckoGlobalResponse {
        let url = URL(string: "https://api.coingecko.com/api/v3/global")!
        let (data, response) = try await session.data(from: url)
        try validate(response)
        return try JSONDecoder().decode(CoinGeckoGlobalResponse.self, from: data)
    }

    private func fetchCoinGeckoCoreMarkets() async throws -> [CoinGeckoCoinMarket] {
        var components = URLComponents(string: "https://api.coingecko.com/api/v3/coins/markets")!
        components.queryItems = [
            URLQueryItem(name: "vs_currency", value: "usd"),
            URLQueryItem(name: "ids", value: "bitcoin,ethereum,tether"),
            URLQueryItem(name: "sparkline", value: "false")
        ]
        let (data, response) = try await session.data(from: components.url!)
        try validate(response)
        return try JSONDecoder().decode([CoinGeckoCoinMarket].self, from: data)
    }

    private func fetchETHBTCTicker() async throws -> BinanceSpot24hTicker {
        let urls = [
            URL(string: "https://api.binance.com/api/v3/ticker/24hr?symbol=ETHBTC")!,
            URL(string: "https://data-api.binance.vision/api/v3/ticker/24hr?symbol=ETHBTC")!
        ]

        var lastError: Error = MarketContextError.noData
        for url in urls {
            do {
                let (data, response) = try await session.data(from: url)
                try validate(response)
                return try JSONDecoder().decode(BinanceSpot24hTicker.self, from: data)
            } catch {
                lastError = error
            }
        }
        throw lastError
    }

    private func fetchOpenInterestSummary() async throws -> OpenInterestSummary {
        var components = URLComponents(string: "https://fapi.binance.com/futures/data/openInterestHist")!
        components.queryItems = [
            URLQueryItem(name: "symbol", value: "BTCUSDT"),
            URLQueryItem(name: "period", value: "1h"),
            URLQueryItem(name: "limit", value: "2")
        ]
        let (data, response) = try await session.data(from: components.url!)
        try validate(response)
        let rows = try JSONDecoder().decode([BinanceOpenInterestPoint].self, from: data)
            .sorted { $0.timestamp < $1.timestamp }
        guard let latest = rows.last,
              let current = Double(latest.sumOpenInterestValue) else {
            throw MarketContextError.invalidResponse
        }

        var change: Double?
        if rows.count >= 2,
           let previous = Double(rows[rows.count - 2].sumOpenInterestValue),
           previous > 0 {
            change = (current / previous - 1) * 100
        }

        return OpenInterestSummary(currentUSD: current, change1h: change)
    }

    private func fetchFundingRatePercent() async throws -> Double {
        var components = URLComponents(string: "https://fapi.binance.com/fapi/v1/premiumIndex")!
        components.queryItems = [URLQueryItem(name: "symbol", value: "BTCUSDT")]
        let (data, response) = try await session.data(from: components.url!)
        try validate(response)
        let payload = try JSONDecoder().decode(BinancePremiumIndex.self, from: data)
        guard let rate = Double(payload.lastFundingRate) else { throw MarketContextError.invalidResponse }
        return rate * 100
    }

    private func fetchUpbitResult() async -> DomesticExchangeFetchResult {
        do {
            return DomesticExchangeFetchResult(exchange: .upbit, volume: try await fetchUpbitVolume(), state: .available)
        } catch {
            return DomesticExchangeFetchResult(exchange: .upbit, volume: nil, state: dataState(for: error))
        }
    }

    private func fetchBithumbResult() async -> DomesticExchangeFetchResult {
        do {
            return DomesticExchangeFetchResult(exchange: .bithumb, volume: try await fetchBithumbVolume(), state: .available)
        } catch {
            return DomesticExchangeFetchResult(exchange: .bithumb, volume: nil, state: dataState(for: error))
        }
    }

    private func fetchCoinoneResult() async -> DomesticExchangeFetchResult {
        do {
            return DomesticExchangeFetchResult(exchange: .coinone, volume: try await fetchCoinoneVolume(), state: .available)
        } catch {
            if dataState(for: error) == .maintenance {
                return DomesticExchangeFetchResult(exchange: .coinone, volume: nil, state: .maintenance)
            }

            // Coinone uniquely exposes an explicit public maintenance_status field.
            // Probe it only after the normal aggregate ticker request has failed, so
            // healthy operation adds zero maintenance-polling traffic.
            if shouldProbeCoinoneMaintenance(after: error),
               (try? await fetchCoinoneExchangeMaintenance()) == true {
                return DomesticExchangeFetchResult(exchange: .coinone, volume: nil, state: .maintenance)
            }
            return DomesticExchangeFetchResult(exchange: .coinone, volume: nil, state: .unavailable)
        }
    }

    private func fetchKorbitResult() async -> DomesticExchangeFetchResult {
        do {
            return DomesticExchangeFetchResult(exchange: .korbit, volume: try await fetchKorbitVolume(), state: .available)
        } catch {
            return DomesticExchangeFetchResult(exchange: .korbit, volume: nil, state: dataState(for: error))
        }
    }

    private func fetchGopaxResult() async -> DomesticExchangeFetchResult {
        do {
            return DomesticExchangeFetchResult(exchange: .gopax, volume: try await fetchGopaxVolume(), state: .available)
        } catch {
            return DomesticExchangeFetchResult(exchange: .gopax, volume: nil, state: dataState(for: error))
        }
    }

    private func dataState(for error: Error) -> DomesticExchangeDataState {
        if let contextError = error as? MarketContextError, case .maintenance = contextError {
            return .maintenance
        }
        return .unavailable
    }

    private func shouldProbeCoinoneMaintenance(after error: Error) -> Bool {
        guard let contextError = error as? MarketContextError else { return false }
        switch contextError {
        case .invalidResponse, .httpError:
            return true
        case .maintenance, .noData:
            return false
        }
    }

    private func fetchUpbitVolume() async throws -> Double {
        var components = URLComponents(string: "https://api.upbit.com/v1/ticker/all")!
        components.queryItems = [URLQueryItem(name: "quote_currencies", value: "KRW")]
        let (data, response) = try await session.data(from: components.url!)
        try validateDomestic(response, data: data)
        let rows = try JSONDecoder().decode([UpbitAllTicker].self, from: data)
        return rows.reduce(0) { $0 + $1.accTradePrice24h }
    }

    private func fetchBithumbVolume() async throws -> Double {
        let url = URL(string: "https://api.bithumb.com/public/ticker/ALL_KRW")!
        let (data, response) = try await session.data(from: url)
        try validateDomestic(response, data: data)

        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            if responseIndicatesMaintenance(data) { throw MarketContextError.maintenance }
            throw MarketContextError.invalidResponse
        }
        guard root["status"] as? String == "0000",
              let items = root["data"] as? [String: Any] else {
            if responseIndicatesMaintenance(data) { throw MarketContextError.maintenance }
            throw MarketContextError.invalidResponse
        }

        var total = 0.0
        for value in items.values {
            guard let ticker = value as? [String: Any] else { continue }
            if let text = ticker["acc_trade_value_24H"] as? String,
               let amount = Double(text) {
                total += amount
            } else if let number = ticker["acc_trade_value_24H"] as? NSNumber {
                total += number.doubleValue
            }
        }
        return total
    }

    private func fetchCoinoneVolume() async throws -> Double {
        let url = URL(string: "https://api.coinone.co.kr/public/v2/ticker_new/KRW")!
        let (data, response) = try await session.data(from: url)
        try validateDomestic(response, data: data)
        if responseIndicatesMaintenance(data) { throw MarketContextError.maintenance }
        let payload = try JSONDecoder().decode(CoinoneTickerResponse.self, from: data)
        guard payload.result.lowercased() == "success", let tickers = payload.tickers else {
            throw MarketContextError.invalidResponse
        }
        return tickers.reduce(0) { $0 + (Double($1.quoteVolume) ?? 0) }
    }

    private func fetchCoinoneExchangeMaintenance() async throws -> Bool {
        let url = URL(string: "https://api.coinone.co.kr/public/v2/markets/KRW")!
        let (data, response) = try await session.data(from: url)
        try validateDomestic(response, data: data)
        let payload = try JSONDecoder().decode(CoinoneMarketsResponse.self, from: data)
        guard payload.result.lowercased() == "success", !payload.markets.isEmpty else {
            throw MarketContextError.invalidResponse
        }
        return payload.markets.allSatisfy { $0.maintenanceStatus == 1 }
    }

    private func fetchKorbitVolume() async throws -> Double {
        let url = URL(string: "https://api.korbit.co.kr/v2/tickers")!
        let (data, response) = try await session.data(from: url)
        try validateDomestic(response, data: data)
        if responseIndicatesMaintenance(data) { throw MarketContextError.maintenance }
        let payload = try JSONDecoder().decode(KorbitTickerEnvelope.self, from: data)
        guard payload.success else {
            throw MarketContextError.invalidResponse
        }
        return payload.data.reduce(0) { partial, ticker in
            guard ticker.symbol.lowercased().hasSuffix("_krw") else { return partial }
            return partial + (Double(ticker.quoteVolume) ?? 0)
        }
    }

    private func fetchGopaxVolume() async throws -> Double {
        let url = URL(string: "https://api.gopax.co.kr/tickers")!
        let (data, response) = try await session.data(from: url)
        try validateDomestic(response, data: data)
        do {
            let tickers = try JSONDecoder().decode([GopaxTicker].self, from: data)
            return tickers.reduce(0) { partial, ticker in
                guard ticker.tradingPairName.uppercased().hasSuffix("-KRW") else { return partial }
                return partial + ticker.quoteVolume
            }
        } catch {
            if responseIndicatesMaintenance(data) { throw MarketContextError.maintenance }
            throw error
        }
    }

    private func validateDomestic(_ response: URLResponse, data: Data) throws {
        guard let http = response as? HTTPURLResponse,
              (200..<300).contains(http.statusCode) else {
            if responseIndicatesMaintenance(data) { throw MarketContextError.maintenance }
            throw MarketContextError.httpError
        }
    }

    private func responseIndicatesMaintenance(_ data: Data) -> Bool {
        guard let text = String(data: data, encoding: .utf8)?.lowercased() else { return false }
        return text.contains("maintenance") || text.contains("점검")
    }

    private func validate(_ response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse,
              (200..<300).contains(http.statusCode) else {
            throw MarketContextError.httpError
        }
    }
}

private enum MarketContextError: Error {
    case noData
    case invalidResponse
    case httpError
    case maintenance
}

private struct DomesticExchangeFetchResult {
    let exchange: DomesticExchange
    let volume: Double?
    let state: DomesticExchangeDataState
}

private struct StablecoinSupplySummary {
    let currentUSD: Double
    let change7d: Double
}

private struct ETFFlowSummary {
    let latestUSD: Double
    let fiveDayUSD: Double
    let date: Date
}

private struct BitcoinTrendSummary {
    let return7d: Double
    let return30d: Double
    let ma200: Double
    let above200DMA: Bool
}

private struct OpenInterestSummary {
    let currentUSD: Double
    let change1h: Double?
}

private struct UpbitAllTicker: Decodable {
    let accTradePrice24h: Double

    enum CodingKeys: String, CodingKey {
        case accTradePrice24h = "acc_trade_price_24h"
    }
}

private struct CoinoneTickerResponse: Decodable {
    let result: String
    let tickers: [CoinoneVolumeTicker]?
}

private struct CoinoneMarketsResponse: Decodable {
    let result: String
    let markets: [CoinoneMarketStatus]
}

private struct CoinoneMarketStatus: Decodable {
    let maintenanceStatus: Int

    enum CodingKeys: String, CodingKey {
        case maintenanceStatus = "maintenance_status"
    }
}

private struct CoinoneVolumeTicker: Decodable {
    let quoteVolume: String

    enum CodingKeys: String, CodingKey {
        case quoteVolume = "quote_volume"
    }
}

private struct KorbitTickerEnvelope: Decodable {
    let success: Bool
    let data: [KorbitVolumeTicker]
}

private struct KorbitVolumeTicker: Decodable {
    let symbol: String
    let quoteVolume: String
}

private struct GopaxTicker: Decodable {
    let quoteVolume: Double
    let tradingPairName: String
}

private struct CoinGeckoGlobalResponse: Decodable {
    let data: CoinGeckoGlobalData
}

private struct CoinGeckoGlobalData: Decodable {
    let totalMarketCap: [String: Double]
    let marketCapPercentage: CoinGeckoMarketCapPercentage
    let marketCapChangePercentage24hUsd: Double
    let updatedAt: Int

    enum CodingKeys: String, CodingKey {
        case totalMarketCap = "total_market_cap"
        case marketCapPercentage = "market_cap_percentage"
        case marketCapChangePercentage24hUsd = "market_cap_change_percentage_24h_usd"
        case updatedAt = "updated_at"
    }
}

private struct CoinGeckoMarketCapPercentage: Decodable {
    let btc: Double
    let eth: Double
    let usdt: Double
}

private struct CoinGeckoCoinMarket: Decodable {
    let id: String
    let marketCap: Double?
    let marketCapChange24h: Double?

    enum CodingKeys: String, CodingKey {
        case id
        case marketCap = "market_cap"
        case marketCapChange24h = "market_cap_change_24h"
    }
}

private struct BinanceSpot24hTicker: Decodable {
    let lastPriceText: String
    let priceChangePercentText: String

    var lastPrice: Double { Double(lastPriceText) ?? 0 }
    var priceChangePercent: Double { Double(priceChangePercentText) ?? 0 }

    enum CodingKeys: String, CodingKey {
        case lastPriceText = "lastPrice"
        case priceChangePercentText = "priceChangePercent"
    }
}

private struct BinanceOpenInterestPoint: Decodable {
    let sumOpenInterestValue: String
    let timestamp: Int64
}

private struct BinancePremiumIndex: Decodable {
    let lastFundingRate: String
}
