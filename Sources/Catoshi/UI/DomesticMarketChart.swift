import Foundation
import SwiftUI

struct DomesticVolumePieChart: View {
    let snapshot: DomesticVolumeSnapshot
    let palette: DisplayPalette
    let language: AppLanguage

    private var entries: [DomesticExchangeVolume] {
        snapshot.entries.sorted { $0.krw24h > $1.krw24h }
    }

    var body: some View {
        GeometryReader { proxy in
            let size = min(proxy.size.width, proxy.size.height)
            ZStack {
                ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
                    PieSlice(
                        startAngle: .degrees(startDegrees(for: index) - 90),
                        endAngle: .degrees(endDegrees(for: index) - 90)
                    )
                    .fill(exchangeColor(entry.exchange, palette: palette, index: index))
                }

                Circle()
                    .fill(Color(nsColor: .windowBackgroundColor))
                    .frame(width: size * 0.42, height: size * 0.42)

                VStack(spacing: 0) {
                    Text("24h")
                        .font(.system(size: CatoshiType.metadata, weight: .semibold))
                    Text(formatKRWTradingValue(snapshot.total, language: language))
                        .font(.system(size: CatoshiType.metadata, weight: .medium, design: .rounded))
                        .minimumScaleFactor(0.90)
                        .lineLimit(1)
                }
                .catoshiText(.secondary)
                .frame(width: size * 0.40)
            }
            .frame(width: size, height: size)
        }
        .aspectRatio(1, contentMode: .fit)
    }

    private func startDegrees(for index: Int) -> Double {
        guard snapshot.total > 0, index > 0 else { return 0 }
        let before = entries.prefix(index).reduce(0) { $0 + $1.krw24h }
        return before / snapshot.total * 360
    }

    private func endDegrees(for index: Int) -> Double {
        guard snapshot.total > 0 else { return 0 }
        let through = entries.prefix(index + 1).reduce(0) { $0 + $1.krw24h }
        return through / snapshot.total * 360
    }
}

private struct PieSlice: Shape {
    var startAngle: Angle
    var endAngle: Angle

    func path(in rect: CGRect) -> Path {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let radius = min(rect.width, rect.height) / 2
        var path = Path()
        path.move(to: center)
        path.addArc(
            center: center,
            radius: radius,
            startAngle: startAngle,
            endAngle: endAngle,
            clockwise: false
        )
        path.closeSubpath()
        return path
    }
}
