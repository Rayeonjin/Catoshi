import Foundation
import SwiftUI

private enum MarketViewMode: String, CaseIterable, Identifiable {
    case overview
    case detail

    var id: String { rawValue }

    func label(_ language: AppLanguage) -> String {
        switch self {
        case .overview: return language.pick("한눈에", "At a Glance")
        case .detail: return language.pick("상세", "Details")
        }
    }
}

private struct MarketMetricExplanation {
    let title: String
    let what: String
    let positiveLabel: String
    let positive: String
    let negativeLabel: String
    let negative: String
    let caution: String
}

struct MarketContextSection: View {
    @ObservedObject var context: MarketContextModel
    let palette: DisplayPalette
    let premium: PremiumSnapshot?
    let btcChange24h: Double?
    let btcChange5m: Double?
    let language: AppLanguage
    let btcUpdatedAt: Date?
    let premiumUpdatedAt: Date?

    @AppStorage("marketViewModeV1") private var viewModeRaw = MarketViewMode.overview.rawValue

    private let overviewColumns = [
        GridItem(.flexible(), spacing: 7),
        GridItem(.flexible(), spacing: 7)
    ]

    private let detailColumns = [
        GridItem(.flexible(), spacing: 7),
        GridItem(.flexible(), spacing: 7),
        GridItem(.flexible(), spacing: 7)
    ]

    private var viewMode: Binding<MarketViewMode> {
        Binding(
            get: { MarketViewMode(rawValue: viewModeRaw) ?? .overview },
            set: { viewModeRaw = $0.rawValue }
        )
    }

    private var inputs: MarketInterpretationInputs { context.interpretationInputs() }

    private var read: MarketRead {
        makeMarketRead(
            macro: context.macro,
            fast: context.fast,
            investor: context.investor,
            freshness: context.freshness,
            premium: premium,
            btcChange24h: btcChange24h,
            btcChange5m: btcChange5m,
            language: language,
            btcUpdatedAt: btcUpdatedAt,
            premiumUpdatedAt: premiumUpdatedAt
        )
    }

    private func dimension(_ id: String) -> MarketReadDimension? {
        read.dimensions.first { $0.id == id }
    }

    private var conciseSummary: String {
        let summary = read.summary.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let range = summary.range(of: ". ") else { return summary }
        return String(summary[..<range.lowerBound]) + "."
    }

    private var riskAppetiteSignal: String {
        guard let macro = inputs.macro else { return language.pick("대기", "Waiting") }
        let usdt = metricTrend(macro.usdtDominanceChange24hPP, threshold: 0.10)
        let total3 = metricTrend(macro.total3Change24h, threshold: 0.75)

        if usdt == .down, total3 == .up {
            return language.pick("개선", "Improving")
        }
        if usdt == .up, total3 == .down {
            return language.pick("약함", "Weak")
        }
        if usdt == .up {
            return language.pick("방어적", "Defensive")
        }
        if total3 == .up {
            return language.pick("확산 시도", "Broadening")
        }
        return language.pick("혼조", "Mixed")
    }

    private var riskAppetiteExplanation: String {
        guard let macro = inputs.macro else {
            return language.pick("USDT.D와 TOTAL3 데이터가 모이면 위험선호의 방향을 요약합니다.", "Risk appetite is summarized once USDT.D and TOTAL3 are available.")
        }
        let usdt = metricTrend(macro.usdtDominanceChange24hPP, threshold: 0.10)
        let total3 = metricTrend(macro.total3Change24h, threshold: 0.75)

        if usdt == .down, total3 == .up {
            return language.pick("USDT 비중은 낮아지고 BTC·ETH 제외 시장은 커져 위험자산으로의 확산과 부합합니다.", "USDT share is falling while the ex-BTC/ETH market expands, which is consistent with broader risk deployment.")
        }
        if usdt == .up, total3 == .down {
            return language.pick("USDT 비중이 높아지고 알트 시장 규모는 줄어 방어적 흐름과 부합합니다.", "USDT share is rising while the alt market contracts, which is consistent with defensive positioning.")
        }
        return language.pick("USDT.D와 TOTAL3가 한 방향으로 충분히 정렬되지 않았습니다.", "USDT.D and TOTAL3 are not aligned strongly enough in one direction.")
    }

    var body: some View {
        // This timer exists only while the Market tab is mounted. Age labels also
        // advance offline, without adding any background network or refresh work.
        TimelineView(.periodic(from: .now, by: 60)) { _ in
            marketContent
        }
    }

