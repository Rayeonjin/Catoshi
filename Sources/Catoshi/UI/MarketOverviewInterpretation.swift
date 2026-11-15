import Foundation

/// Descriptive regimes, not a forecast. Korean and English share the same rules.
struct MarketRegimeRead {
    let title: String
    let summary: String
    let decision: String
    let reversal: String
    let alignment: String
    let tone: MarketReadTone

    init(macro: MacroMarketSnapshot, fast: FastMarketSnapshot?, btcChange24h: Double?, language: AppLanguage) {
        let btc = metricTrend(macro.btcDominanceChange24hPP, threshold: 0.15)
        let usdt = metricTrend(macro.usdtDominanceChange24hPP, threshold: 0.10)
        let breadth = metricTrend(macro.total3Change24h, threshold: 0.75)
        let eth = metricTrend(fast?.ethBTCChange24h, threshold: 0.50)
        let pick = language.pick

        switch (usdt, breadth) {
        case (.down, .up):
            if btc == .up {
                title = pick("BTC 우위·시장 동반 확대", "BTC leads a broader expansion")
            } else if btc == .down {
                title = pick("알트 순환 우세", "Alt rotation leads")
            } else if eth == .up {
                title = pick("ETH 상대강세·시장 확대", "ETH strength with expansion")
            } else {
                title = pick("시장 확대·주도권 분산", "Expansion with mixed leadership")
            }
            summary = pick("USDT 비중은 낮아지고 BTC·ETH 제외 시총은 늘었습니다. 시장 확대 조합이지만 실제 자금 유입액이나 개별 알트의 동반 상승을 뜻하지는 않습니다.", "USDT share is falling and ex-BTC/ETH market cap is growing. This fits expansion, but does not measure cash inflows or prove that individual alts are rising together.")
            decision = pick("BTC.D는 누가 상대적으로 강한지, TOTAL3*는 시장 규모가 커지는지로 나눠 읽습니다. ETH/BTC와 BTC 실제 가격까지 같은 해석을 지지하는지 확인합니다.", "Use BTC.D for relative leadership and TOTAL3* for market size. Check whether ETH/BTC and BTC's actual price support the same interpretation.")
            reversal = pick("USDT.D가 +0.10%p를 넘게 오르거나 TOTAL3*가 -0.75% 아래로 내려가면 확대 해석을 다시 봅니다.", "Reassess expansion if USDT.D rises beyond +0.10pp or TOTAL3* falls below -0.75%.")
            alignment = pick("확대 조합", "Expansion mix")
            tone = (btcChange24h.map { $0 < -0.5 } ?? false) ? .caution : .constructive
        case (.up, .down):
            title = btc == .down ? pick("시장 위축·BTC도 상대 약세", "Contraction with relative BTC weakness") : pick("시장 위축·BTC 상대 방어", "Contraction, BTC relatively resilient")
            summary = pick("USDT 비중 상승과 BTC·ETH 제외 시총 감소가 겹칩니다. BTC.D가 오르더라도 BTC 가격 상승이 아니라 다른 자산보다 덜 약한 결과일 수 있습니다.", "Rising USDT share coincides with shrinking ex-BTC/ETH market cap. Higher BTC.D may mean relative resilience rather than a rising BTC price.")
            decision = pick("시장 규모 축소를 먼저 봅니다. BTC.D 하락도 알트 강세로 단정하지 않고, BTC 실제 가격·TOTAL3*·스테이블 공급을 함께 확인합니다.", "Read market contraction first. Falling BTC.D is not enough to establish alt strength; compare actual BTC price, TOTAL3* and stablecoin supply.")
            reversal = pick("TOTAL3*가 +0.75%를 넘고 USDT.D가 -0.10%p 아래로 내려가면 위축 완화를 다시 평가합니다.", "Reassess contraction if TOTAL3* rises beyond +0.75% and USDT.D falls below -0.10pp.")
            alignment = pick("위축 조합", "Contraction mix")
            tone = btc == .down ? .riskOff : .caution
        case (.up, .up):
            title = pick("시총 확대·방어 비중 동반 상승", "Expansion with rising stable share")
            summary = pick("BTC·ETH 제외 시총과 USDT 비중이 함께 늘었습니다. 시장 규모는 커지지만 방어 비중도 높아져, 일방적인 위험선호로 묶기 어렵습니다.", "Ex-BTC/ETH market cap and USDT share are both rising. Market size is expanding, but the stablecoin share is also rising, so this is not a clean risk-on mix.")
            decision = pick("스테이블 공급 증가가 USDT.D를 끌어올린 것인지, 일부 자산에만 강세가 집중된 것인지 구분합니다. ETH/BTC와 BTC 가격으로 상대강도를 보완합니다.", "Check whether growing stablecoin supply explains higher USDT.D or strength is concentrated in a few assets. Use ETH/BTC and BTC price for relative context.")
            reversal = pick("TOTAL3* 확대가 이어지며 USDT.D가 하락하면 확대 쪽, TOTAL3*까지 하락하면 위축 쪽으로 읽습니다.", "Continued TOTAL3* expansion with falling USDT.D favors expansion; falling TOTAL3* favors contraction.")
            alignment = pick("신호 엇갈림", "Conflicting signals")
            tone = .neutral
        case (.down, .down):
            title = pick("USDT 비중 하락·알트 시총 축소", "Falling stable share, shrinking alts")
            summary = pick("USDT 비중은 낮아졌지만 BTC·ETH 제외 시총도 줄었습니다. USDT.D 하락만으로 시장 전반에 자금이 들어온다고 보기 어렵습니다.", "USDT share is falling, but ex-BTC/ETH market cap is also shrinking. Lower USDT.D alone cannot establish a market-wide inflow.")
            decision = pick("BTC·ETH 집중이나 스테이블 공급 감소 가능성을 함께 봅니다. TOTAL3*가 회복되기 전에는 알트 확산으로 해석하지 않습니다.", "Check for concentration in BTC/ETH or shrinking stablecoin supply. Do not infer alt expansion before TOTAL3* recovers.")
            reversal = pick("TOTAL3*가 +0.75%를 넘게 회복하면 확대 가능성을, USDT.D까지 상승하면 방어적 위축을 다시 확인합니다.", "TOTAL3* recovering beyond +0.75% supports expansion; rising USDT.D would instead reinforce a defensive contraction.")
            alignment = pick("신호 엇갈림", "Conflicting signals")
            tone = .caution
        case (_, .up):
            title = pick("알트 시총 확대·유동성 확인 중", "Alt cap expanding, liquidity unconfirmed")
            summary = pick("BTC·ETH 제외 시총은 늘었지만 USDT 비중 변화는 제한적입니다. 시장 규모 확대는 보이되 유동성 신호의 확인은 남아 있습니다.", "Ex-BTC/ETH market cap is growing while USDT share changes little. Expansion is visible, but the liquidity signal remains unconfirmed.")
            decision = pick("TOTAL3* 확대를 먼저 확인하되 BTC.D와 ETH/BTC로 상대 주도권을 구분합니다. 시총 합계만으로 상승 종목 수가 늘었다고 단정하지 않습니다.", "Recognize TOTAL3* expansion and use BTC.D and ETH/BTC to identify relative leadership. Aggregate cap does not establish how many coins are rising.")
            reversal = pick("USDT.D가 -0.10%p 아래로 내려가면 확대 조합이 강화되고, TOTAL3*가 정체·하락하면 확대 해석이 약해집니다.", "USDT.D below -0.10pp strengthens the expansion mix; flat or falling TOTAL3* weakens it.")
            alignment = pick("일부 확인", "Partial confirmation")
            tone = .neutral
        case (_, .down):
            title = pick("알트 시총 축소·확산 약화", "Alt cap shrinking, expansion weak")
            summary = pick("BTC·ETH 제외 시총이 줄고 USDT 비중은 큰 변화가 없습니다. 알트 시장 규모는 약하지만 자금 이탈 여부까지 확정할 수는 없습니다.", "Ex-BTC/ETH market cap is shrinking while USDT share is broadly flat. Alt market size is weak, but this does not establish cash outflows.")
            decision = pick("BTC.D가 높아져도 상대 방어인지 실제 BTC 상승인지 나눠 봅니다. ETH/BTC와 BTC 가격이 함께 약한지도 확인합니다.", "Separate relative BTC resilience from actual BTC price gains. Check whether ETH/BTC and BTC price are also weak.")
            reversal = pick("TOTAL3*가 +0.75%를 넘게 회복하는지, USDT.D 상승으로 위축 조합이 강화되는지 확인합니다.", "Watch for TOTAL3* recovering beyond +0.75% or rising USDT.D reinforcing contraction.")
            alignment = pick("축소 우세", "Contraction leaning")
            tone = .caution
        case (.up, _):
            title = pick("방어 비중 확대·알트 정체", "Stable share rising, alts flat")
            summary = pick("USDT 비중은 높아지지만 BTC·ETH 제외 시총 변화는 제한적입니다. 방어 비중 확대와 대기성 공급 증가를 구분해야 합니다.", "USDT share is rising while ex-BTC/ETH market cap changes little. Distinguish defensive weighting from an increase in stablecoin supply.")
            decision = pick("USDT+USDC 공급 증가 여부와 BTC 실제 가격을 함께 봅니다. USDT.D 상승만으로 매도나 시장 이탈을 확정하지 않습니다.", "Compare USDT+USDC supply and actual BTC price. Higher USDT.D alone does not prove selling or capital leaving the market.")
            reversal = pick("TOTAL3*가 -0.75% 아래로 내려가면 위축을, USDT.D 하락과 TOTAL3* 상승이 겹치면 확대를 다시 평가합니다.", "TOTAL3* below -0.75% supports contraction; falling USDT.D with rising TOTAL3* supports expansion.")
            alignment = pick("방어 기울기", "Defensive leaning")
            tone = .caution
        case (.down, _):
            title = btc == .up ? pick("BTC 상대 우위·알트 정체", "BTC relatively stronger, alts flat") : pick("USDT 비중 하락·확산 대기", "Stable share falling, expansion pending")
            summary = pick("USDT 비중은 낮아졌지만 BTC·ETH 제외 시총은 아직 뚜렷하게 늘지 않았습니다. 시장 전반의 확대보다는 상대 비중 변화로 먼저 읽습니다.", "USDT share is falling, but ex-BTC/ETH market cap has not clearly expanded. Read this first as a relative-share shift rather than broad expansion.")
            decision = pick("BTC.D 상승이 실제 BTC 가격 상승과 동행하는지 확인합니다. 알트 확산은 TOTAL3*와 ETH/BTC의 후속 확인이 필요합니다.", "Check whether rising BTC.D accompanies an actual BTC price gain. Alt expansion needs follow-through in TOTAL3* and ETH/BTC.")
            reversal = pick("TOTAL3*가 +0.75%를 넘으면 확대 해석을 보강하고, USDT.D가 상승하면 방어 비중 확대를 다시 봅니다.", "TOTAL3* beyond +0.75% supports expansion; rising USDT.D calls for a renewed defensive read.")
            alignment = pick("확산 미확인", "Expansion unconfirmed")
            tone = .neutral
        default:
            title = btc == .up ? pick("변화 제한·BTC 비중 상승", "Limited change, BTC share rising") : btc == .down ? pick("변화 제한·BTC 비중 하락", "Limited change, BTC share falling") : pick("방향 대기·변화 제한", "Direction pending, limited change")
            summary = pick("USDT 비중과 BTC·ETH 제외 시총 변화가 모두 중립 범위입니다. 뚜렷한 신호 충돌보다 주요 변화폭이 아직 작은 상태입니다.", "USDT share and ex-BTC/ETH market-cap changes are both inside neutral ranges. This reflects limited movement rather than necessarily conflicting signals.")
            decision = pick("BTC.D·ETH/BTC로 상대 주도권을 보되 작은 변화만으로 국면 전환을 단정하지 않습니다. 가격·현물 수요·중기 추세의 보조 근거를 함께 확인합니다.", "Use BTC.D and ETH/BTC for relative leadership without calling a regime change from small moves. Check price, spot demand and the medium-term trend for context.")
            reversal = pick("USDT.D ±0.10%p, TOTAL3* ±0.75% 범위를 벗어나는 조합이 나타나면 국면을 다시 평가합니다.", "Reassess when the combination moves outside USDT.D ±0.10pp and TOTAL3* ±0.75% neutral ranges.")
            alignment = pick("변화 제한", "Limited movement")
            tone = .neutral
        }
    }
}

