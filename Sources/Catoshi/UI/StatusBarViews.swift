import Combine
import SwiftUI

@MainActor
final class StatusBarHealthState: ObservableObject {
    @Published private(set) var health: FeedHealth = .stale

    func update(_ next: FeedHealth) {
        guard health != next else { return }
        health = next
    }
}

private struct StatusBarTerritoryWidthKey: SwiftUI.PreferenceKey {
    static var defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

private struct StatusBarCatoshiWaypointKey: SwiftUI.PreferenceKey {
    static var defaultValue: [CGFloat] = []

    static func reduce(value: inout [CGFloat], nextValue: () -> [CGFloat]) {
        value.append(contentsOf: nextValue())
    }
}

private struct StatusBarCatoshiWaypointMarker: View {
    var body: some View {
        GeometryReader { proxy in
            Color.clear.preference(
                key: StatusBarCatoshiWaypointKey.self,
                value: [proxy.frame(in: .named("CatoshiTerritory")).midX]
            )
        }
    }
}

@MainActor
struct StatusBarContentView: View {
    @ObservedObject var model: MarketModel
    let healthState: StatusBarHealthState

    private var hasAnyMarketSegment: Bool {
        model.showMenuBarBinance || model.showMenuBarUpbit || model.showMenuBarPremium
    }

    var body: some View {
        HStack(spacing: 9) {
            marketTerritory

            if hasAnyMarketSegment {
                StatusBarSeparator()
            }

            StatusHealthIndicatorLive(
                healthState: healthState,
                palette: model.displayPalette
            )
        }
        .padding(.horizontal, 2)
        .frame(height: NSStatusBar.system.thickness)
        .fixedSize(horizontal: true, vertical: true)
    }

    private var marketTerritory: some View {
        ZStack(alignment: .leading) {
            HStack(spacing: 9) {
                if model.showCatoshi {
                    // HOME lives immediately to the left of Binance. This fixed slot
                    // keeps every market value stationary while Catoshi follows short
                    // waypoint legs across the visible market territory as an overlay.
                    Color.clear
                        .frame(width: CatoshiMenuMascot.layoutWidth, height: 20)
                        .accessibilityHidden(true)

                    if hasAnyMarketSegment {
                        StatusBarSeparator(marksCatoshiWaypoint: true)
                    }
                }

                if model.showMenuBarBinance {
                    StatusBarSegment(
                        value: model.binanceBTC.map { formatUSDMenu($0.price) } ?? "$---",
                        change: model.binanceBTC?.change24h,
                        changeSuffix: "%",
                        showChange: model.showMenuBarBinance24h,
                        series: model.binanceSparkline,
                        showSparkline: model.showMenuBarBinanceSparkline,
                        palette: model.displayPalette
                    )
                    .equatable()
                }

                if model.showMenuBarBinance && (model.showMenuBarUpbit || model.showMenuBarPremium) {
                    StatusBarSeparator(marksCatoshiWaypoint: true)
                }

                if model.showMenuBarUpbit {
                    StatusBarSegment(
                        value: model.upbitBTC.map { formatKRWMenu($0.price, language: model.appLanguage) } ?? "₩---",
                        change: model.upbitBTC?.change24h,
                        changeSuffix: "%",
                        showChange: model.showMenuBarUpbit24h,
                        series: model.upbitSparkline,
                        showSparkline: model.showMenuBarUpbitSparkline,
                        palette: model.displayPalette
                    )
                    .equatable()
                }

                if model.showMenuBarUpbit && model.showMenuBarPremium {
                    StatusBarSeparator(marksCatoshiWaypoint: true)
                }

                if model.showMenuBarPremium {
                    StatusBarSegment(
                        value: model.premium.map { formatPercent($0.value) } ?? "--",
                        change: model.premium?.change24h,
                        changeSuffix: "%p",
                        showChange: model.showMenuBarPremium24h,
                        series: model.premiumSparkline,
                        showSparkline: model.showMenuBarPremiumSparkline,
                        palette: model.displayPalette
                    )
                    .equatable()
                }
            }

            if model.showCatoshi {
                CatoshiStatusOverlay(
                    motion: model.catoshiMotion,
                    coat: model.catoshiCoat,
                    animationEnabled: model.catoshiAnimationEnabled,
                    language: model.appLanguage,
                    fiveMinuteChange: model.fiveMinuteChange
                )
            }
        }
        .coordinateSpace(name: "CatoshiTerritory")
        .background {
            GeometryReader { proxy in
                Color.clear.preference(
                    key: StatusBarTerritoryWidthKey.self,
                    value: proxy.size.width
                )
            }
        }
        .onPreferenceChange(StatusBarTerritoryWidthKey.self) { territoryWidth in
            Task { @MainActor in
                let maxOffset = model.showCatoshi
                    ? max(0, territoryWidth - CatoshiMenuMascot.layoutWidth)
                    : 0
                model.updateCatoshiTerritory(maxOffset: maxOffset)
            }
        }
        .onPreferenceChange(StatusBarCatoshiWaypointKey.self) { separatorPositions in
            Task { @MainActor in
                let centerOffset = CatoshiMenuMascot.layoutWidth / 2
                model.updateCatoshiWaypoints(separatorPositions.map { $0 - centerOffset })
            }
        }
    }
}


@MainActor
private struct CatoshiStatusOverlay: View {
    @ObservedObject var motion: CatoshiMotionModel
    let coat: CatoshiCoat
    let animationEnabled: Bool
    let language: AppLanguage
    let fiveMinuteChange: Double?