    private var marketContent: some View {
        VStack(alignment: .leading, spacing: 8) {
            header

            switch viewMode.wrappedValue {
            case .overview:
                overviewContent
            case .detail:
                detailContent
            }

            sourceStatusRows
            CatoshiDataAttributionView()

            Text(language.pick(
                "참고용 시장 해석입니다. 각 지표는 서로 보완해서 읽고 단일 수치만으로 매매를 결정하지 마세요.",
                "Reference market interpretation only. Read indicators together rather than making trading decisions from a single number."
            ))
                .font(.system(size: CatoshiType.secondary))
                .catoshiText(.metadata)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var sourceStatusRows: some View {
        VStack(alignment: .leading, spacing: 3) {
            sourceStatusRow("CoinGecko", source: .macro, updatedAt: context.macro?.updatedAt)
            sourceStatusRow("Binance", source: .fast, updatedAt: context.fast?.updatedAt)
            sourceStatusRow("DeFiLlama · Farside · Binance", source: .investor, updatedAt: context.investor?.updatedAt)
            Text(language.pick(
                "해석 제외 기준: 매크로 20분 · ETH/파생 3분 · 일간 지표 수신 2시간 경과 또는 갱신 실패. ETF 보고일은 별도 표시하며 7일 경과 시 제외합니다.",
                "Reads exclude failed data or ages ≥20m macro, ≥3m ETH/derivatives, ≥2h daily-data receipt. ETF reports ≥7 calendar days old are excluded."))
                .font(.system(size: CatoshiType.metadata))
                .catoshiText(.metadata)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func sourceStatusRow(_ title: String, source: MarketDataSource, updatedAt: Date?) -> some View {
        HStack(alignment: .top, spacing: 5) {
            Text(title)
            Spacer(minLength: 4)
            Text(context.status(for: source).label(language))
            Text(updatedAt.map { date in
                language.pick(source == .macro ? "관측 " : "수신 ", source == .macro ? "As of " : "Received ") + dataTimestamp(date)
            } ?? "--")
                .monospacedDigit()
        }
        .font(.system(size: CatoshiType.metadata))
        .catoshiText(.secondary)
        .help(language.pick(
            "관측은 제공자 시각, 수신은 앱이 응답을 받은 시각입니다. 갱신 실패 시 마지막 값은 남기고 해석은 중단합니다.",
            "As of uses provider time; Received uses app receipt time. Failed refreshes retain the last value but stop its interpretation."))
    }

    private func dataTimestamp(_ date: Date) -> String {
        date.formatted(.dateTime.year().month(.twoDigits).day(.twoDigits).hour(.twoDigits(amPM: .omitted)).minute(.twoDigits))
    }

    private func metricStatus(_ source: MarketDataSource, hasValue: Bool) -> String {
        let status = context.status(for: source)
        guard status.allowsInterpretation else { return status.label(language) + language.pick(" · 해석 보류", " · Read paused") }
        return hasValue ? "" : language.pick("미수신 · 해석 제외", "Unavailable · Excluded")
    }

    private var etfStatus: String {
        let sourceStatus = metricStatus(.investor, hasValue: context.investor?.etfFiveDayFlowUSD != nil)
        guard sourceStatus.isEmpty else { return sourceStatus }
        guard let date = context.investor?.etfFlowDate else { return language.pick("보고일 미확인 · 해석 제외", "Report date unknown · Excluded") }
        let prefix = MarketInterpretationInputs.etfReportIsCurrent(date, now: Date())
            ? language.pick("보고 ", "Report ") : language.pick("오래된 보고 · ", "Stale report · ")
        return prefix + date.formatted(.dateTime.year().month(.twoDigits).day(.twoDigits))
    }

    private var header: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 1) {
                Text(language.pick("시장 흐름", "Market Pulse"))
                    .font(.system(size: CatoshiType.sectionTitle, weight: .semibold))
                Text(language.pick("요약으로 보고, 필요하면 같은 수치를 직접 확인합니다.", "Start with the read, then inspect the same numbers when needed."))
                    .font(.system(size: CatoshiType.secondary))
                    .catoshiText(.secondary)
            }

            Spacer(minLength: 8)

            Picker(language.pick("시장 보기", "Market view"), selection: viewMode) {
                ForEach(MarketViewMode.allCases) { mode in
                    Text(mode.label(language)).tag(mode)
                }
            }
            .labelsHidden()
            .pickerStyle(.segmented)
            .controlSize(.small)
            .frame(width: language == .english ? 170 : 132)

            if context.isRefreshing {
                ProgressView().controlSize(.mini)
            }

            Button { context.refreshNow() } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 10.8))
            }
            .buttonStyle(.borderless)
            .disabled(context.isRefreshing)
            .help(language.pick("시장 지표 지금 갱신", "Refresh market indicators now"))
        }
    }

    private var overviewContent: some View {
        VStack(alignment: .leading, spacing: 8) {
            MarketPulseSummaryCard(
                title: read.title,
                summary: conciseSummary,
                alignment: read.alignment,
                tone: read.tone,
                palette: palette
            )

            LazyVGrid(columns: overviewColumns, spacing: 7) {
                MarketOverviewSignalCard(
                    title: language.pick("시장 구조", "Market Structure"),
                    signal: dimension("lead")?.signal ?? language.pick("대기", "Waiting"),
                    explanation: dimension("lead")?.explanation ?? ""
                )
                MarketOverviewSignalCard(
                    title: language.pick("유동성", "Liquidity"),
                    signal: dimension("flow")?.signal ?? language.pick("대기", "Waiting"),
                    explanation: dimension("flow")?.explanation ?? ""
                )
                MarketOverviewSignalCard(
                    title: language.pick("위험 선호", "Risk Appetite"),
                    signal: riskAppetiteSignal,
                    explanation: riskAppetiteExplanation
                )
                MarketOverviewSignalCard(
                    title: language.pick("레버리지", "Leverage"),
                    signal: dimension("lev")?.signal ?? language.pick("대기", "Waiting"),
                    explanation: dimension("lev")?.explanation ?? ""
                )
            }

            HStack(spacing: 5) {
                Image(systemName: "info.circle")
                    .font(.system(size: 10.3))
                Text(language.pick(
                    "개별 수치와 해석법은 ‘상세’에서 확인할 수 있습니다.",
                    "Open Details to inspect each number and learn how to read it."
                ))
                    .font(.system(size: CatoshiType.secondary))
            }
            .catoshiText(.secondary)
        }
    }

    private var detailContent: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Circle()
                    .fill(marketReadAccent(read.tone, palette: palette))
                    .frame(width: 7, height: 7)
                Text(read.title)
                    .font(.system(size: CatoshiType.cardTitle, weight: .semibold))
                Text("·")
                    .catoshiText(.metadata)
                Text(read.alignment)
                    .font(.system(size: CatoshiType.secondary, weight: .medium))
                    .catoshiText(.secondary)
                Spacer()
                Text(language.pick("ⓘ에서 지표 해석 보기", "Use ⓘ to learn each metric"))
                    .font(.system(size: CatoshiType.metadata))
                    .catoshiText(.metadata)
            }

            MarketMetricGroup(title: language.pick("시장 구조", "Market Structure")) {
                LazyVGrid(columns: detailColumns, spacing: 7) {
                    MarketLearningMetricCard(
                        title: "BTC.D",
                        value: context.macro.map { String(format: "%.1f%%", $0.btcDominance) } ?? "--",
                        changeText: context.macro?.btcDominanceChange24hPP.map { "24h " + signedMetric($0) + "%p" } ?? "24h --",
                        statusText: metricStatus(.macro, hasValue: context.macro != nil),
                        signal: btcDominanceSignal,
                        explanation: btcDominanceExplanation,
                        language: language
                    )
                    MarketLearningMetricCard(
                        title: "TOTAL3*",
                        value: context.macro.map { formatUSDMarketCap($0.total3USD) } ?? "--",
                        changeText: context.macro?.total3Change24h.map { "24h " + signedMetric($0) + "%" } ?? "24h --",
                        statusText: metricStatus(.macro, hasValue: context.macro != nil),
                        signal: total3Signal,
                        explanation: total3Explanation,
                        language: language
                    )
                    MarketLearningMetricCard(
                        title: "ETH/BTC",
                        value: context.fast.map { String(format: "%.5f", $0.ethBTC) } ?? "--",
                        changeText: context.fast.map { "24h " + signedMetric($0.ethBTCChange24h) + "%" } ?? "24h --",
                        statusText: metricStatus(.fast, hasValue: context.fast != nil),
                        signal: ethBTCSignal,
                        explanation: ethBTCExplanation,
                        language: language
                    )
                }
            }

            MarketMetricGroup(title: language.pick("유동성", "Liquidity")) {
                LazyVGrid(columns: detailColumns, spacing: 7) {
                    MarketLearningMetricCard(
                        title: "USDT.D",
                        value: context.macro.map { String(format: "%.1f%%", $0.usdtDominance) } ?? "--",
                        changeText: context.macro?.usdtDominanceChange24hPP.map { "24h " + signedMetric($0) + "%p" } ?? "24h --",
                        statusText: metricStatus(.macro, hasValue: context.macro != nil),
                        signal: usdtDominanceSignal,
                        explanation: usdtDominanceExplanation,
                        language: language
                    )
                    MarketLearningMetricCard(
                        title: "Stables 7D",
                        value: context.investor?.stablecoinSupplyUSD.map(formatUSDMarketCap) ?? "--",
                        changeText: context.investor?.stablecoinSupplyChange7d.map { "7D " + signedMetric($0) + "%" } ?? "7D --",
                        statusText: metricStatus(.investor, hasValue: context.investor?.stablecoinSupplyUSD != nil),
                        signal: stablecoinSignal,
                        explanation: stablecoinExplanation,
                        language: language
                    )
                }
            }

            MarketMetricGroup(title: language.pick("현물 수요 · 중기 추세", "Spot Demand · Medium Trend")) {
                LazyVGrid(columns: detailColumns, spacing: 7) {
                    MarketLearningMetricCard(
                        title: "BTC ETF",
                        value: context.investor?.etfLatestFlowUSD.map(formatSignedUSDFlow) ?? "--",
                        changeText: context.investor?.etfFiveDayFlowUSD.map { "5D " + formatSignedUSDFlow($0) } ?? "5D --",
                        statusText: etfStatus,
                        signal: etfSignal,
                        explanation: etfExplanation,
                        language: language
                    )
                    MarketLearningMetricCard(
                        title: "BTC Trend",
                        value: formatBTCTrendValue(context.investor),
                        changeText: formatBTCTrendDetail(context.investor),
                        statusText: metricStatus(.investor, hasValue: context.investor?.btcReturn30d != nil),
                        signal: btcTrendSignal,
                        explanation: btcTrendExplanation,
                        language: language
                    )
                }
            }

            MarketMetricGroup(title: language.pick("레버리지", "Leverage")) {
                LazyVGrid(columns: detailColumns, spacing: 7) {
                    MarketLearningMetricCard(
                        title: "BTC OI",
                        value: context.fast?.openInterestUSD.map(formatUSDMarketCap) ?? "--",
                        changeText: context.fast?.openInterestChange1h.map { "1h " + signedMetric($0) + "%" } ?? "1h --",
                        statusText: metricStatus(.fast, hasValue: context.fast?.openInterestUSD != nil),
                        signal: openInterestSignal,
                        explanation: openInterestExplanation,
                        language: language
                    )
                    MarketLearningMetricCard(
                        title: "Funding",
                        value: context.fast?.fundingRatePercent.map { String(format: "%+.3f%%", $0) } ?? "--",
                        changeText: context.fast?.fundingRatePercent != nil ? context.fast.map { language.pick("수신 ", "Received ") + formatTime($0.updatedAt) } ?? "--" : "--",
                        statusText: metricStatus(.fast, hasValue: context.fast?.fundingRatePercent != nil),
                        signal: fundingSignal,
                        explanation: fundingExplanation,
                        language: language
                    )
                }
            }
        }
    }

    private var btcDominanceSignal: String {
        switch metricTrend(inputs.macro?.btcDominanceChange24hPP, threshold: 0.15) {
        case .up: return language.pick("BTC 상대 우위 강화", "BTC relative strength rising")
        case .down: return language.pick("BTC 상대 우위 약화", "BTC relative strength falling")
        case .flat: return language.pick("BTC 비중 큰 변화 없음", "BTC share broadly stable")
        case .unknown: return language.pick("데이터 대기", "Waiting for data")
        }
    }

    private var usdtDominanceSignal: String {
        switch metricTrend(inputs.macro?.usdtDominanceChange24hPP, threshold: 0.10) {
        case .up: return language.pick("방어적 비중 확대", "Defensive share rising")
        case .down: return language.pick("위험자산 배치와 부합", "Consistent with risk deployment")
        case .flat: return language.pick("대기자금 비중 안정", "Stablecoin share broadly stable")
        case .unknown: return language.pick("데이터 대기", "Waiting for data")
        }
    }

    private var total3Signal: String {
        switch metricTrend(inputs.macro?.total3Change24h, threshold: 0.75) {
        case .up: return language.pick("알트 시장 규모 확대", "Alt market expanding")
        case .down: return language.pick("알트 시장 규모 축소", "Alt market contracting")
        case .flat: return language.pick("알트 시장 규모 보합", "Alt market broadly flat")
        case .unknown: return language.pick("데이터 대기", "Waiting for data")
        }
    }

    private var ethBTCSignal: String {
        switch metricTrend(inputs.fast?.ethBTCChange24h, threshold: 0.50) {
        case .up: return language.pick("ETH 상대강세", "ETH outperforming BTC")
        case .down: return language.pick("ETH 상대약세", "ETH underperforming BTC")
        case .flat: return language.pick("ETH/BTC 큰 변화 없음", "ETH/BTC broadly stable")
        case .unknown: return language.pick("데이터 대기", "Waiting for data")
        }
    }

    private var stablecoinSignal: String {
        guard let change = inputs.investor?.stablecoinSupplyChange7d else { return language.pick("데이터 대기", "Waiting for data") }
        if change >= 0.50 { return language.pick("유동성 기반 확대", "Liquidity base expanding") }
        if change <= -0.50 { return language.pick("유동성 기반 축소", "Liquidity base contracting") }
        return language.pick("공급 큰 변화 없음", "Supply broadly stable")
    }

    private var etfSignal: String {
        guard let flow = inputs.investor?.etfFiveDayFlowUSD else { return language.pick("데이터 대기", "Waiting for data") }
        if flow >= 500_000_000 { return language.pick("강한 현물 순유입", "Strong spot inflow") }
        if flow >= 100_000_000 { return language.pick("현물 순유입", "Spot inflow") }
        if flow <= -500_000_000 { return language.pick("강한 현물 순유출", "Strong spot outflow") }
        if flow <= -100_000_000 { return language.pick("현물 순유출", "Spot outflow") }
        return language.pick("현물 수급 중립", "Spot flow neutral")
    }

    private var btcTrendSignal: String {
        guard let snapshot = inputs.investor,
              let ret30 = snapshot.btcReturn30d,
              let above = snapshot.btcAbove200DMA else {
            return language.pick("데이터 대기", "Waiting for data")
        }
        if above, ret30 >= 5.0 { return language.pick("중기 상승 구조", "Medium-term uptrend") }
        if !above, ret30 <= -5.0 { return language.pick("중기 약세 구조", "Weak medium-term structure") }
        return above ? language.pick("200DMA 위", "Above 200DMA") : language.pick("200DMA 아래", "Below 200DMA")
    }

    private var openInterestSignal: String {
        guard let change = inputs.fast?.openInterestChange1h else { return language.pick("데이터 대기", "Waiting for data") }
        if change >= 5.0 { return language.pick("레버리지 빠르게 확대", "Leverage building quickly") }
        if change >= 3.0 { return language.pick("레버리지 확대", "Leverage building") }
        if change <= -3.0 { return language.pick("디레버리징", "Deleveraging") }
        return language.pick("큰 변화 없음", "No major change")
    }

    private var fundingSignal: String {
        guard let funding = inputs.fast?.fundingRatePercent else { return language.pick("데이터 대기", "Waiting for data") }
        if funding >= 0.05 { return language.pick("롱 쏠림 주의", "Long crowding risk") }
        if funding <= -0.05 { return language.pick("숏 쏠림 주의", "Short crowding risk") }
        return language.pick("중립권", "Near neutral")
    }

    private var btcDominanceExplanation: MarketMetricExplanation {
        MarketMetricExplanation(
            title: "BTC.D",
            what: language.pick("전체 가상자산 시가총액에서 Bitcoin이 차지하는 비중입니다.", "Bitcoin's share of total crypto market capitalization."),
            positiveLabel: language.pick("상승하면", "When it rises"),
            positive: language.pick("알트보다 BTC의 상대적 비중이 커지고 있다는 뜻입니다. BTC가 시장을 주도하거나 알트가 더 약하게 움직일 때도 상승할 수 있습니다.", "BTC is gaining share relative to alts. This can happen because BTC leads the market or because alts are falling faster."),
            negativeLabel: language.pick("하락하면", "When it falls"),
            negative: language.pick("BTC보다 알트의 상대적 비중이 커지는 방향입니다. TOTAL3가 같이 늘어나는지 보면 실제 알트 시장 확대인지 구분하기 쉽습니다.", "Alts are gaining relative share versus BTC. Check TOTAL3 to see whether the alt market itself is actually expanding."),
            caution: language.pick("BTC.D 상승이 BTC 가격 상승이나 신규자금 유입을 뜻하는 것은 아닙니다. 전체 시총 변화에 따른 분모 효과가 있습니다.", "Rising BTC.D does not necessarily mean BTC price is rising or that fresh capital is entering. The denominator also changes with total market cap.")
        )
    }

    private var usdtDominanceExplanation: MarketMetricExplanation {
        MarketMetricExplanation(
            title: "USDT.D",
            what: language.pick("전체 가상자산 시가총액에서 USDT가 차지하는 비중입니다.", "USDT's share of total crypto market capitalization."),
            positiveLabel: language.pick("상승하면", "When it rises"),
            positive: language.pick("시장 내 스테이블코인의 상대적 비중이 커져 방어적 포지셔닝과 부합할 수 있습니다.", "Stablecoins are taking a larger relative share, which can be consistent with more defensive positioning."),
            negativeLabel: language.pick("하락하면", "When it falls"),
            negative: language.pick("USDT 비중이 줄어 위험자산 배치와 부합할 수 있습니다. Stablecoin Supply가 같이 늘면 신규 유동성 해석이 더 강해집니다.", "USDT share is falling, which can fit risk deployment. If stablecoin supply also expands, the fresh-liquidity interpretation is stronger."),
            caution: language.pick("가격 상승으로 전체 시총이 커져 USDT.D가 내려갈 수도 있습니다. 비중과 실제 스테이블 공급량은 다릅니다.", "USDT.D can fall simply because crypto prices lift the total market cap. Share and actual stablecoin supply are different measures.")
        )
    }

    private var total3Explanation: MarketMetricExplanation {
        MarketMetricExplanation(
            title: "TOTAL3*",
            what: language.pick("전체 가상자산 시가총액에서 BTC와 ETH를 제외한 시장 규모의 프록시입니다.", "A proxy for total crypto market capitalization excluding BTC and ETH."),
            positiveLabel: language.pick("상승하면", "When it rises"),
            positive: language.pick("BTC·ETH 이외 알트 시장의 총 규모가 커지고 있다는 뜻입니다. BTC.D 하락과 함께 나타나면 알트 확산 해석이 더 강해집니다.", "The market value of alts outside BTC and ETH is expanding. Together with falling BTC.D, it is stronger evidence of broadening alt participation."),
            negativeLabel: language.pick("하락하면", "When it falls"),
            negative: language.pick("알트 시장의 파이가 줄고 있다는 뜻입니다. BTC.D가 내려가더라도 TOTAL3가 줄면 건강한 알트 순환으로 보기 어렵습니다.", "The alt market is shrinking. Even if BTC.D falls, declining TOTAL3 is not a healthy alt-rotation signal."),
            caution: language.pick("여기서는 여러 공개 시가총액 데이터를 조합한 프록시를 사용합니다. 정확한 개별 종목 투자판단 지표는 아닙니다.", "This app uses a proxy assembled from public market-cap data. It is not a precise signal for any individual asset.")
        )
    }

    private var ethBTCExplanation: MarketMetricExplanation {
        MarketMetricExplanation(
            title: "ETH/BTC",
            what: language.pick("ETH 가격을 BTC 가격으로 나눈 상대가격입니다.", "ETH's price expressed in BTC, measuring ETH's relative performance versus BTC."),
            positiveLabel: language.pick("상승하면", "When it rises"),
            positive: language.pick("ETH가 BTC보다 강하게 움직이고 있다는 뜻입니다. TOTAL3까지 상승하면 대형 알트에서 더 넓은 알트 시장으로 힘이 확산되는지 볼 수 있습니다.", "ETH is outperforming BTC. If TOTAL3 also rises, relative strength may be spreading beyond large-cap alts."),
            negativeLabel: language.pick("하락하면", "When it falls"),
            negative: language.pick("BTC가 ETH보다 상대적으로 강하거나 ETH가 더 약하다는 뜻입니다.", "BTC is relatively stronger than ETH, or ETH is weakening faster."),
            caution: language.pick("ETH/BTC 하나만으로 전체 알트 시장을 대표하지는 않습니다. TOTAL3와 함께 보는 편이 안전합니다.", "ETH/BTC does not represent the entire alt market. Read it together with TOTAL3.")
        )
    }

    private var stablecoinExplanation: MarketMetricExplanation {
        MarketMetricExplanation(
            title: "Stables 7D",
            what: language.pick("USDT와 USDC 유통량의 7일 변화입니다. 도미넌스가 아닌 실제 공급량을 봅니다.", "The 7-day change in circulating USDT and USDC. Unlike dominance, this measures actual supply."),
            positiveLabel: language.pick("늘어나면", "When it rises"),
            positive: language.pick("시장에 배치될 수 있는 스테이블 유동성의 기반이 확대되는 방향입니다.", "The base of stablecoin liquidity available to the market is expanding."),
            negativeLabel: language.pick("줄어들면", "When it falls"),
            negative: language.pick("스테이블 유동성 기반이 축소되는 방향이라 위험자산 유입 여력이 약해질 수 있습니다.", "The stablecoin liquidity base is contracting, which can reduce potential deployable capital."),
            caution: language.pick("공급 증가가 즉시 코인 매수를 뜻하지는 않습니다. USDT.D와 실제 가격 흐름을 함께 봐야 합니다.", "More supply does not mean it is immediately buying crypto. Read it with USDT.D and actual price action.")
        )
    }

    private var etfExplanation: MarketMetricExplanation {
        MarketMetricExplanation(
            title: "BTC ETF",
            what: language.pick("미국 현물 Bitcoin ETF의 순유입·순유출입니다. 화면의 해석은 최근 5거래일 누적을 더 중요하게 봅니다.", "Net flows into and out of US spot Bitcoin ETFs. The app gives more weight to the latest five trading days."),
            positiveLabel: language.pick("순유입이면", "With net inflows"),
            positive: language.pick("기관성 현물 수요가 BTC 가격을 지지하는 방향입니다. 며칠간 지속되는지가 중요합니다.", "Institutional spot demand is supporting BTC. Persistence over several sessions matters more than one day."),
            negativeLabel: language.pick("순유출이면", "With net outflows"),
            negative: language.pick("현물 기관성 수요가 약해지는 방향입니다. 가격이 강하다면 레버리지가 대신 커지고 있는지도 확인합니다.", "Institutional spot demand is weakening. If price remains strong, check whether leverage is filling the gap."),
            caution: language.pick("미국 거래일 중 최신 일간 값은 잠정치일 수 있으며 ETF 흐름 하나로 가격 방향을 확정할 수 없습니다.", "The latest US trading-day figure may be provisional, and ETF flows alone do not determine price direction.")
        )
    }

    private var btcTrendExplanation: MarketMetricExplanation {
        MarketMetricExplanation(
            title: "BTC Trend",
            what: language.pick("BTC의 7일·30일 수익률과 200일 이동평균 위/아래 여부를 함께 봅니다.", "BTC's 7-day and 30-day returns together with whether price is above or below the 200-day moving average."),
            positiveLabel: language.pick("강해지면", "When stronger"),
            positive: language.pick("30일 모멘텀이 양호하고 200DMA 위에 있으면 단기 조정을 중기 상승 구조 안의 조정으로 볼 근거가 늘어납니다.", "Positive 30-day momentum above the 200DMA gives more support to treating short-term weakness as a pullback inside a broader uptrend."),
            negativeLabel: language.pick("약해지면", "When weaker"),
            negative: language.pick("30일 수익률이 약하고 200DMA 아래라면 단기 반등도 우선 중기 약세 구조 안의 반등으로 봅니다.", "Weak 30-day momentum below the 200DMA makes short-term rallies more likely to be rebounds inside a weaker medium-term regime."),
            caution: language.pick("200DMA는 느린 추세 지표입니다. 정확한 매수·매도 타이밍을 알려주는 신호가 아닙니다.", "The 200DMA is a slow trend measure, not a precise entry or exit signal.")
        )
    }

    private var openInterestExplanation: MarketMetricExplanation {
        MarketMetricExplanation(
            title: "BTC OI",
            what: language.pick("Binance BTCUSDT 무기한 선물의 미결제약정 규모입니다. 열려 있는 레버리지 포지션의 크기를 보여줍니다.", "Binance BTCUSDT perpetual open interest, showing the size of outstanding leveraged positions."),
            positiveLabel: language.pick("빠르게 늘면", "When it rises quickly"),
            positive: language.pick("시장에 레버리지가 쌓이는 구간일 수 있습니다. 가격과 같은 방향으로 과도하게 늘면 청산 위험도 커질 수 있습니다.", "Leverage may be building. If it expands too quickly with price, liquidation risk can also rise."),
            negativeLabel: language.pick("줄어들면", "When it falls"),
            negative: language.pick("포지션이 정리되는 디레버리징 구간일 수 있습니다.", "Positions may be closing in a deleveraging phase."),
            caution: language.pick("OI 증가는 롱인지 숏인지 알려주지 않습니다. Funding과 가격 방향을 함께 봐야 합니다.", "Rising OI does not tell you whether positioning is long or short. Read it with funding and price direction.")
        )
    }

    private var fundingExplanation: MarketMetricExplanation {
        MarketMetricExplanation(
            title: "Funding",
            what: language.pick("무기한 선물 가격을 현물에 가깝게 유지하기 위해 롱과 숏 사이에 주고받는 펀딩비입니다.", "The periodic payment between longs and shorts that helps keep perpetual futures close to spot prices."),
            positiveLabel: language.pick("큰 양수면", "When strongly positive"),
            positive: language.pick("롱 포지션의 비용이 커져 롱 쏠림 가능성을 경계합니다.", "Longs are paying more, which can indicate crowded long positioning."),
            negativeLabel: language.pick("큰 음수면", "When strongly negative"),
            negative: language.pick("숏 포지션의 비용이 커져 숏 쏠림 가능성을 경계합니다.", "Shorts are paying more, which can indicate crowded short positioning."),
            caution: language.pick("양수는 상승 신호, 음수는 하락 신호라는 뜻이 아닙니다. 포지셔닝의 혼잡도를 보는 지표입니다.", "Positive funding is not automatically bullish and negative funding is not automatically bearish. It is primarily a crowding measure.")
        )
    }
}

