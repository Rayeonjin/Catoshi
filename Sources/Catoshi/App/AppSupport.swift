import AppKit
import Combine
import Foundation
import SwiftUI

private enum CatoshiAppInfo {
    static let developer = CatoshiCommunity.developerDisplayName
    static let copyrightNotice = CatoshiCommunity.copyrightNotice

    static func assetNote(_ language: AppLanguage) -> String {
        language.pick(
            "고양이와 앱 아이콘은 Catoshi를 위해 생성·편집한 AI 보조 시각 자산이며, 외부 스톡 이미지를 번들에 포함하지 않습니다.",
            "The cat artwork and app icon are AI-assisted visual assets created and edited for Catoshi. No third-party stock artwork is bundled with the app."
        )
    }

    static func affiliationNote(_ language: AppLanguage) -> String {
        language.pick(
            "Catoshi는 독립적으로 제작된 앱이며 Bitcoin Core, Binance, Upbit, CoinGecko, DeFiLlama, Farside Investors 및 표시되는 거래소와 제휴하거나 공식적으로 승인된 제품이 아닙니다.",
            "Catoshi is an independent app and is not affiliated with, sponsored by, or officially endorsed by Bitcoin Core, Binance, Upbit, CoinGecko, DeFiLlama, Farside Investors, or the exchanges shown in the app."
        )
    }
}

enum AppLanguage: String, CaseIterable, Identifiable {
    case korean
    case english

    var id: String { rawValue }
    var selectorLabel: String { self == .korean ? "한국어" : "English" }

    func pick(_ korean: String, _ english: String) -> String {
        self == .korean ? korean : english
    }
}


enum AppAppearance: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    var id: String { rawValue }

    func label(_ language: AppLanguage) -> String {
        switch self {
        case .system: return language.pick("시스템", "System")
        case .light: return language.pick("라이트", "Light")
        case .dark: return language.pick("다크", "Dark")
        }
    }

    var symbolName: String {
        switch self {
        case .system: return "circle.lefthalf.filled"
        case .light: return "sun.max.fill"
        case .dark: return "moon.fill"
        }
    }

    var next: AppAppearance {
        switch self {
        case .system: return .light
        case .light: return .dark
        case .dark: return .system
        }
    }

    func cycleHelp(_ language: AppLanguage) -> String {
        language.pick(
            "화면 모드: \(label(language)) · 클릭하면 \(next.label(language))로 전환",
            "Appearance: \(label(language)) · Click to switch to \(next.label(language))"
        )
    }

    var nsAppearance: NSAppearance? {
        switch self {
        case .system: return nil
        case .light: return NSAppearance(named: .aqua)
        case .dark: return NSAppearance(named: .darkAqua)
        }
    }
}

@MainActor
struct CatoshiGuideView: View {
    let language: AppLanguage
    @StateObject private var loginItemManager = LoginItemManager()

