import Foundation

enum ExchangeLinks {
    // Price rows refer to the BTC pairs shown in Catoshi.
    static let binanceBTC = URL(string: "https://www.binance.com/en/trade/BTC_USDT")!
    static let upbitBTC = URL(string: "https://www.upbit.com/exchange?code=CRIX.UPBIT.KRW-BTC")!

    // The domestic table aggregates all KRW markets, so its links open each venue.
    static func website(for exchange: DomesticExchange) -> URL {
        switch exchange {
        case .upbit: return URL(string: "https://www.upbit.com/")!
        case .bithumb: return URL(string: "https://www.bithumb.com/")!
        case .coinone: return URL(string: "https://coinone.co.kr/")!
        case .korbit: return URL(string: "https://digitalx.miraeasset.com/")!
        case .gopax: return URL(string: "https://www.gopax.co.kr/")!
        }
    }
}
