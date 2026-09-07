import AppKit
import Foundation

enum FeedHealth: Equatable {
    case healthy
    case stale
    case disconnected

    var color: NSColor {
        switch self {
        case .healthy: return .systemGreen
        case .stale: return .systemOrange
        case .disconnected: return .systemRed
        }
    }

    func toolTip(_ language: AppLanguage) -> String {
        switch self {
        case .healthy: return language.pick("실시간 · Binance와 Upbit가 정상적으로 갱신 중", "Live · Binance and Upbit are updating normally")
        case .stale: return language.pick("지연 · 연결은 유지되지만 최근 시세가 들어오지 않음", "Delayed · connections are up, but fresh market data has not arrived recently")
        case .disconnected: return language.pick("연결 문제 · Binance 또는 Upbit 피드 연결 끊김", "Connection issue · Binance or Upbit feed is disconnected")
        }
    }
}

@MainActor
func feedHealth(model: MarketModel, now: Date = Date()) -> FeedHealth {
    guard model.networkAvailable else { return .disconnected }

    if model.binanceState == .disconnected || model.upbitState == .disconnected {
        return .disconnected
    }

    if model.binanceState == .connecting || model.upbitState == .connecting {
        return .stale
    }

    guard let binanceAt = model.binanceLastTickAt,
          let upbitAt = model.upbitLastTickAt else {
        return .stale
    }

    let newestRequiredFeed = min(binanceAt, upbitAt)
    return now.timeIntervalSince(newestRequiredFeed) <= CatoshiRuntimePolicy.healthDisplayStaleThreshold ? .healthy : .stale
}

enum Formatters {
    static let usd: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "USD"
        formatter.locale = Locale(identifier: "en_US")
        formatter.maximumFractionDigits = 2
        formatter.minimumFractionDigits = 2
        return formatter
    }()

    static let krw: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.locale = Locale(identifier: "ko_KR")
        formatter.maximumFractionDigits = 0
        return formatter
    }()

    static let clock: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter
    }()

    static let iso8601: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    static let upbitUTC: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        return formatter
    }()
}

func formatUSD(_ value: Double) -> String {
    Formatters.usd.string(from: NSNumber(value: value)) ?? "$--"
}

func formatKRW(_ value: Double) -> String {
    "₩" + (Formatters.krw.string(from: NSNumber(value: value)) ?? "--")
}

func formatUSDMenu(_ value: Double) -> String {
    if value >= 1_000 {
        return String(format: "$%.2fK", value / 1_000.0)
    }
    return String(format: "$%.2f", value)
}

func formatKRWMenu(_ value: Double, language: AppLanguage) -> String {
    if language == .english {
        if value >= 1_000_000_000 { return String(format: "₩%.2fB", value / 1_000_000_000) }
        if value >= 1_000_000 { return String(format: "₩%.2fM", value / 1_000_000) }
        if value >= 1_000 { return String(format: "₩%.1fK", value / 1_000) }
        return String(format: "₩%.0f", value)
    }

    let won = max(0, Int(value))
    if won >= 100_000_000 {
        let eok = won / 100_000_000
        let man = (won % 100_000_000) / 10_000
        if man > 0 { return "₩\(eok)억 \(formatInteger(man))만" }
        return "₩\(eok)억"
    }
    if won >= 10_000 { return "₩\(formatInteger(won / 10_000))만" }
    return "₩\(formatInteger(won))"
}

func formatInteger(_ value: Int) -> String {
    Formatters.krw.string(from: NSNumber(value: value)) ?? String(value)
}

func formatPercent(_ value: Double) -> String {
    String(format: "%+.2f%%", value)
}

func signedPercentWithArrow(_ value: Double) -> String {
    let arrow = value >= 0 ? "▲" : "▼"
    return "\(arrow) \(String(format: "%.2f%%", abs(value)))"
}

func menuBarChangeText(_ value: Double, suffix: String) -> String {
    let arrow = value >= 0 ? "▲" : "▼"
    return "\(arrow)\(String(format: "%.2f", abs(value)))\(suffix)"
}

func compactChange(_ value: Double) -> String {
    let arrow = value >= 0 ? "▲" : "▼"
    return "\(arrow)\(String(format: "%.2f%%", abs(value)))"
}

func compactPpChange(_ value: Double) -> String {
    let arrow = value >= 0 ? "▲" : "▼"
    return "\(arrow)\(String(format: "%.2f%%p", abs(value)))"
}

func formatPp(_ value: Double) -> String {
    String(format: "%.2f%%p", value)
}

func formatTime(_ date: Date) -> String {
    Formatters.clock.string(from: date)
}

func iso8601(_ date: Date) -> String {
    Formatters.iso8601.string(from: date)
}

func percentChange(current: Double, previous: Double) -> Double? {
    guard previous > 0 else { return nil }
    return ((current / previous) - 1.0) * 100.0
}