    var body: some View {
        VStack(alignment: .leading, spacing: 11) {
            VStack(alignment: .leading, spacing: 3) {
                Text(language.pick("Catoshi 빠른 사용법", "Catoshi Quick Guide"))
                    .font(.system(size: CatoshiType.sectionTitle, weight: .semibold))
                Text(language.pick(
                    "설명서를 읽지 않아도 쓸 수 있도록 만들었지만, 처음이라면 아래 순서만 알아두면 됩니다.",
                    "Catoshi is designed to be usable without a manual. These few points are enough to get started."
                ))
                    .font(.system(size: CatoshiType.body))
                    .catoshiText(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            GuideRow(
                icon: "menubar.rectangle",
                title: language.pick("메뉴바", "Menu Bar"),
                text: language.pick(
                    "Binance BTC, Upbit BTC, 김치프리미엄을 확인합니다. 하단의 ‘표시항목 설정’에서 메뉴바에 남길 정보와 색상 표현을 고를 수 있습니다.",
                    "Monitor Binance BTC, Upbit BTC and the Kimchi Premium. Use ‘Display Settings’ below to choose menu-bar items and the color style."
                )
            )

            GuideRow(
                icon: "bitcoinsign.circle",
                title: language.pick("시세", "Price"),
                text: language.pick(
                    "BTC 가격, 24시간 변동, 김치프리미엄과 Binance·Upbit 연결 상태를 빠르게 확인합니다.",
                    "Check BTC prices, 24-hour changes, the Kimchi Premium, and Binance/Upbit connection health at a glance."
                )
            )

            GuideRow(
                icon: "chart.xyaxis.line",
                title: language.pick("시장", "Market"),
                text: language.pick(
                    "시장 탭은 ‘한눈에’에서 시장 구조·유동성·위험 선호·레버리지를 요약해 보고, ‘상세’에서 기존 9개 지표를 직접 확인합니다. 각 지표의 ⓘ를 누르면 수치의 의미·상승/하락 해석·주의점을 바로 볼 수 있습니다.",
                    "Use ‘At a Glance’ for Market Structure, Liquidity, Risk Appetite and Leverage, then switch to ‘Details’ to inspect the same nine indicators directly. Tap ⓘ on any metric to see what it measures, how to read moves, and what not to infer from it."
                )
            )

            GuideRow(
                icon: "building.columns",
                title: language.pick("국내 거래소", "KR Exchanges"),
                text: language.pick(
                    "거래소별 활동 상태·활동 배수·상대비중 변화와 24시간 거래대금 비중을 한 표에서 함께 봅니다. 앱 실행 후 화면이 켜져 있는 동안 자동으로 표본을 모아 약 2~5분부터 빠른 추정을 보여주고, 15분 이후에는 15m 활동으로 전환합니다. 로컬 기준선이 4개 미만이면 상태를 ‘잠정’으로 표시합니다. 일부 거래소가 점검/수신 불가여도 정상 수신 거래소의 활동 측정은 계속하며, ‘상대비중 Δ’는 5개 거래소 전체가 비교 가능한 경우에만 표시합니다.",
                    "Read each venue's activity state, activity ratio, relative-share change and 24-hour trading share in one table. While the display is awake, Catoshi starts sampling automatically, shows a quick estimate after about 2-5 minutes, and switches to a 15m view after 15 minutes. States remain provisional until four local baseline intervals exist. If a venue is under maintenance or unavailable, other venues keep measuring activity; Relative Share Δ appears only when all five venues are comparable."
                )
            )

            GuideRow(
                icon: "square.and.arrow.up",
                title: language.pick("공유 카드", "Share Cards"),
                text: language.pick(
                    "시세·시장·국내 거래소·정보 탭의 공유 버튼으로 현재 보유한 수치와 고양이를 담은 카드를 만듭니다. 출처·관측 시점·추정 지표를 함께 표시하고 오래된 입력은 자동 해석에서 제외합니다. Instagram 피드(1080×1350), Story(1080×1920), 정사각형(1080×1080)으로 이미지·캡션 복사, PNG 저장, macOS 공유를 사용할 수 있습니다. 캡션에는 데이터 출처와 Catoshi GitHub·Telegram 주소가 포함됩니다. 제3자 데이터에는 제공자별 이용 조건이 적용됩니다.",
                    "Share cards from Price, Market, KR Exchanges and About include retained values and a cat. Sources, observation times and estimated metrics are identified; stale inputs are excluded from automated interpretation. Choose Feed (1080×1350), Story (1080×1920) or Square (1080×1080), then copy the image or caption, save a PNG, or use macOS sharing. Captions include sources and the Catoshi GitHub and Telegram URLs. Provider terms apply to third-party data."
                )
            )

            GuideRow(
                icon: "pawprint.fill",
                title: "Catoshi",
                text: language.pick(
                    "Catoshi는 Binance 왼쪽을 집처럼 사용하지만 메뉴바 전체를 자기 생활권으로 돌아다닙니다. 산책 후 주변을 살피고 쉬는 행동이 자연스럽게 이어지며, 드물게 크게 기지개를 켜거나 주위를 돌아보거나 졸다 놀라는 행동도 합니다. BTC 급등·급락 반응에는 진입/해제 기준과 쿨다운을 함께 적용해 경계값 근처에서 같은 반응을 반복하지 않습니다. 상단의 ‘고양이 꾸미기’에서 털색·동작·활동량·시장 반응을 설정합니다.",
                    "Catoshi uses the space left of Binance as home while treating the whole menu bar as its territory. Walks now flow naturally into looking around and resting, with rare behaviors such as a big stretch, an over-the-shoulder look or a sleepy startle. Market reactions use separate entry/release thresholds plus cooldown so the same reaction does not flap around a boundary. Use ‘Customize Catoshi’ to choose its coat, motion, activity and market reactions."
                )
            )

            LoginItemSettingsRow(manager: loginItemManager, language: language)

            HStack(spacing: 12) {
                GuideStatusLegend(color: .green, text: language.pick("정상", "Healthy"))
                GuideStatusLegend(color: .yellow, text: language.pick("연결·복구 중", "Connecting"))
                GuideStatusLegend(color: .red, text: language.pick("연결 끊김", "Disconnected"))
            }
            .font(.system(size: CatoshiType.body))

            Text(language.pick(
                "시장 정보와 자동 해석은 참고용이며 투자자문이나 매수·매도 권유가 아닙니다.",
                "Market data and automated interpretations are for reference only and are not investment advice or a recommendation to buy or sell."
            ))
                .font(.system(size: CatoshiType.body))
                .catoshiText(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .onAppear {
            loginItemManager.refresh()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            loginItemManager.refresh()
        }
    }
}

@MainActor
private struct LoginItemSettingsRow: View {
    @ObservedObject var manager: LoginItemManager
    let language: AppLanguage

    private var toggleBinding: Binding<Bool> {
        Binding(
            get: { manager.isEnabled },
            set: { manager.setEnabled($0) }
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .center, spacing: 9) {
                Image(systemName: "power.circle")
                    .font(.system(size: CatoshiType.body, weight: .semibold))
                    .catoshiText(.secondary)
                    .frame(width: 18, alignment: .center)

                VStack(alignment: .leading, spacing: 2) {
                    Text(language.pick("로그인 시 Catoshi 자동 실행", "Launch Catoshi at Login"))
                        .font(.system(size: CatoshiType.rowTitle, weight: .semibold))
                    Text(language.pick(
                        "macOS에 로그인하면 Catoshi가 메뉴바에서 자동으로 시작됩니다.",
                        "Start Catoshi in the menu bar automatically when you log in to macOS."
                    ))
                        .font(.system(size: CatoshiType.body))
                        .catoshiText(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 8)

                Toggle("", isOn: toggleBinding)
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .disabled(manager.isChanging)
                    .accessibilityLabel(language.pick("로그인 시 자동 실행", "Launch at Login"))
            }

            if manager.requiresApproval {
                HStack(spacing: 7) {
                    Image(systemName: "exclamationmark.circle.fill")
                        .foregroundStyle(.orange)
                    Text(language.pick(
                        "macOS 승인이 필요합니다. 로그인 항목에서 Catoshi를 허용해 주세요.",
                        "macOS approval is required. Allow Catoshi in Login Items."
                    ))
                        .font(.system(size: CatoshiType.secondary))
                        .catoshiText(.secondary)
                    Spacer(minLength: 4)
                    Button(language.pick("로그인 항목 열기", "Open Login Items")) {
                        manager.openLoginItemsSettings()
                    }
                    .buttonStyle(.borderless)
                    .font(.system(size: CatoshiType.secondary, weight: .semibold))
                }
                .padding(.leading, 27)
            } else if manager.legacyLaunchAgentPresent {
                HStack(spacing: 7) {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .catoshiText(.metadata)
                    Text(language.pick(
                        "기존 자동 실행 설정을 유지하고 있습니다. 다시 켤 때 macOS 로그인 항목 방식으로 이전합니다.",
                        "The legacy auto-start setting is being preserved. Re-enabling it will migrate to macOS Login Items."
                    ))
                        .font(.system(size: CatoshiType.secondary))
                        .catoshiText(.metadata)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.leading, 27)
            }

            if let error = manager.lastErrorMessage {
                Text(language.pick("자동 실행 설정 오류: ", "Login-item error: ") + error)
                    .font(.system(size: CatoshiType.secondary))
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.leading, 27)
            }
        }
        .padding(.vertical, 7)
        .padding(.horizontal, 8)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.56))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

private struct GuideRow: View {
    let icon: String
    let title: String
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 9) {
            Image(systemName: icon)
                .font(.system(size: CatoshiType.body, weight: .semibold))
                .catoshiText(.secondary)
                .frame(width: 18, alignment: .center)
                .padding(.top, 1)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: CatoshiType.rowTitle, weight: .semibold))
                Text(text)
                    .font(.system(size: CatoshiType.body))
                    .catoshiText(.secondary)
                    .lineSpacing(1)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

private struct GuideStatusLegend: View {
    let color: Color
    let text: String

    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(color)
                .frame(width: 6, height: 6)
            Text(text)
                .font(.system(size: CatoshiType.secondary))
                .catoshiText(.secondary)
        }
    }
}

