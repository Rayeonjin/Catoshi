import AppKit
import Foundation
import SwiftUI

enum MainPopoverTab: String, CaseIterable, Identifiable {
    case prices
    case market
    case domestic
    case guide
    case info

    var id: String { rawValue }
    func label(_ language: AppLanguage) -> String {
        switch self {
        case .prices: return language.pick("시세", "Price")
        case .market: return language.pick("시장", "Market")
        case .domestic: return language.pick("국내 거래소", "KR Exchanges")
        case .guide: return language.pick("사용법", "Guide")
        case .info: return language.pick("정보", "About")
        }
    }
    var focus: MarketContextFocus {
        switch self {
        case .prices: return .none
        case .market: return .market
        case .domestic: return .domestic
        case .guide, .info: return .none
        }
    }

    var shareSection: CatoshiShareSection? {
        switch self {
        case .prices: return .prices
        case .market: return .market
        case .domestic: return .domestic
        case .info: return .info
        case .guide: return nil
        }
    }

    var shortcutKey: KeyEquivalent {
        switch self {
        case .prices: return "1"
        case .market: return "2"
        case .domestic: return "3"
        case .guide: return "4"
        case .info: return "5"
        }
    }
}

private struct PopoverContentHeightKey: SwiftUI.PreferenceKey {
    static var defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

struct MarketPopover: View {
    @ObservedObject var model: MarketModel
    let onPreferredHeightChange: (CGFloat) -> Void
    let onSelectedTabChange: (MainPopoverTab) -> Void
    @State private var selectedTab: MainPopoverTab
    @State private var showDisplayEditor = false
    @State private var showCatoshiEditor = false
    @State private var showShareCard = false

    init(
        model: MarketModel,
        initialTab: MainPopoverTab = .prices,
        onPreferredHeightChange: @escaping (CGFloat) -> Void,
        onSelectedTabChange: @escaping (MainPopoverTab) -> Void = { _ in }
    ) {
        self.model = model
        self.onPreferredHeightChange = onPreferredHeightChange
        self.onSelectedTabChange = onSelectedTabChange
        _selectedTab = State(initialValue: initialTab)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            CatoshiControlRow(
                model: model,
                showCatoshiEditor: $showCatoshiEditor,
                showDisplayEditor: $showDisplayEditor
            )

            MainPopoverTabBar(
                selectedTab: $selectedTab,
                language: model.appLanguage
            )

            Group {
                switch selectedTab {
                case .prices:
                    PriceOverviewSection(model: model)
                case .market:
                    MarketContextSection(
                        context: model.marketContext,
                        palette: model.displayPalette,
                        premium: model.premium,
                        btcChange24h: model.binanceBTC?.change24h,
                        btcChange5m: model.fiveMinuteChange,
                        language: model.appLanguage,
                        btcUpdatedAt: model.binanceLastTickAt,
                        premiumUpdatedAt: {
                            guard let binance = model.binanceLastTickAt, let upbit = model.upbitLastTickAt else { return nil }
                            return min(binance, upbit)
                        }()
                    )
                case .domestic:
                    DomesticMarketSection(context: model.marketContext, palette: model.displayPalette, language: model.appLanguage)
                case .guide:
                    CatoshiGuideView(language: model.appLanguage)
                case .info:
                    CatoshiAboutView(language: model.appLanguage)
                }
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .transaction { transaction in
                // Tab content should replace immediately. Panel
                // sizing is handled separately after layout has settled.
                transaction.animation = nil
            }

            Divider()

            PopoverFooterControls(
                model: model,
                selectedTab: selectedTab,
                showDisplayEditor: $showDisplayEditor,
                showCatoshiEditor: $showCatoshiEditor,
                showShareCard: $showShareCard
            )
        }
        .background {
            GeometryReader { proxy in
                Color.clear.preference(
                    key: PopoverContentHeightKey.self,
                    value: proxy.size.height
                )
            }
        }
        .onPreferenceChange(PopoverContentHeightKey.self) { measuredHeight in
            // MarketPopover is wrapped by 14 pt vertical padding in MenuPanelController.
            // Use the actual rendered height instead of a per-tab guess so the panel
            // hugs the content even when interpretation text changes dynamically.
            guard measuredHeight > 0 else { return }
            onPreferredHeightChange(ceil(measuredHeight + 28))
        }
        .onAppear {
            model.marketContext.setFocus(selectedTab.focus)
        }
        .onChange(of: selectedTab) { newValue in
            showShareCard = false
            model.marketContext.setFocus(newValue.focus)
            onSelectedTabChange(newValue)
        }
    }
}

private struct MainPopoverTabBar: View {
    @Binding var selectedTab: MainPopoverTab
    let language: AppLanguage

