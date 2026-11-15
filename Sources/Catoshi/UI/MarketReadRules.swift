import Foundation

enum MarketReadRules {
    static func leadership(btc: MarketTrend, total3: MarketTrend, eth: MarketTrend, language: AppLanguage) -> MarketReadDimension {
        let pick = language.pick
        let signal: String
        if btc == .up { signal = pick("BTC 상대 우위", "BTC relative leadership") }
        else if btc == .down && total3 == .up { signal = pick("BTC 외 시총 확대", "Ex-BTC cap expansion") }
        else if eth == .up { signal = pick("ETH 상대강세", "ETH relative strength") }
        else { signal = pick("주도권 미확정", "Leadership unconfirmed") }
        return MarketReadDimension(id: "lead", label: pick("주도권", "Leadership"), signal: signal,
            explanation: pick("BTC.D \(btc.rawValue) · TOTAL3* \(total3.rawValue) · ETH/BTC \(eth.rawValue). 비중·합계 시총·상대 가격의 변화입니다. 개별 종목 상승 수나 실제 자금 이동을 측정하지 않습니다.", "BTC.D \(btc.rawValue) · TOTAL3* \(total3.rawValue) · ETH/BTC \(eth.rawValue). These measure share, aggregate cap and relative price, not advancing-coin counts or capital transfers."))
    }

    static func leverage(oi: Double?, funding: Double?, language: AppLanguage) -> MarketReadDimension {
        let pick = language.pick
        var facts: [String] = []
        if let oi { facts.append(String(format: "OI quantity 1h %+.2f%%", oi)) }
        if let funding { facts.append(String(format: "Funding %+.3f%%", funding)) }
        let biased = funding.map { abs($0) >= 0.05 } ?? false
        let signal: String
        if biased {
            signal = (oi.map { $0 <= -3 } ?? false) ? pick("수량 감소·펀딩 편향 지속", "OI falling, funding biased") : pick("펀딩 편향 주의", "Funding bias")
        } else if let oi {
            signal = oi >= 3 ? pick("OI 수량 증가", "OI quantity rising") : oi <= -3 ? pick("OI 수량 감소", "OI quantity falling") : pick("수량 변화 제한", "Limited quantity change")
        } else { signal = pick("OI 미확인", "OI unavailable") }
        if oi == nil { facts.append(pick("OI 미수신·제외", "OI unavailable / excluded")) }
        if funding == nil { facts.append(pick("Funding 미수신·제외", "Funding unavailable / excluded")) }
        return MarketReadDimension(id: "lev", label: pick("레버리지", "Leverage"), signal: signal,
            explanation: facts.joined(separator: " · ") + pick(". Binance BTCUSDT 기준입니다. 수량 감소만으로 펀딩 위험 해소나 청산 발생을 확정하지 않습니다.", ". Binance BTCUSDT only. Falling quantity does not prove funding risk has cleared or liquidations occurred."))
    }

    static func price(day: Double?, short: Double?, language: AppLanguage) -> MarketReadDimension {
        let pick = language.pick
        guard let day else { return MarketReadDimension(id: "price", label: pick("가격", "Price"), signal: pick("데이터 부족", "No data"), explanation: pick("BTC 가격 데이터를 기다립니다.", "Waiting for BTC price data.")) }
        let daily = metricTrend(day, threshold: 0.5)
        let brief = metricTrend(short, threshold: 0.1)
        let signal: String
        switch (daily, brief) {
        case (.up, .up): signal = pick("상승 동행", "Both rising")
        case (.down, .down): signal = pick("하락 동행", "Both falling")
        case (.up, .down): signal = pick("24h 상승·단기 하락", "24h up, short-term down")
        case (.down, .up): signal = pick("24h 하락·단기 반등", "24h down, short-term bounce")
        case (.up, _): signal = pick("24h 상승", "24h rising")
        case (.down, _): signal = pick("24h 하락", "24h falling")
        default: signal = pick("24h 변화 제한", "Limited 24h change")
        }
        return MarketReadDimension(id: "price", label: pick("가격", "Price"), signal: signal,
            explanation: String(format: "BTC 24h %+.2f%%", day) + (short.map { String(format: " · 5m %+.2f%%", $0) } ?? pick(" · 5m 미확인", " · 5m unavailable")) + pick(". 24h ±0.5%, 5m ±0.1% 이내는 중립 범위이며 서로 다른 관측 기간입니다.", ". Neutral bands are ±0.5% over 24h and ±0.1% over 5m; these are different observation periods."))
    }
}