    private var toolTip: String {
        let momentum = fiveMinuteChange.map { String(format: "BTC 5m %+.2f%%", $0) }
            ?? language.pick("BTC 5m 준비 중", "BTC 5m warming up")
        return "Catoshi · \(motion.state.label(language)) · \(momentum)"
    }

    var body: some View {
        CatoshiMenuMascot(
            state: motion.state,
            coat: coat,
            animationEnabled: animationEnabled,
            stateStartedAt: motion.stateStartedAt,
            basePositionX: motion.positionX,
            facing: motion.facing,
            moveDuration: motion.moveDuration,
            microMotion: motion.microMotion,
            microActive: motion.microActive,
            language: language
        )
        .help(toolTip)
    }
}

struct StatusBarSegment: View, Equatable {
    let value: String
    let change: Double?
    let changeSuffix: String
    let showChange: Bool
    let series: [Double]
    let showSparkline: Bool
    let palette: DisplayPalette

    static func == (lhs: StatusBarSegment, rhs: StatusBarSegment) -> Bool {
        guard lhs.value == rhs.value,
              lhs.showChange == rhs.showChange,
              lhs.showSparkline == rhs.showSparkline,
              lhs.changeSuffix == rhs.changeSuffix,
              lhs.palette.rawValue == rhs.palette.rawValue else {
            return false
        }

        if lhs.showChange, lhs.change != rhs.change { return false }
        if lhs.showSparkline, lhs.series != rhs.series { return false }
        return true
    }

    private var changeColor: Color {
        guard let change else { return .secondary }
        if palette == .monochrome { return .primary }
        return change >= 0 ? .green : .red
    }

    var body: some View {
        HStack(spacing: 6) {
            Text(value)
                .font(.system(size: 12, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(.primary)
                .lineLimit(1)

            if showChange, let change {
                Text(menuBarChangeText(change, suffix: changeSuffix))
                    .font(.system(size: 11, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(changeColor)
                    .lineLimit(1)
                    .transition(.opacity.combined(with: .scale(scale: 0.9)))
            }

            if showSparkline {
                MiniSparkline(values: series, trend: change, palette: palette)
                    .equatable()
                    .transition(.opacity.combined(with: .scale(scale: 0.9)))
            }
        }
        .animation(.easeInOut(duration: 0.16), value: showChange)
        .animation(.easeInOut(duration: 0.16), value: showSparkline)
    }
}

struct StatusBarSeparator: View {
    var marksCatoshiWaypoint = false

    var body: some View {
        Rectangle()
            .fill(Color.secondary.opacity(0.35))
            .frame(width: 1, height: 13)
            .background {
                if marksCatoshiWaypoint {
                    StatusBarCatoshiWaypointMarker()
                }
            }
    }
}

@MainActor
private struct StatusHealthIndicatorLive: View {
    @ObservedObject var healthState: StatusBarHealthState
    let palette: DisplayPalette

    var body: some View {
        StatusHealthIndicator(
            health: healthState.health,
            palette: palette
        )
    }
}

struct StatusHealthIndicator: View {
    let health: FeedHealth
    let palette: DisplayPalette

    var body: some View {
        Group {
            if palette == .color {
                Circle()
                    .fill(Color(nsColor: health.color))
            } else {
                switch health {
                case .healthy:
                    Circle().fill(Color.primary)
                case .stale:
                    Circle().fill(Color.secondary)
                case .disconnected:
                    Circle().stroke(Color.secondary, lineWidth: 1.2)
                }
            }
        }
        .frame(width: 7, height: 7)
    }
}

struct MiniSparkline: View, Equatable {
    let values: [Double]
    let trend: Double?
    let palette: DisplayPalette

    static func == (lhs: MiniSparkline, rhs: MiniSparkline) -> Bool {
        lhs.values == rhs.values &&
        lhs.trendDirection == rhs.trendDirection &&
        lhs.palette.rawValue == rhs.palette.rawValue
    }

    private var trendDirection: Int {
        guard let trend else { return 0 }
        return trend >= 0 ? 1 : -1
    }

    private var lineColor: Color {
        guard let trend else { return .secondary }
        if palette == .monochrome { return .primary.opacity(0.82) }
        return trend >= 0 ? .green : .red
    }

    var body: some View {
        Canvas { context, size in
            guard values.count >= 2,
                  let minimum = values.min(),
                  let maximum = values.max() else {
                var path = Path()
                path.move(to: CGPoint(x: 0, y: size.height / 2))
                path.addLine(to: CGPoint(x: size.width, y: size.height / 2))
                context.stroke(path, with: .color(.secondary.opacity(0.35)), lineWidth: 1)
                return
            }

            let span = maximum - minimum
            let count = values.count
            var path = Path()

            for (index, value) in values.enumerated() {
                let x = count == 1 ? 0 : CGFloat(index) / CGFloat(count - 1) * size.width
                let normalized = span == 0 ? 0.5 : (value - minimum) / span
                let y = size.height - CGFloat(normalized) * size.height
                let point = CGPoint(x: x, y: y)

                if index == 0 {
                    path.move(to: point)
                } else {
                    path.addLine(to: point)
                }
            }

            context.stroke(path, with: .color(lineColor), lineWidth: 1.15)
        }
        .frame(width: 38, height: 11)
        .accessibilityHidden(true)
    }
}