    var body: some View {
        HStack(spacing: 4) {
            ForEach(MainPopoverTab.allCases) { tab in
                let isSelected = selectedTab == tab
                Button {
                    selectedTab = tab
                } label: {
                    Text(tab.label(language))
                        .font(.system(size: CatoshiType.tab, weight: isSelected ? .semibold : .medium))
                        .catoshiText(isSelected ? .primary : .secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.92)
                        .frame(maxWidth: .infinity, minHeight: 32)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .keyboardShortcut(tab.shortcutKey, modifiers: .command)
                .background {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(isSelected ? Color.accentColor.opacity(0.18) : .clear)
                }
                .overlay {
                    if isSelected {
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .stroke(Color.accentColor.opacity(0.58), lineWidth: 0.8)
                    }
                }
                .accessibilityValue(isSelected ? language.pick("선택됨", "Selected") : "")
            }
        }
        .padding(3)
        .frame(maxWidth: .infinity)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.82))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color.secondary.opacity(0.20), lineWidth: 0.8)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(language.pick("보기", "View"))
    }
}

@MainActor
private struct PopoverFooterControls: View {
    @ObservedObject var model: MarketModel
    let selectedTab: MainPopoverTab
    @Binding var showDisplayEditor: Bool
    @Binding var showCatoshiEditor: Bool
    @Binding var showShareCard: Bool

    var body: some View {
        HStack(spacing: 6) {
            Button {
                showCatoshiEditor = false
                showDisplayEditor.toggle()
            } label: {
                Label(
                    model.appLanguage.pick("표시항목 설정", "Display Settings"),
                    systemImage: "menubar.rectangle"
                )
                .font(.system(size: CatoshiType.button, weight: .semibold))
                .lineLimit(1)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .help(model.appLanguage.pick("메뉴바 항목과 색상 표현 설정", "Configure menu-bar items and color style"))
            .popover(isPresented: $showDisplayEditor, arrowEdge: .bottom) {
                DisplaySettingsEditor(model: model)
                    .padding(10)
                    .frame(width: 500)
            }

            Button {
                model.appAppearance = model.appAppearance.next
            } label: {
                Image(systemName: model.appAppearance.symbolName)
                    .font(.system(size: 12, weight: .semibold))
                    .frame(width: 16, height: 16)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .help(model.appAppearance.cycleHelp(model.appLanguage))
            .accessibilityLabel(model.appLanguage.pick("화면 모드", "Appearance"))
            .accessibilityValue(model.appAppearance.label(model.appLanguage))

            Picker(model.appLanguage.pick("언어", "Language"), selection: $model.appLanguage) {
                ForEach(AppLanguage.allCases) { language in
                    Text(language.selectorLabel).tag(language)
                }
            }
            .labelsHidden()
            .pickerStyle(.segmented)
            .controlSize(.small)
            .frame(width: 112)

            Spacer(minLength: 14)

            if let shareSection = selectedTab.shareSection {
                Button {
                    showDisplayEditor = false
                    showCatoshiEditor = false
                    showShareCard.toggle()
                } label: {
                    Image(systemName: "square.and.arrow.up")
                        .font(.system(size: 12, weight: .semibold))
                        .frame(width: 16, height: 16)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .help(model.appLanguage.pick("현재 화면 공유 카드 만들기", "Create a share card for this view"))
                .accessibilityLabel(model.appLanguage.pick("공유", "Share"))
                .popover(isPresented: $showShareCard, arrowEdge: .bottom) {
                    CatoshiShareCardPopover(model: model, section: shareSection)
                }
            }

            Button {
                NSApplication.shared.terminate(nil)
            } label: {
                Label(model.appLanguage.pick("종료", "Quit"), systemImage: "power")
                    .font(.system(size: CatoshiType.button, weight: .semibold))
                    .lineLimit(1)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .keyboardShortcut("q", modifiers: .command)
            .help(model.appLanguage.pick("Catoshi 종료", "Quit Catoshi"))
        }
        .frame(maxWidth: .infinity)
    }
}

private struct PriceOverviewSection: View {
    @ObservedObject var model: MarketModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            QuoteRow(
                title: "Binance",
                price: model.binanceBTC.map { formatUSD($0.price) } ?? "$---",
                change: model.binanceBTC?.change24h,
                palette: model.displayPalette
            )
            Divider()
            QuoteRow(
                title: "Upbit",
                price: model.upbitBTC.map { formatKRW($0.price) } ?? "₩---",
                change: model.upbitBTC?.change24h,
                palette: model.displayPalette
            )
            Divider()
            PremiumRow(
                premium: model.premium,
                palette: model.displayPalette,
                language: model.appLanguage
            )
            Divider()
            HStack(spacing: 12) {
                ConnectionDot(label: "Binance", state: model.binanceState, palette: model.displayPalette, language: model.appLanguage)
                ConnectionDot(label: "Upbit", state: model.upbitState, palette: model.displayPalette, language: model.appLanguage)
                Spacer(minLength: 6)
                Button {
                    model.reconnectFeeds()
                } label: {
                    Label(model.appLanguage.pick("재연결", "Reconnect"), systemImage: "arrow.clockwise").font(.system(size: CatoshiType.metadata, weight: .medium))
                }
                .buttonStyle(.borderless)
                .help(model.appLanguage.pick("Binance와 Upbit를 새로 연결", "Reconnect Binance and Upbit"))
                Text(model.updatedAt.map(formatTime) ?? "--:--:--")
                    .font(.system(size: CatoshiType.metadata, design: .monospaced))
                    .catoshiText(.metadata)
            }
        }
    }
}