@MainActor
struct CatoshiAboutView: View {
    let language: AppLanguage
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 14) {
                if let icon = NSImage(named: "Catoshi_AppIcon") ?? NSApplication.shared.applicationIconImage {
                    Image(nsImage: icon)
                        .resizable()
                        .interpolation(.high)
                        .scaledToFit()
                        .frame(width: 64, height: 64)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text("Catoshi")
                        .font(.title2.weight(.bold))
                    Text(language.pick("메뉴바에 사는 작은 비트코인 고양이.", "A tiny Bitcoin cat living in your menu bar."))
                        .font(.system(size: CatoshiType.body))
                        .catoshiText(.secondary)
                    Text(language.pick("버전 \(AppMetadata.version)", "Version \(AppMetadata.version)"))
                        .font(.system(size: CatoshiType.secondary, design: .monospaced))
                        .catoshiText(.metadata)
                }
                Spacer(minLength: 0)
            }

            Divider()

            VStack(alignment: .leading, spacing: 8) {
                AboutDeveloperRow(language: language)
                AboutInfoRow(label: language.pick("저작권", "Copyright"), value: CatoshiAppInfo.copyrightNotice)
                AboutInfoRow(label: language.pick("지원 환경", "Requires"), value: "macOS 13+")
            }

            GroupBox(language.pick("프로젝트", "Project")) {
                VStack(alignment: .leading, spacing: 8) {
                    AboutProjectLinkRow(
                        icon: "chevron.left.forwardslash.chevron.right",
                        title: "GitHub",
                        detail: language.pick("소스 코드 · 빌드 가이드 · 버그 제보", "Source code · build guide · issue tracker"),
                        url: CatoshiCommunity.githubRepositoryURL
                    )
                    AboutProjectLinkRow(
                        icon: "paperplane.fill",
                        title: "Telegram",
                        detail: language.pick("공지 · 업데이트 · 간단 문의", "Announcements · updates · quick contact"),
                        url: CatoshiCommunity.telegramURL
                    )
                }
                .padding(.vertical, 4)
            }

            GroupBox(language.pick("공개 API 및 데이터 출처", "Public APIs & Data Sources")) {
                VStack(alignment: .leading, spacing: 5) {
                    CatoshiDataAttributionView()
                    Text(language.pick(
                        "모든 시장 데이터는 로그인이나 API Key가 필요 없는 공개 인터페이스만 사용합니다. 시장 데이터는 해당 탭에서만 갱신합니다. 국내 거래소 활동 레이더만 앱 실행 후 자동으로 시작하며, 화면이 켜진 동안 초기 15분에는 3분 간격의 경량 표본을 잠시 수집한 뒤 15분 백그라운드 주기로 낮아집니다. 각 백그라운드 표본에서 활동 계산까지 완료해 마지막 유효 15m 결과를 유지하므로 국내 거래소 탭을 열 때 측정을 새로 시작하지 않습니다. 일부 거래소가 수신 불가이면 정상 거래소의 측정을 이어가기 위해 3분 간격을 유지하고, 복구 후 다시 저빈도 주기로 돌아갑니다. 화면이 꺼지면 수집을 쉬고 깨어날 때 다시 갱신합니다. 국내 거래소 탭을 열면 이미 측정된 결과를 즉시 표시하고 1분 주기로 최신화하며, 기준선이 충분히 쌓이기 전에는 잠정 판정임을 화면에 표시합니다.",
                        "All market data uses public interfaces that require no account login or API key. Market context refreshes only in its tab. The KR-exchange activity radar starts automatically with the app while the display is awake, temporarily samples every 3 minutes during the first 15 minutes, then drops to a 15-minute background cadence. Each background sample is evaluated immediately and the latest valid 15m reading is retained, so opening the KR Exchanges tab does not restart measurement. If a venue becomes unavailable, the 3-minute cadence is retained temporarily so healthy venues keep measuring and recovery is picked up quickly; it returns to the lower cadence after recovery. It pauses while the display sleeps and refreshes again after wake. Opening the KR Exchanges tab shows the already-measured result immediately and refreshes it once per minute, while provisional states remain explicit until enough local baseline history exists."
                    ))
                        .font(.system(size: CatoshiType.body))
                        .catoshiText(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    AboutDataSourceRow(
                        provider: "Binance",
                        detail: language.pick("Spot/Futures API·WebSocket · BTC/USDT, ETH/BTC, 캔들, OI, Funding", "Spot/Futures API & WebSocket · BTC/USDT, ETH/BTC, candles, OI, funding")
                    )
                    AboutDataSourceRow(
                        provider: "Upbit",
                        detail: language.pick("REST·WebSocket · BTC/KRW, USDT/KRW, 캔들, 원화 거래대금", "REST & WebSocket · BTC/KRW, USDT/KRW, candles, KRW trading value")
                    )
                    AboutDataSourceRow(
                        provider: "CoinGecko",
                        detail: language.pick("Global/Core Markets API · BTC.D, USDT.D, TOTAL3* 계산 입력값", "Global/Core Markets API · inputs for BTC.D, USDT.D and TOTAL3*")
                    )
                    AboutDataSourceRow(
                        provider: "DeFiLlama",
                        detail: language.pick("Stablecoins API · USDT+USDC 공급량 및 7일 변화", "Stablecoins API · USDT+USDC supply and 7-day change")
                    )
                    AboutDataSourceRow(
                        provider: "Farside Investors",
                        detail: language.pick("공개 ETF 데이터 페이지 · 미국 현물 BTC ETF 일간·5거래일 순유입", "Public ETF data page · U.S. spot BTC ETF daily and 5-day net flows")
                    )
                    AboutDataSourceRow(
                        provider: language.pick("국내 거래소", "KR exchanges"),
                        detail: language.pick("Upbit·Bithumb·Coinone·Korbit·GOPAX 공개 API · 24시간 원화 거래대금 및 활동 레이더 입력값", "Upbit, Bithumb, Coinone, Korbit and GOPAX public APIs · 24h KRW trading value and activity-radar inputs")
                    )
                    Text(language.pick(
                        "공개 엔드포인트와 제공 범위는 각 데이터 제공자의 정책에 따라 변경될 수 있습니다.",
                        "Public endpoints and available fields may change with each provider's policy."
                    ))
                        .font(.system(size: CatoshiType.body))
                        .catoshiText(.metadata)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.vertical, 4)
            }

            GroupBox(language.pick("이미지 및 저작권", "Artwork & Copyright")) {
                Text(CatoshiAppInfo.assetNote(language))
                    .font(.system(size: CatoshiType.body))
                    .catoshiText(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.vertical, 4)
            }

            GroupBox(language.pick("데이터 및 면책", "Data & Disclaimer")) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(CatoshiAppInfo.affiliationNote(language))
                    Text(language.pick(
                        "Catoshi는 비상업적 개인 사용만 허용합니다. 회사·기관의 내부 업무나 상업적 사용은 허용하지 않습니다. 제3자 데이터의 이용·재공유에는 각 제공자의 조건이 적용됩니다.",
                        "Catoshi permits noncommercial personal use only. Internal business or institutional use and commercial use are not permitted. Provider terms govern third-party data use and resharing."
                    ))
                    Text(language.pick(
                        "시장 해석은 공개 데이터를 이용한 참고용 휴리스틱이며 투자자문이나 매수·매도 권유가 아닙니다.",
                        "Market interpretations are reference heuristics based on public data. They are not investment advice or a recommendation to buy or sell."
                    ))
                }
                .font(.system(size: CatoshiType.body))
                .catoshiText(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.vertical, 4)
            }
        }
    }
}