private struct MarketPulseSummaryCard: View {
    let title: String
    let summary: String
    let alignment: String
    let tone: MarketReadTone
    let palette: DisplayPalette

    private var accent: Color { marketReadAccent(tone, palette: palette) }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 6) {
                Circle().fill(accent).frame(width: 8, height: 8)
                Text(title)
                    .font(.system(size: CatoshiType.metric, weight: .semibold))
                Spacer()
                Text(alignment)
                    .font(.system(size: CatoshiType.secondary, weight: .semibold))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(accent.opacity(0.10))
                    .clipShape(Capsule())
            }

            Text(summary)
                .font(.system(size: CatoshiType.body))
                .lineSpacing(1.4)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(9)
        .background(accent.opacity(palette == .color ? 0.07 : 0.04))
        .overlay(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .stroke(accent.opacity(0.17), lineWidth: 0.8)
        )
        .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
    }
}

private struct MarketOverviewSignalCard: View {
    let title: String
    let signal: String
    let explanation: String

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.system(size: CatoshiType.secondary, weight: .semibold))
                .catoshiText(.secondary)
            Text(signal)
                .font(.system(size: CatoshiType.cardTitle, weight: .semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.90)
            if !explanation.isEmpty {
                Text(explanation)
                    .font(.system(size: CatoshiType.secondary))
                    .catoshiText(.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 70, alignment: .topLeading)
        .padding(8)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.50))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

