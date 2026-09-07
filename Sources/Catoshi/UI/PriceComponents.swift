import AppKit
import Foundation
import SwiftUI

struct QuoteRow: View {
    let title: String
    let price: String
    let change: Double?
    let palette: DisplayPalette

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Text(title)
                .font(.system(size: CatoshiType.body, weight: .medium))
                .catoshiText(.secondary)
                .frame(width: 90, alignment: .leading)

            Text(price)
                .font(.system(size: CatoshiType.price, weight: .semibold, design: .default))
                .monospacedDigit()
                .lineLimit(1)
                .frame(width: 160, alignment: .leading)

            Spacer(minLength: 6)

            if let change {
                HStack(spacing: 5) {
                    Text("24h")
                        .font(.system(size: CatoshiType.metadata))
                        .catoshiText(.metadata)
                    ChangeBadge(value: change, palette: palette)
                }
            } else {
                Text("--")
                    .font(.system(size: CatoshiType.body, weight: .semibold))
                    .catoshiText(.secondary)
            }
        }
        .frame(minHeight: 34)
    }
}

struct PremiumRow: View {
    let premium: PremiumSnapshot?
    let palette: DisplayPalette
    let language: AppLanguage

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Text(language.pick("김치프리미엄", "Kimchi Premium"))
                .font(.system(size: CatoshiType.body, weight: .medium))
                .catoshiText(.secondary)
                .frame(width: 90, alignment: .leading)

            Text(premium.map { formatPercent($0.value) } ?? "--")
                .font(.system(size: CatoshiType.price, weight: .semibold, design: .default))
                .monospacedDigit()
                .frame(width: 160, alignment: .leading)

            Spacer(minLength: 6)

            if let delta = premium?.change24h {
                HStack(spacing: 5) {
                    Text("24h")
                        .font(.system(size: CatoshiType.metadata))
                        .catoshiText(.metadata)
                    DirectionBadge(value: delta, palette: palette)
                }
            } else {
                Text("--")
                    .font(.system(size: CatoshiType.body, weight: .semibold))
                    .catoshiText(.secondary)
            }
        }
        .frame(minHeight: 34)
    }
}

struct ChangeBadge: View {
    let value: Double
    let palette: DisplayPalette

    private var foregroundColor: Color {
        if palette == .monochrome { return .primary }
        return value >= 0 ? .green : .red
    }

    var body: some View {
        Text(signedPercentWithArrow(value))
            .font(.system(size: CatoshiType.badge, weight: .semibold, design: .default))
            .monospacedDigit()
            .foregroundStyle(foregroundColor)
    }
}

struct DirectionBadge: View {
    let value: Double
    let palette: DisplayPalette

    private var foregroundColor: Color {
        if palette == .monochrome { return .primary }
        return value >= 0 ? .green : .red
    }

    var body: some View {
        let arrow = value >= 0 ? "▲" : "▼"
        Text("\(arrow) \(formatPp(abs(value)))")
            .font(.system(size: CatoshiType.badge, weight: .semibold, design: .default))
            .monospacedDigit()
            .foregroundStyle(foregroundColor)
    }
}

struct ConnectionDot: View {
    let label: String
    let state: SocketConnectionState
    let palette: DisplayPalette
    let language: AppLanguage

    private var color: Color {
        guard palette == .color else { return state == .connected ? .primary : .secondary }
        switch state {
        case .connected: return .green
        case .connecting: return .orange
        case .disconnected: return .red
        }
    }

    var body: some View {
        HStack(spacing: 4) {
            Group {
                if palette == .monochrome && state == .disconnected {
                    Circle().stroke(color, lineWidth: 1.2)
                } else {
                    Circle().fill(color)
                }
            }
            .frame(width: 7, height: 7)

            Text(label)
                .font(.system(size: CatoshiType.metadata))
                .help("\(label): \(state.label(language))")
        }
    }
}