// Required provider attribution is separate from project and donation links.
// Keep this legible (12 pt; CoinGecko's minimum is 10) and visible next to data.
struct CatoshiDataAttributionView: View {
    var body: some View {
        Link("Powered by CoinGecko", destination: URL(string: "https://www.coingecko.com/")!)
            .font(.system(size: 12, weight: .semibold))
            .padding(.vertical, 4)
            .help("CoinGecko · BTC.D, USDT.D, TOTAL3")
            .accessibilityLabel("Powered by CoinGecko — coingecko.com")
    }
}

private enum AboutLayout {
    // Keep metadata values on one shared visual axis. This is intentionally
    // independent of label length in either Korean or English.
    static let metadataLabelWidth: CGFloat = 78
    static let metadataColumnSpacing: CGFloat = 8

    // Data-source names need enough room for the longest provider without
    // stealing excessive width from the descriptive column.
    static let providerWidth: CGFloat = 110
    static let sourceColumnSpacing: CGFloat = 10
}

private struct AboutDataSourceRow: View {
    let provider: String
    let detail: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: AboutLayout.sourceColumnSpacing) {
            Text(provider)
                .font(.system(size: CatoshiType.secondary, weight: .semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.9)
                .frame(width: AboutLayout.providerWidth, alignment: .leading)

            Text(detail)
                .font(.system(size: CatoshiType.body))
                .catoshiText(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct AboutInfoRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: AboutLayout.metadataColumnSpacing) {
            AboutMetadataLabel(text: label)

            Text(value)
                .font(.system(size: CatoshiType.body))
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
        }
    }
}

private struct AboutDeveloperRow: View {
    let language: AppLanguage

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: AboutLayout.metadataColumnSpacing) {
            AboutMetadataLabel(text: language.pick("제작자", "Developer"))

            Text(CatoshiAppInfo.developer)
                .font(.system(size: CatoshiType.body))
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
        }
    }
}

private struct AboutProjectLinkRow: View {
    let icon: String
    let title: String
    let detail: String
    let url: URL

    var body: some View {
        Link(destination: url) {
            HStack(spacing: 9) {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .semibold))
                    .frame(width: 20, alignment: .center)

                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(.system(size: CatoshiType.rowTitle, weight: .semibold))
                    Text(detail)
                        .font(.system(size: CatoshiType.secondary))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 8)
                Image(systemName: "arrow.up.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(url.absoluteString)
    }
}

private struct AboutMetadataLabel: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: CatoshiType.rowTitle, weight: .semibold))
            .catoshiText(.secondary)
            .frame(width: AboutLayout.metadataLabelWidth, alignment: .leading)
    }
}

@MainActor
final class PassthroughHostingView<Content: View>: NSHostingView<Content> {
    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }
}