private struct MarketMetricGroup<Content: View>: View {
    let title: String
    let content: Content

    init(title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(.system(size: CatoshiType.cardTitle, weight: .semibold))
                .catoshiText(.secondary)
            content
        }
    }
}

private struct MarketLearningMetricCard: View {
    let title: String
    let value: String
    let changeText: String
    let statusText: String
    let signal: String
    let explanation: MarketMetricExplanation
    let language: AppLanguage

    @State private var showExplanation = false

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 4) {
                Text(title)
                    .font(.system(size: CatoshiType.secondary, weight: .semibold))
                    .catoshiText(.secondary)
                Spacer(minLength: 2)
                Button {
                    showExplanation.toggle()
                } label: {
                    Image(systemName: "info.circle")
                        .font(.system(size: CatoshiType.metadata))
                        .catoshiText(.secondary)
                }
                .buttonStyle(.plain)
                .help(language.pick("지표 해석 보기", "How to read this metric"))
                .popover(isPresented: $showExplanation, arrowEdge: .trailing) {
                    MarketMetricExplanationPopover(explanation: explanation, language: language)
                }
            }

            Text(value)
                .font(.system(size: CatoshiType.metric, weight: .semibold, design: .monospaced))
                .lineLimit(1)
                .minimumScaleFactor(0.90)

            Text(changeText)
                .font(.system(size: CatoshiType.table, weight: .medium, design: .monospaced))
                .catoshiText(.metadata)
                .lineLimit(1)
                .minimumScaleFactor(0.90)

            if !statusText.isEmpty {
                Text(statusText)
                    .font(.system(size: CatoshiType.metadata))
                    .catoshiText(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Text(signal)
                .font(.system(size: CatoshiType.secondary, weight: .semibold))
                .lineLimit(2)
                .minimumScaleFactor(0.90)
        }
        .frame(maxWidth: .infinity, minHeight: 82, alignment: .topLeading)
        .padding(7)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.55))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color.secondary.opacity(0.12), lineWidth: 0.7)
        )
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

