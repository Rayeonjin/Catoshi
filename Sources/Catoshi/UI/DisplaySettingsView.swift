import AppKit
import Foundation
import SwiftUI

@MainActor
struct DisplaySettingsEditor: View {
    @ObservedObject var model: MarketModel

    private var hasVisibleContent: Bool {
        model.showCatoshi || model.showMenuBarBinance || model.showMenuBarUpbit || model.showMenuBarPremium
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            SettingsCard(
                model.appLanguage.pick("실시간 미리보기", "Live Preview"),
                subtitle: model.appLanguage.pick(
                    "실제 메뉴바와 같은 순서·간격으로 표시합니다. 변경사항은 즉시 적용됩니다.",
                    "Uses the same order and spacing as the real menu bar. Changes apply immediately."
                )
            ) {
                MenuBarDisplayPreview(model: model)

                if !hasVisibleContent {
                    Label(
                        model.appLanguage.pick(
                            "모든 항목이 꺼져 있어 연결 상태 점만 메뉴바에 남습니다.",
                            "All content is hidden, so only the connection-status dot remains."
                        ),
                        systemImage: "info.circle"
                    )
                    .font(.system(size: CatoshiType.secondary))
                    .catoshiText(.secondary)
                }
            }

            SettingsCard(
                model.appLanguage.pick("표현 방식", "Presentation"),
                subtitle: model.appLanguage.pick(
                    "색상에만 의존하지 않도록 상승·하락 화살표는 두 모드에서 모두 유지됩니다.",
                    "Direction arrows remain visible in both modes, so meaning never relies on color alone."
                )
            ) {
                VStack(spacing: 11) {
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(model.appLanguage.pick("색상 표현", "Color Style"))
                                .font(.system(size: CatoshiType.body, weight: .medium))
                            Text(model.appLanguage.pick(
                                "상승·하락과 연결 상태에 색상을 사용할지 선택",
                                "Choose whether trends and connection state use color"
                            ))
                                .font(.system(size: CatoshiType.secondary))
                                .catoshiText(.secondary)
                        }
                        Spacer(minLength: 12)
                        Picker(model.appLanguage.pick("색상 표현", "Color Style"), selection: $model.displayPalette) {
                            ForEach(DisplayPalette.allCases) { palette in
                                Text(palette.label(model.appLanguage)).tag(palette)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.segmented)
                        .frame(width: 150)
                    }

                    Divider()

                    SettingToggleRow(
                        model.appLanguage.pick("Catoshi 표시", "Show Catoshi"),
                        detail: model.appLanguage.pick(
                            "메뉴바 왼쪽 생활공간과 고양이를 표시합니다.",
                            "Shows Catoshi and its home area at the left of the menu bar strip."
                        ),
                        isOn: $model.showCatoshi
                    )
                }
            }

            SettingsCard(
                model.appLanguage.pick("시장 항목", "Market Items"),
                subtitle: model.appLanguage.pick(
                    "각 항목의 가격·24시간 변화·미니 차트를 독립적으로 구성합니다.",
                    "Configure each price, 24-hour change and mini chart independently."
                )
            ) {
                VStack(spacing: 12) {
                    MenuBarDisplayGroup(
                        title: "Binance BTC",
                        detail: "BTC/USDT",
                        isOn: $model.showMenuBarBinance,
                        show24h: $model.showMenuBarBinance24h,
                        showChart: $model.showMenuBarBinanceSparkline,
                        language: model.appLanguage
                    )

                    Divider()

                    MenuBarDisplayGroup(
                        title: "Upbit BTC",
                        detail: "BTC/KRW",
                        isOn: $model.showMenuBarUpbit,
                        show24h: $model.showMenuBarUpbit24h,
                        showChart: $model.showMenuBarUpbitSparkline,
                        language: model.appLanguage
                    )

                    Divider()

                    MenuBarDisplayGroup(
                        title: model.appLanguage.pick("김치프리미엄", "Kimchi Premium"),
                        detail: model.appLanguage.pick("Upbit/Binance 환산 차이", "Converted Upbit/Binance gap"),
                        isOn: $model.showMenuBarPremium,
                        show24h: $model.showMenuBarPremium24h,
                        showChart: $model.showMenuBarPremiumSparkline,
                        language: model.appLanguage
                    )
                }
            }

            HStack {
                Spacer()
                Button(model.appLanguage.pick("메뉴바 기본값 복원", "Restore Menu Bar Defaults")) {
                    model.resetDisplaySettings()
                }
                .controlSize(.small)
            }
        }
    }
}

private struct MenuBarDisplayGroup: View {
    let title: String
    let detail: String
    @Binding var isOn: Bool
    @Binding var show24h: Bool
    @Binding var showChart: Bool
    let language: AppLanguage

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            SettingToggleRow(title, detail: detail, isOn: $isOn)

            HStack(spacing: 18) {
                Toggle(language.pick("24시간 변동률", "24h change"), isOn: $show24h)
                    .toggleStyle(.checkbox)
                Toggle(language.pick("미니 차트", "Mini chart"), isOn: $showChart)
                    .toggleStyle(.checkbox)
                Spacer(minLength: 0)
            }
            .font(.system(size: CatoshiType.secondary))
            .padding(.leading, 4)
            .disabled(!isOn)
            .opacity(isOn ? 1 : 0.45)
        }
    }
}

@MainActor
private struct MenuBarDisplayPreview: View {
    @ObservedObject var model: MarketModel

    private var hasAnyMarketSegment: Bool {
        model.showMenuBarBinance || model.showMenuBarUpbit || model.showMenuBarPremium
    }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 9) {
                if model.showCatoshi {
                    ZStack(alignment: .leading) {
                        Color.clear
                            .frame(width: CatoshiMenuMascot.layoutWidth, height: 20)
                        if let image = CatoshiAssets.sprite(named: "idle", coat: model.catoshiCoat) {
                            Image(nsImage: image)
                                .resizable()
                                .interpolation(.none)
                                .scaledToFit()
                                .frame(width: 60, height: 20)
                        }
                    }
                    .frame(width: CatoshiMenuMascot.layoutWidth, height: 20)

                    if hasAnyMarketSegment {
                        StatusBarSeparator()
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
                }

                if model.showMenuBarBinance && (model.showMenuBarUpbit || model.showMenuBarPremium) {
                    StatusBarSeparator()
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
                }

                if model.showMenuBarUpbit && model.showMenuBarPremium {
                    StatusBarSeparator()
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
                }

                if hasAnyMarketSegment {
                    StatusBarSeparator()
                }

                StatusHealthIndicator(
                    health: feedHealth(model: model),
                    palette: model.displayPalette
                )
            }
            .padding(.horizontal, 10)
            .frame(height: 32)
        }
        .frame(maxWidth: .infinity, minHeight: 32, alignment: .leading)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.66))
        .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .stroke(Color.secondary.opacity(0.15), lineWidth: 0.7)
        }
    }
}
