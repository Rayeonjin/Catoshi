import Foundation
import SwiftUI

func exchangeColor(_ exchange: DomesticExchange, palette: DisplayPalette, index: Int) -> Color {
    if palette == .monochrome {
        let opacity = max(0.34, 0.92 - Double(index) * 0.13)
        return Color.primary.opacity(opacity)
    }

    switch exchange {
    case .upbit: return .blue
    case .bithumb: return .orange
    case .coinone: return .purple
    case .korbit: return .teal
    case .gopax: return .yellow
    }
}

func formatKRWTradingValue(_ value: Double, language: AppLanguage) -> String {
    if language == .english {
        if value >= 1_000_000_000_000 { return String(format: "₩%.2fT", value / 1_000_000_000_000) }
        if value >= 1_000_000_000 { return String(format: "₩%.1fB", value / 1_000_000_000) }
        if value >= 1_000_000 { return String(format: "₩%.1fM", value / 1_000_000) }
        if value >= 1_000 { return String(format: "₩%.1fK", value / 1_000) }
        return String(format: "₩%.0f", value)
    }
    if value >= 1_000_000_000_000 { return String(format: "₩%.2f조", value / 1_000_000_000_000) }
    if value >= 100_000_000 { return String(format: "₩%.0f억", value / 100_000_000) }
    if value >= 10_000 { return String(format: "₩%.0f만", value / 10_000) }
    return String(format: "₩%.0f", value)
}

func formatUSDMarketCap(_ value: Double) -> String {
    let absolute = abs(value)
    if absolute >= 1_000_000_000_000 {
        return String(format: "$%.2fT", value / 1_000_000_000_000)
    }
    if absolute >= 1_000_000_000 {
        return String(format: "$%.1fB", value / 1_000_000_000)
    }
    if absolute >= 1_000_000 {
        return String(format: "$%.1fM", value / 1_000_000)
    }
    return String(format: "$%.0f", value)
}

func formatSignedUSDFlow(_ value: Double) -> String {
    let sign = value >= 0 ? "+" : "-"
    let absolute = abs(value)
    if absolute >= 1_000_000_000 {
        return String(format: "%@$%.2fB", sign, absolute / 1_000_000_000)
    }
    if absolute >= 1_000_000 {
        return String(format: "%@$%.0fM", sign, absolute / 1_000_000)
    }
    if absolute >= 1_000 {
        return String(format: "%@$%.0fK", sign, absolute / 1_000)
    }
    return String(format: "%@$%.0f", sign, absolute)
}

func formatBTCTrendValue(_ snapshot: InvestorMarketSnapshot?) -> String {
    guard let snapshot, let ret7 = snapshot.btcReturn7d else { return "--" }
    return String(format: "7D %+.1f%%", ret7)
}

func formatBTCTrendDetail(_ snapshot: InvestorMarketSnapshot?) -> String {
    guard let snapshot, let ret30 = snapshot.btcReturn30d else { return "30D / 200D" }
    let position: String
    if let above = snapshot.btcAbove200DMA {
        position = above ? ">200D" : "<200D"
    } else {
        position = "200D --"
    }
    return String(format: "30D %+.1f%% · %@", ret30, position)
}

func signedMetric(_ value: Double) -> String {
    String(format: "%+.2f", value)
}

func metricTrend(_ value: Double?, threshold: Double) -> MarketTrend {
    guard let value else { return .unknown }
    if value > threshold { return .up }
    if value < -threshold { return .down }
    return .flat
}