private struct MarketMetricExplanationPopover: View {
    let explanation: MarketMetricExplanation
    let language: AppLanguage

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text(explanation.title)
                .font(.system(size: CatoshiType.metric, weight: .semibold))

            ExplanationBlock(
                title: language.pick("무엇인가요?", "What is it?"),
                text: explanation.what
            )
            ExplanationBlock(title: explanation.positiveLabel, text: explanation.positive)
            ExplanationBlock(title: explanation.negativeLabel, text: explanation.negative)

            Divider()

            ExplanationBlock(
                title: language.pick("주의", "Caution"),
                text: explanation.caution
            )
        }
        .padding(12)
        .frame(width: 340)
    }
}

private struct ExplanationBlock: View {
    let title: String
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.system(size: CatoshiType.secondary, weight: .semibold))
            Text(text)
                .font(.system(size: CatoshiType.body))
                .catoshiText(.secondary)
                .lineSpacing(1.2)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}


struct DomesticMarketSection: View {
    @ObservedObject var context: MarketContextModel
    let palette: DisplayPalette
    let language: AppLanguage

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(language.pick("국내 거래소", "KR Exchanges"))
                    .font(.system(size: CatoshiType.sectionTitle, weight: .semibold))
                Spacer()
                if context.isRefreshing { ProgressView().controlSize(.mini) }
                Button { context.refreshNow() } label: {
                    Image(systemName: "arrow.clockwise").font(.system(size: 10.6))
                }
                .buttonStyle(.borderless)
                .disabled(context.isRefreshing)
                .help(language.pick("국내 거래소 데이터 지금 갱신", "Refresh Korean exchange data now"))
            }

            DomesticActivityRadarCard(
                snapshot: context.domesticActivity,
                volumeSnapshot: context.domestic,
                availability: context.domesticAvailability,
                palette: palette,
                language: language
            )

            if let snapshot = context.domestic, !snapshot.entries.isEmpty, !snapshot.isPartial {
                HStack(alignment: .center, spacing: 16) {
                    DomesticVolumePieChart(snapshot: snapshot, palette: palette, language: language)
                        .frame(width: 116, height: 116)
                        .accessibilityLabel(language.pick("국내 거래소 24시간 거래대금 비중", "Korea exchange 24-hour trading-value share"))

                    VStack(alignment: .leading, spacing: 6) {
                        Text(language.pick("24h 거래대금 비중", "24h Trading Share"))
                            .font(.system(size: CatoshiType.cardTitle, weight: .semibold))

                        HStack(spacing: 6) {
                            Text(language.pick("합계", "Total"))
                                .font(.system(size: CatoshiType.secondary, weight: .medium))
                                .catoshiText(.secondary)
                            Text(formatKRWTradingValue(snapshot.total, language: language))
                                .font(.system(size: CatoshiType.body, weight: .semibold, design: .rounded))

                            Text("·")
                                .font(.system(size: CatoshiType.metadata))
                                .catoshiText(.metadata)

                            Text(formatTime(snapshot.updatedAt))
                                .font(.system(size: CatoshiType.metadata, design: .monospaced))
                                .catoshiText(.metadata)
                        }
                        .lineLimit(1)
                        .minimumScaleFactor(0.90)

                        Text(language.pick(
                            "위 통합 표의 거래소 색상과 같은 기준으로 표시합니다.",
                            "Colors match the exchange markers in the combined table above."
                        ))
                            .font(.system(size: CatoshiType.secondary))
                            .catoshiText(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            } else if let snapshot = context.domestic, snapshot.isPartial {
                Label(
                    language.pick(
                        "일부 거래소 데이터가 없어 24h 비중 차트는 표시하지 않습니다.",
                        "The 24h share chart is hidden while some exchange data is unavailable."
                    ),
                    systemImage: "chart.pie.fill"
                )
                .font(.system(size: CatoshiType.secondary, weight: .medium))
                .catoshiText(.secondary)
                .frame(maxWidth: .infinity, minHeight: 84, alignment: .leading)
            } else if context.domesticRefreshIssue != nil {
                Label(
                    language.pick(
                        "현재 24h 거래대금 집계를 표시할 수 없습니다.",
                        "The 24h trading-value summary is currently unavailable."
                    ),
                    systemImage: "exclamationmark.triangle.fill"
                )
                .font(.system(size: CatoshiType.secondary, weight: .medium))
                .catoshiText(.secondary)
                .frame(maxWidth: .infinity, minHeight: 84, alignment: .leading)
            } else {
                HStack(spacing: 7) {
                    ProgressView().controlSize(.small)
                    Text(language.pick("거래대금 데이터를 불러오는 중…", "Loading trading-value data…"))
                        .font(.system(size: CatoshiType.secondary))
                        .catoshiText(.secondary)
                }
                .frame(maxWidth: .infinity, minHeight: 150)
            }

            if let issue = context.domesticRefreshIssue {
                Label(issue.message(language), systemImage: "exclamationmark.triangle")
                    .font(.system(size: CatoshiType.metadata, weight: .medium))
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Text(language.pick(
                "활동 레이더는 화면이 켜진 동안 앱과 함께 계속 동작합니다. 초기 15분은 3분 간격으로 빠르게 기준을 만들고, 이후에는 15분마다 수집·평가해 마지막 유효 15m 결과를 유지합니다. 이 탭을 열면 측정을 새로 시작하지 않고 이미 측정된 결과를 즉시 보여주며, 열린 동안에는 1분마다 최신화합니다.",
                "The activity radar keeps running with the app while the display is awake: every 3 minutes during the first 15 minutes, then every 15 minutes. Each background sample is evaluated and the latest valid 15m reading is retained. Opening this tab shows the existing measurement immediately instead of restarting it, then refreshes once per minute while visible."
            ))
                .font(.system(size: CatoshiType.secondary))
                .catoshiText(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private enum DomesticActivityDisplayConfidence: Equatable {
    case measuring
    case estimated
    case provisional
    case stable
}

private enum DomesticActivityTableMetrics {
    // Use semantic groups rather than one mechanically aligned six-column strip.
    // Labels read naturally, while numeric values still keep stable trailing axes.
    // 170 + 12 + 122 + 12 + 134 = 450 pt total.
    static let groupSpacing: CGFloat = 12
    static let columnSpacing: CGFloat = 6

    static let exchange: CGFloat = 76
    static let state: CGFloat = 88
    static let identityGroup: CGFloat = exchange + columnSpacing + state

    static let activity: CGFloat = 46
    static let relativeShare: CGFloat = 70
    static let radarGroup: CGFloat = activity + columnSpacing + relativeShare

    static let volumeShare: CGFloat = 46
    static let volumeValue: CGFloat = 82
    static let volume24h: CGFloat = volumeShare + columnSpacing + volumeValue
}

private struct DomesticActivityRadarCard: View {
    let snapshot: DomesticActivitySnapshot?
    let volumeSnapshot: DomesticVolumeSnapshot?
    let availability: [DomesticExchangeAvailability]
    let palette: DisplayPalette
    let language: AppLanguage

    private func dataState(for exchange: DomesticExchange) -> DomesticExchangeDataState {
        availability.first(where: { $0.exchange == exchange })?.state ?? .unknown
    }

    private var maintenanceExchanges: [DomesticExchange] {
        availability.compactMap { $0.state == .maintenance ? $0.exchange : nil }
    }

    private var unavailableExchanges: [DomesticExchange] {
        availability.compactMap { $0.state == .unavailable ? $0.exchange : nil }
    }

    private var rowExchanges: [DomesticExchange] {
        guard let volumeSnapshot, !volumeSnapshot.entries.isEmpty else {
            return DomesticExchange.allCases
        }
        let ranked = volumeSnapshot.entries
            .sorted { $0.krw24h > $1.krw24h }
            .map(\.exchange)
        let missing = DomesticExchange.allCases.filter { !ranked.contains($0) }
        return ranked + missing
    }

    private var confidence: DomesticActivityDisplayConfidence {
        guard let snapshot else { return .measuring }
        switch snapshot.phase {
        case .measuring:
            return .measuring
        case .quickEstimate:
            return .estimated
        case .fifteenMinute:
            return snapshot.baselineIntervals >= 4 ? .stable : .provisional
        }
    }

    private var titleText: String {
        guard let snapshot else { return language.pick("현재 활동 · 측정 시작", "Current Activity · Starting") }
        switch snapshot.phase {
        case .measuring:
            return language.pick("현재 활동 · 측정 시작", "Current Activity · Starting")
        case .quickEstimate(let minutes):
            return language.pick("현재 활동 · 빠른 추정 \(minutes)m", "Current Activity · Quick \(minutes)m")
        case .fifteenMinute:
            return language.pick("현재 활동 · 15m", "Current Activity · 15m")
        }
    }

    private var baselineText: String {
        guard let snapshot else { return language.pick("첫 비교값 수집 중", "Collecting first comparison") }
        let count = min(snapshot.baselineIntervals, 20)
        switch snapshot.phase {
        case .measuring:
            return language.pick("첫 비교값 수집 중", "Collecting first comparison")
        case .quickEstimate:
            return language.pick("15m 기준 준비 중", "Preparing 15m baseline")
        case .fifteenMinute where count < 4:
            return language.pick("잠정 판정 · 기준 \(count)/4", "Provisional · baseline \(count)/4")
        case .fifteenMinute:
            return language.pick("기준선 \(count)/20", "Baseline \(count)/20")
        }
    }

    private var summaryText: String {
        if !maintenanceExchanges.isEmpty || !unavailableExchanges.isEmpty {
            let maintenanceNames = maintenanceExchanges.map(\.label).joined(separator: ", ")
            let unavailableNames = unavailableExchanges.map(\.label).joined(separator: ", ")
            if maintenanceExchanges.count + unavailableExchanges.count >= DomesticExchange.allCases.count {
                return language.pick(
                    "국내 거래소 데이터를 현재 수신하지 못해 활동 측정을 일시 중지합니다.",
                    "Domestic exchange data is currently unavailable, so activity measurement is paused."
                )
            }
            if !maintenanceNames.isEmpty, unavailableNames.isEmpty {
                return language.pick(
                    "\(maintenanceNames) 점검 중 · 나머지 거래소 활동은 계속 측정하며 상대비중 Δ는 일시 중지합니다.",
                    "\(maintenanceNames) is under maintenance. Other venues keep measuring activity; Relative Share Δ is paused."
                )
            }
            if maintenanceNames.isEmpty, !unavailableNames.isEmpty {
                return language.pick(
                    "\(unavailableNames) 수신 불가 · 나머지 거래소 활동은 계속 측정하며 상대비중 Δ는 일시 중지합니다.",
                    "\(unavailableNames) is unavailable. Other venues keep measuring activity; Relative Share Δ is paused."
                )
            }
            return language.pick(
                "\(maintenanceNames) 점검 중 · \(unavailableNames) 수신 불가 · 나머지 거래소 활동은 계속 측정합니다.",
                "\(maintenanceNames) under maintenance · \(unavailableNames) unavailable. Other venues keep measuring activity."
            )
        }

        guard let snapshot else {
            return language.pick("첫 비교값을 수집하고 있습니다.", "Collecting the first comparison sample.")
        }

        switch snapshot.phase {
        case .measuring:
            return language.pick(
                "첫 비교값을 수집하고 있습니다. 약 2~5분 뒤 빠른 추정을 시작합니다.",
                "Collecting the first comparison sample. A quick estimate starts in about 2-5 minutes."
            )
        case .quickEstimate, .fifteenMinute:
            break
        }

        let usable = snapshot.entries.filter { entry in
            guard let ratio = entry.activityRatio else { return false }
            return ratio.isFinite
        }
        guard !usable.isEmpty else {
            return language.pick("비교 가능한 활동값을 아직 확보하지 못했습니다.", "No comparable activity values are available yet.")
        }

        let strongest = usable.max { lhs, rhs in
            if lhs.level.rawValue != rhs.level.rawValue {
                return lhs.level.rawValue < rhs.level.rawValue
            }
            return (lhs.activityRatio ?? 0) < (rhs.activityRatio ?? 0)
        }

        if let strongest, strongest.level == .surging {
            if confidence == .stable {
                return language.pick(
                    "\(strongest.exchange.label) 활동 급증과 상대비중 확대가 함께 나타납니다.",
                    "\(strongest.exchange.label) shows both a sharp activity increase and a rising relative share."
                )
            }
            return language.pick(
                "\(strongest.exchange.label) 활동 급증 신호가 보이지만 기준선이 아직 얕아 잠정적으로 봅니다.",
                "\(strongest.exchange.label) shows a surge signal, but the baseline is still shallow, so treat it as provisional."
            )
        }

        if let strongest, strongest.level == .elevated {
            if confidence == .stable {
                return language.pick(
                    "\(strongest.exchange.label) 활동이 기준보다 늘고 상대비중도 확대되고 있습니다.",
                    "\(strongest.exchange.label) activity is above baseline and its relative share is expanding."
                )
            }
            return language.pick(
                "\(strongest.exchange.label) 활동 증가 신호가 있으나 아직 잠정 판정입니다.",
                "\(strongest.exchange.label) shows elevated activity, but the reading is still provisional."
            )
        }

        let ratios = usable.compactMap(\.activityRatio)
        if !ratios.isEmpty, ratios.allSatisfy({ $0 < 1.0 }) {
            let relativeLeader = usable
                .filter { ($0.shareDeltaPP ?? 0) >= 5.0 && ($0.activityRatio ?? 0) < 1.0 }
                .max { ($0.shareDeltaPP ?? -.infinity) < ($1.shareDeltaPP ?? -.infinity) }

            if let relativeLeader {
                return language.pick(
                    "전반 활동은 기준 이하이며, \(relativeLeader.exchange.label)의 상대비중만 확대됐습니다.",
                    "Overall activity is below baseline; only \(relativeLeader.exchange.label)'s relative share has expanded."
                )
            }
            return language.pick(
                "국내 거래소 전반의 활동이 현재 기준보다 낮은 편입니다.",
                "Activity across Korean exchanges is currently below baseline."
            )
        }

        return language.pick(
            "뚜렷한 거래소 활동 급증 신호는 없습니다.",
            "There is no clear exchange-activity surge signal."
        )
    }

    private var methodNote: String {
        guard let snapshot else {
            return language.pick(
                "앱 실행 후 자동으로 경량 표본을 모읍니다. 약 2~5분부터 빠른 추정을 표시하고, 15분 이후 15m 활동으로 전환합니다.",
                "Catoshi starts collecting lightweight samples automatically. A quick estimate appears after about 2-5 minutes, then switches to a 15m view after 15 minutes."
            )
        }
        switch snapshot.phase {
        case .measuring:
            return language.pick(
                "첫 표본을 기준으로 약 2~5분 뒤 빠른 추정을 시작합니다. 별도의 전 종목 체결 수집은 하지 않습니다.",
                "A quick estimate starts about 2-5 minutes after the first sample. Catoshi does not open all-market trade streams."
            )
        case .quickEstimate:
            return language.pick(
                "빠른 추정 · 공개 24h 거래대금의 단기 변화와 24h 속도를 비교합니다. 일부 거래소가 빠지면 정상 수신 거래소의 활동은 계속 계산하되 상대비중 Δ는 전체 비교가 가능할 때까지 표시하지 않습니다.",
                "Quick estimate · Compares short-term changes in public 24h turnover with its normalized pace. If a venue is missing, available venues keep their activity estimate while Relative Share Δ waits for a complete comparison."
            )
        case .fifteenMinute where snapshot.baselineIntervals < 4:
            return language.pick(
                "15m 관측은 확보했지만 로컬 기준선이 4개 미만이라 상태는 잠정 판정입니다. 일부 거래소가 빠지면 정상 수신 거래소의 활동만 계속 계산하고 상대비중 Δ는 전체 비교가 복구될 때까지 숨깁니다.",
                "A 15m observation is available, but fewer than four local baseline intervals means the state is provisional. With a missing venue, available venues keep measuring while Relative Share Δ stays hidden until the full comparison returns."
            )
        case .fifteenMinute:
            return language.pick(
                "경량 근사치 · 15분 변화량과 최근 최대 5시간의 로컬 기준선을 사용합니다. 거래소별 활동은 독립적으로 이어가며 상대비중 Δ는 5개 거래소 전체가 같은 구간에서 비교될 때만 표시합니다.",
                "Lightweight proxy · Uses the 15m change and up to 5 hours of local baseline history. Per-venue activity continues independently; Relative Share Δ appears only when all five venues are comparable over the same window."
            )
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 6) {
                Text(titleText)
                    .font(.system(size: CatoshiType.cardTitle, weight: .semibold))
                Text(baselineText)
                    .font(.system(size: CatoshiType.metadata, weight: confidence == .provisional ? .semibold : .medium, design: .monospaced))
                    .catoshiText(confidence == .provisional ? .secondary : .metadata)
                Spacer()
                if let snapshot {
                    Text(formatTime(snapshot.updatedAt))
                        .font(.system(size: CatoshiType.metadata, design: .monospaced))
                        .catoshiText(.metadata)
                }
            }

            Text(summaryText)
                .font(.system(size: CatoshiType.secondary, weight: .medium))
                .catoshiText(.body)
                .lineSpacing(1)
                .fixedSize(horizontal: false, vertical: true)

            Divider().opacity(0.45)

            VStack(spacing: 0) {
                HStack(spacing: DomesticActivityTableMetrics.groupSpacing) {
                    HStack(spacing: DomesticActivityTableMetrics.columnSpacing) {
                        Text(language.pick("거래소", "Exchange"))
                            .frame(width: DomesticActivityTableMetrics.exchange, alignment: .leading)
                        Text(language.pick("상태", "State"))
                            .frame(width: DomesticActivityTableMetrics.state, alignment: .leading)
                    }
                    .frame(width: DomesticActivityTableMetrics.identityGroup, alignment: .leading)

                    HStack(spacing: DomesticActivityTableMetrics.columnSpacing) {
                        Text(language.pick("활동", "Activity"))
                            .frame(width: DomesticActivityTableMetrics.activity, alignment: .center)
                        Text(language.pick("상대비중 Δ", "Relative Share Δ"))
                            .frame(width: DomesticActivityTableMetrics.relativeShare, alignment: .center)
                            .lineLimit(1)
                            .minimumScaleFactor(0.90)
                            .help(language.pick(
                                "같은 시점의 국내 5개 거래소 활동 중 상대비중 변화입니다. 양수라도 해당 거래소의 절대 활동이 늘었다는 뜻은 아니므로 ‘활동’ 배수와 함께 봅니다.",
                                "Change in relative share of activity across the five Korean exchanges. A positive value does not necessarily mean the venue's absolute activity increased; read it together with Activity."
                            ))
                    }
                    .frame(width: DomesticActivityTableMetrics.radarGroup, alignment: .center)

                    Text("24h")
                        .frame(width: DomesticActivityTableMetrics.volume24h, alignment: .center)
                        .help(language.pick("24시간 거래대금 비중 · 거래대금", "24-hour trading share · trading value"))
                }
                .font(.system(size: CatoshiType.tableHeader, weight: .medium))
                .catoshiText(.secondary)
                .padding(.vertical, 4)

                Divider().opacity(0.36)

                ForEach(Array(rowExchanges.enumerated()), id: \.element.id) { index, exchange in
                    DomesticActivityRow(
                        entry: snapshot?.entry(for: exchange),
                        volumeSnapshot: volumeSnapshot,
                        exchange: exchange,
                        dataState: dataState(for: exchange),
                        colorIndex: index,
                        palette: palette,
                        language: language,
                        confidence: confidence
                    )

                    if index < rowExchanges.count - 1 {
                        Divider().opacity(0.20)
                    }
                }
            }

            Text(methodNote)
                .font(.system(size: CatoshiType.secondary))
                .catoshiText(.secondary)
                .lineSpacing(1)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(9)
        .background(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(Color.secondary.opacity(0.055))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .stroke(Color.secondary.opacity(0.13), lineWidth: 0.7)
        )
        .help(language.pick(
            "약 2~5분부터 빠른 추정을 제공하고 15분 이후 15m 활동으로 전환합니다. 기준선 4개 미만의 15m 상태는 잠정 판정이며, 상대비중 Δ는 절대 활동 증가가 아니라 거래소 간 상대적인 비중 변화를 뜻합니다.",
            "A quick estimate appears after about 2-5 minutes and switches to a 15m view after 15 minutes. A 15m state with fewer than four baseline intervals is provisional, and Relative Share Δ reflects relative movement between exchanges rather than absolute activity growth."
        ))
    }
}

private struct DomesticActivityRow: View {
    let entry: DomesticExchangeActivity?
    let volumeSnapshot: DomesticVolumeSnapshot?
    let exchange: DomesticExchange
    let dataState: DomesticExchangeDataState
    let colorIndex: Int
    let palette: DisplayPalette
    let language: AppLanguage
    let confidence: DomesticActivityDisplayConfidence

    private var level: DomesticActivityLevel { entry?.level ?? .warmingUp }

    private var indicatorColor: Color {
        switch dataState {
        case .maintenance:
            return palette == .monochrome ? .primary : .orange
        case .unavailable:
            return palette == .monochrome ? .primary.opacity(0.78) : .orange.opacity(0.82)
        case .unknown, .available:
            break
        }

        if confidence == .provisional || confidence == .estimated {
            if level == .surging { return palette == .monochrome ? .primary : .orange.opacity(0.78) }
            if level == .elevated { return palette == .monochrome ? .primary : .accentColor.opacity(0.78) }
            return .primary.opacity(0.72)
        }
        if palette == .monochrome { return level == .warmingUp ? .primary.opacity(0.62) : .primary }
        switch level {
        case .warmingUp: return .primary.opacity(0.62)
        case .normal: return .primary.opacity(0.72)
        case .elevated: return .accentColor
        case .surging: return .orange
        }
    }

    private var statusText: String {
        switch dataState {
        case .maintenance:
            return language.pick("점검 중", "Maintenance")
        case .unavailable:
            return language.pick("수신 불가", "Unavailable")
        case .unknown, .available:
            let core = level.label(language)
            switch confidence {
            case .measuring, .stable:
                return core
            case .estimated:
                return language.pick("추정 \(core)", "Est. \(core)")
            case .provisional:
                return language.pick("잠정 \(core)", "Prov. \(core)")
            }
        }
    }

    private var ratioText: String {
        guard dataState == .available, let value = entry?.activityRatio, value.isFinite else { return "--" }
        if value >= 9.95 { return ">9.9×" }
        if value < 0.1 { return "<0.1×" }
        return String(format: "%.1f×", value)
    }

    private var shareText: String {
        guard dataState == .available, let value = entry?.shareDeltaPP, value.isFinite else { return "--" }
        return String(format: "%+.1f%%p", value)
    }

    private var shareColor: Color {
        guard dataState == .available, let entry,
              let ratio = entry.activityRatio,
              let share = entry.shareDeltaPP,
              ratio.isFinite, share.isFinite else { return .secondary }

        // Relative-share moves are deliberately deemphasized when absolute activity is below
        // baseline. This prevents a large +pp shift caused by other venues slowing down from
        // looking like an inflow/surge signal on its own.
        if ratio < 1.0 { return .primary.opacity(0.66) }
        if level == .surging { return palette == .monochrome ? .primary : .orange }
        if level == .elevated { return palette == .monochrome ? .primary : .accentColor }
        return .primary.opacity(0.82)
    }

    private var volumeEntry: DomesticExchangeVolume? {
        volumeSnapshot?.entries.first { $0.exchange == exchange }
    }

    private var volumeShareText: String {
        guard dataState == .available,
              let volumeSnapshot,
              !volumeSnapshot.isPartial,
              let volumeEntry else { return "--" }
        return String(format: "%.1f%%", volumeSnapshot.share(for: volumeEntry))
    }

    private var volumeValueText: String {
        guard dataState == .available, let volumeEntry else { return "--" }
        return formatKRWTradingValue(volumeEntry.krw24h, language: language)
    }

    private var exchangeMarkerColor: Color {
        exchangeColor(exchange, palette: palette, index: colorIndex)
    }

    var body: some View {
        HStack(spacing: DomesticActivityTableMetrics.groupSpacing) {
            HStack(spacing: DomesticActivityTableMetrics.columnSpacing) {
                HStack(spacing: 6) {
                    Circle()
                        .fill(exchangeMarkerColor)
                        .frame(width: 7, height: 7)
                    Text(exchange.label)
                        .font(.system(size: CatoshiType.table, weight: .medium))
                        .lineLimit(1)
                }
                .frame(width: DomesticActivityTableMetrics.exchange, alignment: .leading)

                HStack(spacing: 4) {
                    Group {
                        switch dataState {
                        case .maintenance:
                            Image(systemName: "wrench.adjustable.fill")
                        case .unavailable:
                            Image(systemName: "exclamationmark.circle.fill")
                        case .unknown, .available:
                            Text(level.symbol)
                        }
                    }
                        .font(.system(size: CatoshiType.metadata, weight: .bold))
                        .frame(width: 11, alignment: .center)
                    Text(statusText)
                        .font(.system(size: CatoshiType.table, weight: level == .surging ? .semibold : .medium))
                        .lineLimit(1)
                        .minimumScaleFactor(0.90)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .foregroundStyle(indicatorColor)
                .frame(width: DomesticActivityTableMetrics.state, alignment: .leading)
            }
            .frame(width: DomesticActivityTableMetrics.identityGroup, alignment: .leading)

            HStack(spacing: DomesticActivityTableMetrics.columnSpacing) {
                Text(ratioText)
                    .font(.system(size: CatoshiType.table, weight: .medium))
                    .monospacedDigit()
                    .frame(width: DomesticActivityTableMetrics.activity, alignment: .trailing)

                Text(shareText)
                    .font(.system(size: CatoshiType.table, weight: .medium))
                    .monospacedDigit()
                    .foregroundStyle(shareColor)
                    .frame(width: DomesticActivityTableMetrics.relativeShare, alignment: .trailing)
            }
            .frame(width: DomesticActivityTableMetrics.radarGroup, alignment: .trailing)

            HStack(spacing: DomesticActivityTableMetrics.columnSpacing) {
                Text(volumeShareText)
                    .font(.system(size: CatoshiType.table, weight: .semibold))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.90)
                    .frame(width: DomesticActivityTableMetrics.volumeShare, alignment: .trailing)

                Text(volumeValueText)
                    .font(.system(size: CatoshiType.table))
                    .monospacedDigit()
                    .catoshiText(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.90)
                    .frame(width: DomesticActivityTableMetrics.volumeValue, alignment: .trailing)
            }
            .frame(width: DomesticActivityTableMetrics.volume24h, alignment: .trailing)
        }
        .frame(minHeight: 32)
        .help(rowHelpText)
    }

    private var rowHelpText: String {
        switch dataState {
        case .maintenance:
            return language.pick(
                "거래소 응답 또는 공식 공개 상태 필드에서 점검을 확인했습니다.",
                "Maintenance was confirmed from the exchange response or an official public status field."
            )
        case .unavailable:
            return language.pick(
                "최신 데이터를 받지 못했습니다. 점검 근거가 확인되지 않아 '점검 중'으로 단정하지 않습니다.",
                "Fresh data was not received. Catoshi does not label it maintenance without explicit evidence."
            )
        case .unknown, .available:
            return ""
        }
    }
}