struct MarketOverviewRead {
    let summary: String
    let supporting: [String]
    let cautions: [String]
    let coverage: String
    let limitations: String

    init(macro: MacroMarketSnapshot, fast: FastMarketSnapshot?, investor: InvestorMarketSnapshot?,
         premium: PremiumSnapshot?, btcChange24h: Double?, language: AppLanguage) {
        let pick = language.pick
        summary = MarketRegimeRead(macro: macro, fast: fast, btcChange24h: btcChange24h, language: language).summary
        var support: [String] = []
        var caution: [String] = []
        let total3 = macro.total3Change24h ?? 0
        let usdt = macro.usdtDominanceChange24hPP ?? 0
        let btc = macro.btcDominanceChange24hPP ?? 0
        // Values explain today's observation; a neutral or missing value is never confirmation.
        if total3 > 0.75 {
            support.append(pick("TOTAL3* 24h \(signedMetric(total3))%: BTC·ETH 제외 시총 확대.", "TOTAL3* 24h \(signedMetric(total3))%: ex-BTC/ETH cap expands."))
        } else if total3 < -0.75 {
            caution.append(pick("TOTAL3* 24h \(signedMetric(total3))%: BTC·ETH 제외 시장 규모 축소.", "TOTAL3* 24h \(signedMetric(total3))%: ex-BTC/ETH market cap contracts."))
        }
        if usdt < -0.10 {
            support.append(pick("USDT.D 24h \(signedMetric(usdt))%p: 스테이블 상대 비중 하락. 신규 유입액은 미확인.", "USDT.D 24h \(signedMetric(usdt))pp: lower stable share; fresh inflows are unconfirmed."))
        } else if usdt > 0.10 {
            caution.append(pick("USDT.D 24h \(signedMetric(usdt))%p: 방어 비중 상승. 공급 증가 가능성도 확인.", "USDT.D 24h \(signedMetric(usdt))pp: stable share rises; check supply growth too."))
        }
        if let day = btcChange24h, day < -0.5 {
            caution.append(pick("BTC 24h \(signedMetric(day))%: \(btc > 0.15 ? "도미넌스 상승도 가격 강세를 뜻하지 않습니다." : "짧은 반등만으로 회복을 확정하기 어렵습니다.")", "BTC 24h \(signedMetric(day))%: \(btc > 0.15 ? "higher dominance does not mean price strength." : "a brief bounce does not establish recovery.")"))
        }
        if let etf = investor?.etfFiveDayFlowUSD {
            if etf >= 100_000_000 {
                support.append(pick("미국 BTC ETF 5거래일 \(formatSignedUSDFlow(etf)): 해당 ETF의 순유입.", "US BTC ETF 5 sessions \(formatSignedUSDFlow(etf)): net inflows in this segment."))
            } else if etf <= -100_000_000 {
                caution.append(pick("미국 BTC ETF 5거래일 \(formatSignedUSDFlow(etf)): 해당 ETF의 순유출.", "US BTC ETF 5 sessions \(formatSignedUSDFlow(etf)): net outflows in this segment."))
            }
        }
        if let stable = investor?.stablecoinSupplyChange7d {
            if stable >= 0.5 {
                support.append(pick("USDT+USDC 7D \(signedMetric(stable))%: 공급 확대. 코인 매수에 쓰였는지는 별도입니다.", "USDT+USDC 7D \(signedMetric(stable))%: supply expands; use for crypto buying is unconfirmed."))
            } else if stable <= -0.5 {
                caution.append(pick("USDT+USDC 7D \(signedMetric(stable))%: 공급 감소로 유동성 해석에 제약.", "USDT+USDC 7D \(signedMetric(stable))%: shrinking supply limits the liquidity read."))
            }
        }
        if let oi = fast?.openInterestChange1h, let funding = fast?.fundingRatePercent,
           (oi >= 5 && abs(funding) >= 0.05) || abs(funding) >= 0.10 {
            // Put material positioning risk first, even if the price regime is constructive.
            caution.insert(pick("OI 1h \(signedMetric(oi))% · Funding \(String(format: "%+.3f%%", funding)): 포지션 쏠림 주의. 방향 확정 신호는 아닙니다.", "OI 1h \(signedMetric(oi))% · Funding \(String(format: "%+.3f%%", funding)): positioning risk, not a directional confirmation."), at: 0)
        } else if let funding = fast?.fundingRatePercent, abs(funding) >= 0.10 {
            caution.insert(pick("Funding \(String(format: "%+.3f%%", funding)): 펀딩 편향이 큽니다. OI가 없어 포지션 증가 여부는 미확인입니다.", "Funding \(String(format: "%+.3f%%", funding)): large funding bias; OI is unavailable, so position growth is unconfirmed."), at: 0)
        }
        if let premium = premium?.value, premium >= 5 {
            caution.insert(pick("김프 \(signedMetric(premium))%: 국내 가격 괴리 확대. 글로벌 추세의 확인 근거와 구분합니다.", "Kimchi \(signedMetric(premium))%: larger domestic price gap; separate it from global trend confirmation."), at: 0)
        }
        if let ret = investor?.btcReturn30d, let above = investor?.btcAbove200DMA {
            if above, ret >= 5 {
                support.append(pick("BTC 30D \(signedMetric(ret))% · 200DMA 위: 중기 상승 구조.", "BTC 30D \(signedMetric(ret))% · above 200DMA: constructive medium-term structure."))
            } else if !above, ret <= -5 {
                caution.append(pick("BTC 30D \(signedMetric(ret))% · 200DMA 아래: 중기 약세와 단기 신호 구분.", "BTC 30D \(signedMetric(ret))% · below 200DMA: separate short-term signals from medium-term weakness."))
            }
        }
        supporting = support
        cautions = caution
        var missing: [String] = []
        if fast == nil { missing.append("ETH/BTC") }
        if investor?.stablecoinSupplyChange7d == nil { missing.append(pick("스테이블 공급", "Stable supply")) }
        if investor?.etfFiveDayFlowUSD == nil { missing.append("ETF") }
        if investor?.btcReturn7d == nil || investor?.btcReturn30d == nil || investor?.btcAbove200DMA == nil { missing.append(pick("중기 추세", "Medium trend")) }
        if fast?.openInterestChange1h == nil || fast?.fundingRatePercent == nil { missing.append("OI/Funding") }
        if premium == nil { missing.append(pick("김프", "Kimchi")) }
        if btcChange24h == nil { missing.append(pick("BTC 가격", "BTC price")) }
        coverage = missing.isEmpty
            ? pick("핵심·보조 지표 수신 완료 · 해석의 적중률을 뜻하지 않습니다.", "Core and auxiliary inputs available; this is not forecast accuracy.")
            : pick("판단 미반영: ", "Not included: ") + missing.joined(separator: " · ") + pick(" — 미수신·오래됨·실패는 중립으로 세지 않습니다.", " — unavailable, stale or failed data does not count as neutral.")
        limitations = pick("24h 구조와 1h OI·5m 가격·7D 공급·ETF 5거래일은 관측 기간이 다릅니다. TOTAL3*는 CoinGecko 전체 시총−BTC−ETH 추정치로 스테이블을 포함하며, 상승 종목 수나 순유입액을 측정하지 않습니다. 기준: BTC.D ±0.15%p · USDT.D ±0.10%p · TOTAL3* ±0.75% · ETH/BTC ±0.50% 이내는 중립입니다.", "24h structure, 1h OI, 5m price, 7D supply and 5-session ETF flows cover different periods. TOTAL3* estimates CoinGecko total cap minus BTC and ETH, includes stablecoins, and does not measure advancing coins or net inflows. Neutral bands: BTC.D ±0.15pp, USDT.D ±0.10pp, TOTAL3* ±0.75%, ETH/BTC ±0.50%.")
    }
}
