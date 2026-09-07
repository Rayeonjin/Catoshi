import Foundation
import SwiftUI

func marketReadAccent(_ tone: MarketReadTone, palette: DisplayPalette) -> Color {
    guard palette == .color else { return .primary }
    switch tone {
    case .constructive: return .green
    case .caution: return .orange
    case .riskOff: return .red
    case .neutral: return .secondary
    }
}

func makeMarketRead(
    macro: MacroMarketSnapshot?,
    fast: FastMarketSnapshot?,
    investor: InvestorMarketSnapshot?,
    freshness: MarketContextFreshness,
    premium: PremiumSnapshot?,
    btcChange24h: Double?,
    btcChange5m: Double?,
    language: AppLanguage,
    btcUpdatedAt: Date? = nil,
    premiumUpdatedAt: Date? = nil,
    now: Date = Date()
) -> MarketRead {
    let inputs = MarketInterpretationInputs(macro: macro, fast: fast, investor: investor, freshness: freshness, now: now)
    let priceIsCurrent = btcUpdatedAt.map { MarketRefreshState.isCurrent($0, maximumAge: 180, now: now) } ?? false
    let premiumIsCurrent = premiumUpdatedAt.map { MarketRefreshState.isCurrent($0, maximumAge: 180, now: now) } ?? false
    let result: MarketRead
    if language == .english {
        result = makeMarketReadEnglish(
            macro: inputs.macro, fast: inputs.fast, investor: inputs.investor,
            premium: premiumIsCurrent ? premium : nil,
            btcChange24h: priceIsCurrent ? btcChange24h : nil,
            btcChange5m: priceIsCurrent ? btcChange5m : nil
        )
    } else {
        result = makeMarketReadKorean(
            macro: inputs.macro, fast: inputs.fast, investor: inputs.investor,
            premium: premiumIsCurrent ? premium : nil,
            btcChange24h: priceIsCurrent ? btcChange24h : nil,
            btcChange5m: priceIsCurrent ? btcChange5m : nil
        )
    }
    if inputs.macro == nil, macro != nil || freshness.macro.lastFailureAt != nil {
        return MarketRead(
            title: language.pick("시장 해석 보류", "Market read paused"),
            summary: language.pick(
                "매크로 데이터가 오래됐거나 갱신에 실패했거나 일부 변화율이 누락되었습니다. 정상 데이터를 받은 뒤 시장 해석을 다시 제공합니다.",
                "Macro data is stale, failed to refresh, or is missing required changes. The market read resumes after valid data arrives."),
            decision: language.pick("마지막 수치는 참고용으로만 표시합니다.", "Retained numbers are historical reference only."),
            reversal: language.pick("출처별 상태와 마지막 수신 시각을 확인하세요.", "Check each source status and last received time."),
            basis: result.basis,
            alignment: language.pick("해석 보류", "Read paused"),
            dimensions: result.dimensions,
            tone: .neutral,
            badges: [language.pick("갱신 필요", "Refresh needed")]
        )
    }
    let hasExcludedContext = (fast != nil && inputs.fast == nil) || (investor != nil && inputs.investor == nil)
        || freshness.fast.lastFailureAt != nil || freshness.investor.lastFailureAt != nil
        || (investor?.etfFiveDayFlowUSD != nil && inputs.investor?.etfFiveDayFlowUSD == nil)
    guard hasExcludedContext else { return result }
    return MarketRead(
        title: result.title,
        summary: result.summary + language.pick(" 오래되었거나 수신에 실패한 보조 지표는 해석에서 제외했습니다.", " Stale or failed auxiliary indicators are excluded from this read."),
        decision: result.decision, reversal: result.reversal, basis: result.basis,
        alignment: result.alignment + language.pick(" · 일부 지표 제외", " · Some inputs excluded"),
        dimensions: result.dimensions, tone: result.tone,
        badges: result.badges + [language.pick("일부 지표 제외", "Some inputs excluded")]
    )
}

private func makeMarketReadKorean(
    macro: MacroMarketSnapshot?,
    fast: FastMarketSnapshot?,
    investor: InvestorMarketSnapshot?,
    premium: PremiumSnapshot?,
    btcChange24h: Double?,
    btcChange5m: Double?
) -> MarketRead {
    guard let macro else {
        return MarketRead(
            title: "시장 맥락 계산 중",
            summary: "도미넌스와 시가총액 데이터를 기다리고 있습니다. 핵심 데이터가 모이면 자금·주도권·현물수요·중기 추세·레버리지·국내 심리를 분리해서 해석합니다.",
            decision: "현재는 데이터가 충분하지 않아 방향성 판단을 유보하는 편이 낫습니다.",
            reversal: "시장 탭을 연 상태에서 매크로 데이터가 갱신되면 자동으로 해석합니다.",
            basis: "BTC.D · USDT.D · TOTAL3* 데이터 대기",
            alignment: "데이터 대기",
            dimensions: [
                MarketReadDimension(id: "flow", label: "자금", signal: "대기", explanation: "USDT.D와 전체 시총 데이터를 기다리고 있습니다."),
                MarketReadDimension(id: "lead", label: "주도권", signal: "대기", explanation: "BTC.D·TOTAL3·ETH/BTC가 모이면 BTC와 알트의 상대강도를 비교합니다."),
                MarketReadDimension(id: "lev", label: "레버리지", signal: "대기", explanation: "OI와 Funding을 기다리고 있습니다."),
                MarketReadDimension(id: "spot", label: "현물 수요", signal: "대기", explanation: "ETF 흐름 데이터를 기다리고 있습니다."),
                MarketReadDimension(id: "trend", label: "중기 추세", signal: "대기", explanation: "7D·30D·200DMA 데이터를 기다리고 있습니다."),
                MarketReadDimension(id: "retail", label: "국내 심리", signal: "대기", explanation: "김치프리미엄 데이터가 들어오면 국내 과열도를 함께 봅니다.")
            ],
            tone: .neutral,
            badges: []
        )
    }

    let btc = metricTrend(macro.btcDominanceChange24hPP, threshold: 0.15)
    let usdt = metricTrend(macro.usdtDominanceChange24hPP, threshold: 0.10)
    let total3 = metricTrend(macro.total3Change24h, threshold: 0.75)
    let eth = metricTrend(fast?.ethBTCChange24h, threshold: 0.50)

    var title = "혼조·전환 구간"
    var summary = "주도권과 유동성 신호가 한 방향으로 정렬되지 않았습니다. 이런 구간에서는 BTC.D 한 가지보다 USDT.D와 TOTAL3가 어느 쪽으로 정렬되는지 기다리는 편이 해석 오류를 줄입니다."
    var decision = "방향을 강하게 단정하기보다 자금 흐름과 시장 폭이 같은 방향으로 확인되는지를 우선 보세요. 혼조 구간에서는 짧은 가격 움직임을 큰 추세 전환으로 확대 해석하기 쉽습니다."
    var reversal = "USDT.D와 TOTAL3가 반대 방향이 아니라 같은 시장 국면을 가리키기 시작하는지 확인합니다."
    var tone: MarketReadTone = .neutral
    var badges: [String] = []
    var aligned = 1
    let alignmentTotal = 4

    if btc == .down, usdt == .down, total3 == .up {
        title = "알트 순환 강화"
        summary = "BTC 비중과 USDT 비중이 함께 낮아지는 가운데 BTC·ETH 제외 시총이 커지고 있습니다. BTC가 약해서 도미넌스만 떨어지는 장면보다, 실제로 알트 시장의 파이가 커지는 쪽에 더 가까운 조합입니다."
        decision = "알트 강세를 판단할 때 BTC.D 하락 자체보다 TOTAL3 확대를 더 중요하게 봅니다. ETH/BTC까지 상승하면 대형 알트의 상대강도도 확인되는 만큼 순환의 질이 한 단계 좋아집니다."
        reversal = "USDT.D가 다시 상승하거나 TOTAL3가 하락 전환하면 알트 순환 해석이 약해집니다. ETH/BTC까지 꺾이면 확산 동력이 약해졌는지 재확인합니다."
        tone = .constructive
        badges.append("알트 순환")
        aligned = 3 + (eth == .up ? 1 : 0)
    } else if btc == .up, usdt == .down {
        title = "BTC 주도 위험선호"
        summary = "BTC의 상대 점유율은 높아지고 USDT 비중은 낮아지고 있습니다. 시장 내 위험자산 배치가 늘어나는 가운데 그 수요가 우선 BTC에 집중되는 흐름과 부합합니다."
        decision = "현재는 '시장 전체가 강하다'보다 'BTC가 시장을 주도한다'는 해석에 무게를 둡니다. TOTAL3와 ETH/BTC가 뒤따라 오르기 전에는 BTC 강세를 알트 전반의 강세로 확대 해석하지 않는 편이 안전합니다."
        reversal = "BTC.D가 꺾이고 TOTAL3·ETH/BTC가 동시에 상승하면 BTC 집중에서 알트 순환으로 주도권이 이동하는지 다시 봅니다."
        tone = .constructive
        badges.append("BTC 주도")
        aligned = 2 + ((total3 == .flat || total3 == .down) ? 1 : 0) + ((eth == .flat || eth == .down) ? 1 : 0)
    } else if btc == .down, usdt == .up {
        title = "위험회피·자금 이탈"
        summary = "BTC 비중은 낮아지는데 USDT 비중은 높아지고 있습니다. 건강한 알트 순환보다는 코인 시장의 위험 노출을 줄이고 스테이블코인 비중을 높이는 방어적 흐름에 더 가깝습니다."
        decision = "BTC.D 하락을 알트 강세로 오해하기 쉬운 조합입니다. 이때는 TOTAL3가 실제로 성장하는지보다 감소하는지를 먼저 확인하고, USDT.D가 꺾이기 전까지 위험선호 회복을 성급히 가정하지 않는 편이 좋습니다."
        reversal = "USDT.D가 하락 전환하고 TOTAL3가 회복되면 자금 이탈 압력이 완화되는 첫 신호로 볼 수 있습니다."
        tone = .riskOff
        badges.append("위험회피")
        aligned = 2 + (total3 == .down ? 1 : 0) + (eth == .down ? 1 : 0)
    } else if btc == .flat, eth == .up, total3 == .up {
        title = "ETH 주도 순환"
        summary = "BTC 점유율은 큰 변화가 없지만 ETH/BTC와 TOTAL3가 함께 상승하고 있습니다. BTC에서 대형 알트로 상대강도가 확산되면서 알트 시장의 체력도 같이 좋아지는 흐름입니다."
        decision = "ETH/BTC 상승만 볼 때보다 TOTAL3 상승이 동반되는지를 중요하게 봅니다. 둘이 함께 오르면 특정 종목의 상대강세가 아니라 시장 폭이 넓어지는 순환으로 해석할 근거가 더 많아집니다."
        reversal = "ETH/BTC 상승이 멈추거나 TOTAL3가 하락하면 대형 알트 주도 순환이 약해지는지 확인합니다. USDT.D 상승까지 겹치면 방어적으로 다시 읽어야 합니다."
        tone = .constructive
        badges.append("ETH 주도")
        aligned = 3 + (usdt != .up ? 1 : 0)
    }

    var basisParts = [
        "BTC.D \(btc.rawValue)",
        "USDT.D \(usdt.rawValue)",
        "TOTAL3 \(total3.rawValue)"
    ]
    if eth != .unknown { basisParts.append("ETH/BTC \(eth.rawValue)") }

    if let btcChange24h {
        basisParts.append(String(format: "BTC 24h %+.1f%%", btcChange24h))
    }
    if let btcChange5m {
        basisParts.append(String(format: "5m %+.2f%%", btcChange5m))
    }

    if let stable7d = investor?.stablecoinSupplyChange7d {
        basisParts.append(String(format: "Stables 7D %+.2f%%", stable7d))
        if stable7d >= 0.50 {
            badges.append("유동성 확대")
            if usdt == .down {
                summary += " USDT.D가 낮아지는 동안 USDT+USDC 공급도 7일 기준 늘어, 단순한 시가총액 분모 효과보다 실제 스테이블 유동성 기반 확대가 동반되는 쪽에 무게가 실립니다."
                decision += " 자금 유입을 판단할 때는 USDT.D 하락만 보지 말고 스테이블 공급 증가가 계속되는지 확인하면 해석의 신뢰도가 높아집니다."
            } else if usdt == .up {
                summary += " USDT+USDC 공급은 늘었지만 USDT.D도 높아지는 모습이라, 새 유동성이 들어와도 아직 위험자산으로 충분히 배치되지 않고 대기 중일 가능성을 함께 봅니다."
                reversal += " USDT.D가 하락으로 돌아서면 대기성 스테이블 유동성이 위험자산으로 이동하는지 확인합니다."
            }
        } else if stable7d <= -0.50 {
            badges.append("유동성 축소")
            if usdt == .down {
                summary += " 다만 USDT+USDC 공급 자체는 7일 기준 줄고 있어 USDT.D 하락을 신규 자금 유입으로 곧바로 해석하기 어렵습니다."
                decision += " 이 경우 도미넌스 하락보다 TOTAL3와 실제 가격의 지속성을 우선 확인하는 편이 낫습니다."
            } else {
                summary += " USDT+USDC 공급이 7일 기준 감소해 시장 바깥으로 스테이블 유동성이 줄어드는 압력도 확인됩니다."
            }
            if tone == .constructive || tone == .neutral { tone = .caution }
        }
    }

    if let etf5d = investor?.etfFiveDayFlowUSD {
        basisParts.append("ETF 5D " + formatSignedUSDFlow(etf5d))
        if etf5d >= 500_000_000 {
            badges.append("ETF 순유입")
            summary += " 미국 현물 BTC ETF도 최근 5거래일 누적 순유입이 뚜렷해 BTC 현물 수요 측면의 버팀목이 확인됩니다."
            if btc == .up {
                decision += " BTC.D 상승이 ETF 순유입과 함께 나타나면 파생 레버리지에만 의존한 상승보다 현물 수요가 동반되는지에 더 높은 점수를 줄 수 있습니다."
            }
        } else if etf5d <= -500_000_000 {
            badges.append("ETF 순유출")
            summary += " 반면 미국 현물 BTC ETF는 최근 5거래일 누적 순유출이 커 현물 기관성 수요는 가격 흐름을 충분히 지지하지 못하고 있습니다."
            decision += " 가격이 오르더라도 ETF 순유출이 계속되면 상승의 질이 약한지, OI 증가로 레버리지가 대신 채우고 있는지 함께 확인합니다."
            if tone == .constructive || tone == .neutral { tone = .caution }
        }
    }

    if let ret30 = investor?.btcReturn30d, let above200 = investor?.btcAbove200DMA {
        basisParts.append(String(format: "BTC 30D %+.1f%%", ret30))
        basisParts.append(above200 ? "200DMA 위" : "200DMA 아래")
        if above200, ret30 >= 5.0 {
            badges.append("중기 상승")
            summary += " BTC는 200일 이동평균 위에 있고 30일 수익률도 양호해 현재 단기 신호가 중기 상승 구조 안에서 발생하고 있습니다."
            decision += " 이런 구조에서는 단기 조정과 중기 추세 훼손을 구분해 읽는 것이 중요하며, 200DMA 이탈과 30일 모멘텀 약화를 함께 확인합니다."
        } else if !above200, ret30 <= -5.0 {
            badges.append("중기 약세")
            summary += " BTC가 200일 이동평균 아래에 있고 30일 수익률도 약해, 단기 반등이 나타나더라도 중기 약세 구조 안의 반등일 가능성을 먼저 염두에 둡니다."
            decision += " 단기 강세 신호만으로 추세 전환을 단정하지 말고 200DMA 회복과 30일 모멘텀 개선이 같이 나타나는지 확인합니다."
            if tone == .constructive || tone == .neutral { tone = .caution }
        } else {
            summary += " 200일선과 30일 모멘텀이 완전히 같은 방향으로 정렬되지 않아 중기 추세 확인은 아직 혼조입니다."
        }
    }

    if let oi = fast?.openInterestChange1h,
       let funding = fast?.fundingRatePercent,
       oi >= 5.0,
       funding >= 0.05 {
        badges.append("롱 과열")
        summary += " 여기에 OI가 빠르게 늘고 펀딩비도 높은 양수라 상승 방향과 별개로 롱 포지션의 밀집도가 높아진 상태입니다."
        decision += " 추세가 맞더라도 레버리지 청산이 작은 조정을 큰 변동으로 키울 수 있어, 이 구간에서는 방향보다 진입 가격과 손실 허용폭의 중요성이 커집니다."
        reversal += " OI 증가율 둔화와 Funding 정상화는 과열 완화 신호입니다."
        basisParts.append(String(format: "OI +%.1f%%/1h", oi))
        basisParts.append(String(format: "Funding +%.3f%%", funding))
        if tone == .constructive || tone == .neutral { tone = .caution }
    } else if let oi = fast?.openInterestChange1h,
              let funding = fast?.fundingRatePercent,
              oi >= 5.0,
              funding <= -0.05 {
        badges.append("숏 과밀")
        summary += " OI가 빠르게 늘면서 펀딩비가 큰 음수여서 숏 포지션이 한쪽으로 밀렸을 가능성이 있습니다."
        decision += " 현물 가격과 거래가 강해질 경우 숏 스퀴즈가 변동성을 확대할 수 있으므로 단순히 음의 펀딩을 약세로만 읽지 않습니다."
        reversal += " OI 감소 또는 Funding의 0 부근 복귀는 포지션 과밀 완화 신호입니다."
        basisParts.append(String(format: "OI +%.1f%%/1h", oi))
        basisParts.append(String(format: "Funding %.3f%%", funding))
        if tone == .neutral { tone = .caution }
    } else if let funding = fast?.fundingRatePercent, funding >= 0.10 {
        badges.append("Funding 과열")
        summary += " 펀딩비가 이례적으로 높은 양수여서 롱 쏠림을 별도 위험요인으로 봐야 합니다."
        decision += " 가격이 강하더라도 높은 Funding이 오래 유지되는지는 추격 판단의 위험도를 높이는 요소입니다."
        basisParts.append(String(format: "Funding +%.3f%%", funding))
        if tone == .constructive || tone == .neutral { tone = .caution }
    } else if let funding = fast?.fundingRatePercent, funding <= -0.10 {
        badges.append("Funding 음수")
        summary += " 펀딩비가 이례적으로 큰 음수여서 숏 쏠림 가능성이 높습니다."
        decision += " 음의 Funding 자체는 추가 하락 신호가 아니라 포지션 편향 신호이므로 현물 방향과 함께 읽습니다."
        basisParts.append(String(format: "Funding %.3f%%", funding))
        if tone == .neutral { tone = .caution }
    }

    if let kimchi = premium?.value, kimchi >= 7.0 {
        badges.append("국내 FOMO")
        summary += " 김치프리미엄이 7%를 넘어 국내 리테일 수요의 과열 가능성도 높습니다."
        decision += " 국내 과열이 글로벌 추세를 보증하지 않으므로 김프만으로 강세의 지속성을 확신하지 않습니다."
        reversal += " 김프가 빠르게 정상화되면 국내 FOMO가 식는지 확인합니다."
        basisParts.append(String(format: "김프 +%.1f%%", kimchi))
        if tone != .riskOff { tone = .caution }
    } else if let kimchi = premium?.value, kimchi >= 5.0 {
        badges.append("김프 상승")
        summary += " 김치프리미엄도 높은 편이라 국내 리테일 수요의 추가 과열 여부를 함께 확인할 필요가 있습니다."
        basisParts.append(String(format: "김프 +%.1f%%", kimchi))
        if tone == .constructive { tone = .caution }
    }

    let flowDimension: MarketReadDimension = {
        let stable = investor?.stablecoinSupplyChange7d
        if usdt == .down, let stable, stable >= 0.50 {
            return MarketReadDimension(id: "flow", label: "자금", signal: "유입 확인", explanation: String(format: "USDT.D는 하락하고 USDT+USDC 공급은 7D %+.2f%% 늘었습니다. 비중 하락과 실제 공급 확대가 함께 나타나 위험자산으로 이동 가능한 유동성 기반이 넓어지는 조합입니다.", stable))
        }
        if usdt == .down, let stable, stable <= -0.50 {
            return MarketReadDimension(id: "flow", label: "자금", signal: "착시 경계", explanation: String(format: "USDT.D는 하락하지만 USDT+USDC 공급도 7D %+.2f%% 줄었습니다. 신규 자금 유입보다 전체 시총 상승의 분모 효과일 수 있어 TOTAL3와 가격 지속성을 더 중요하게 봅니다.", stable))
        }
        if usdt == .up, let stable, stable >= 0.50 {
            return MarketReadDimension(id: "flow", label: "자금", signal: "대기자금↑", explanation: String(format: "USDT+USDC 공급은 7D %+.2f%% 늘었지만 USDT.D도 상승했습니다. 새 유동성이 생겼어도 아직 코인으로 배치되지 않고 스테이블 형태로 대기하는지 확인합니다.", stable))
        }
        if usdt == .up, let stable, stable <= -0.50 {
            return MarketReadDimension(id: "flow", label: "자금", signal: "방어·축소", explanation: String(format: "USDT.D는 상승하고 USDT+USDC 공급은 7D %+.2f%% 줄어 방어적 현금 비중 확대와 시장 유동성 축소가 동시에 나타나는 조합입니다.", stable))
        }
        switch usdt {
        case .down:
            return MarketReadDimension(id: "flow", label: "자금", signal: "위험선호 쪽", explanation: "USDT.D가 24h 하락했습니다. 스테이블 비중 감소는 위험자산 배치와 부합하지만, Stablecoin Supply가 크게 늘지 않았다면 분모 효과 가능성도 남아 있습니다.")
        case .up:
            return MarketReadDimension(id: "flow", label: "자금", signal: "방어 쪽", explanation: "USDT.D가 24h 상승했습니다. 스테이블 비중 확대는 현금화·대기 수요와 부합하며, Stablecoin Supply와 TOTAL3를 함께 보면 방어인지 신규 대기자금인지 구분하기 쉽습니다.")
        case .flat:
            return MarketReadDimension(id: "flow", label: "자금", signal: "중립", explanation: "USDT.D 변화가 작습니다. Stablecoin Supply, TOTAL3와 실제 가격 움직임을 함께 봐야 자금 방향을 구분할 수 있습니다.")
        case .unknown:
            return MarketReadDimension(id: "flow", label: "자금", signal: "데이터 부족", explanation: "USDT.D 변화 데이터를 기다리고 있습니다.")
        }
    }()

    let leadershipDimension: MarketReadDimension = {
        if btc == .down, total3 == .up, eth == .up {
            return MarketReadDimension(id: "lead", label: "주도권", signal: "알트 확산", explanation: "BTC.D는 낮아지고 TOTAL3·ETH/BTC는 함께 오릅니다. BTC에서 알트로 상대강도가 확산되는 가장 깔끔한 조합 중 하나입니다.")
        }
        if btc == .down, total3 == .up {
            return MarketReadDimension(id: "lead", label: "주도권", signal: "알트 시도", explanation: "TOTAL3는 커지지만 ETH/BTC 확인이 부족합니다. 알트 파이는 확대되나 대형 알트까지 확산되는지는 추가 확인이 필요합니다.")
        }
        if btc == .up && (total3 == .down || total3 == .flat) {
            return MarketReadDimension(id: "lead", label: "주도권", signal: "BTC 집중", explanation: "BTC.D가 오르면서 TOTAL3가 강하게 따라오지 못합니다. 시장 내 상대강도가 BTC에 집중되는 구간으로 읽습니다.")
        }
        if eth == .up, total3 == .up {
            return MarketReadDimension(id: "lead", label: "주도권", signal: "ETH/알트", explanation: "ETH/BTC와 TOTAL3가 함께 올라 대형 알트의 상대강도와 시장 폭이 동시에 개선되고 있습니다.")
        }
        if btc == .up, total3 == .up {
            return MarketReadDimension(id: "lead", label: "주도권", signal: "동반 상승", explanation: "BTC와 알트 시총이 같이 강한데 BTC 비중도 상승합니다. 시장은 넓어지지만 BTC가 상대적으로 더 강한 흐름입니다.")
        }
        return MarketReadDimension(id: "lead", label: "주도권", signal: "혼조", explanation: "BTC.D·TOTAL3·ETH/BTC가 한 방향으로 정렬되지 않아 뚜렷한 주도 섹터를 단정하기 어렵습니다.")
    }()

    let spotDemandDimension: MarketReadDimension = {
        guard let fiveDay = investor?.etfFiveDayFlowUSD else {
            return MarketReadDimension(id: "spot", label: "현물 수요", signal: "데이터 부족", explanation: "미국 현물 BTC ETF 흐름을 기다리고 있습니다. 하루 값보다 최근 5거래일 합계를 중심으로 봅니다.")
        }
        let latestText = investor?.etfLatestFlowUSD.map { " · 최근 " + formatSignedUSDFlow($0) } ?? ""
        if fiveDay >= 500_000_000 {
            return MarketReadDimension(id: "spot", label: "현물 수요", signal: "강한 순유입", explanation: "BTC ETF 5D " + formatSignedUSDFlow(fiveDay) + latestText + "입니다. 지속적인 현물 순유입은 BTC 가격과 BTC.D 상승의 질을 보강하는 요소입니다.")
        }
        if fiveDay >= 100_000_000 {
            return MarketReadDimension(id: "spot", label: "현물 수요", signal: "순유입", explanation: "BTC ETF 5D " + formatSignedUSDFlow(fiveDay) + latestText + "로 현물 수요가 우호적입니다. 하루 변동보다 누적 흐름이 유지되는지 봅니다.")
        }
        if fiveDay <= -500_000_000 {
            return MarketReadDimension(id: "spot", label: "현물 수요", signal: "강한 순유출", explanation: "BTC ETF 5D " + formatSignedUSDFlow(fiveDay) + latestText + "입니다. 가격이 강해도 ETF 수요가 받치지 못하면 레버리지 의존도가 커지는지 점검합니다.")
        }
        if fiveDay <= -100_000_000 {
            return MarketReadDimension(id: "spot", label: "현물 수요", signal: "순유출", explanation: "BTC ETF 5D " + formatSignedUSDFlow(fiveDay) + latestText + "로 현물 수요가 다소 약합니다. 추세 훼손 여부는 가격·OI와 함께 봅니다.")
        }
        return MarketReadDimension(id: "spot", label: "현물 수요", signal: "중립", explanation: "BTC ETF 5거래일 누적 흐름이 크지 않아 현재 시장 방향을 강하게 확인하거나 부정하지 않습니다.")
    }()

    let trendDimension: MarketReadDimension = {
        guard let ret7 = investor?.btcReturn7d, let ret30 = investor?.btcReturn30d, let above = investor?.btcAbove200DMA else {
            return MarketReadDimension(id: "trend", label: "중기 추세", signal: "데이터 부족", explanation: "BTC 7D·30D 수익률과 200DMA 데이터를 기다리고 있습니다.")
        }
        if above, ret30 >= 5.0 {
            return MarketReadDimension(id: "trend", label: "중기 추세", signal: "상승 구조", explanation: String(format: "BTC 7D %+.1f%% · 30D %+.1f%%이며 200DMA 위입니다. 단기 하락은 우선 상승 추세 안의 조정인지 구분해서 봅니다.", ret7, ret30))
        }
        if !above, ret30 <= -5.0 {
            return MarketReadDimension(id: "trend", label: "중기 추세", signal: "약세 구조", explanation: String(format: "BTC 7D %+.1f%% · 30D %+.1f%%이며 200DMA 아래입니다. 단기 반등은 중기 추세 전환보다 약세 안의 반등 가능성을 먼저 봅니다.", ret7, ret30))
        }
        if above {
            return MarketReadDimension(id: "trend", label: "중기 추세", signal: "200D 위", explanation: String(format: "BTC는 200DMA 위지만 7D %+.1f%% · 30D %+.1f%%로 모멘텀 정렬은 혼조입니다. 200DMA 유지와 30D 방향을 같이 봅니다.", ret7, ret30))
        }
        return MarketReadDimension(id: "trend", label: "중기 추세", signal: "200D 아래", explanation: String(format: "BTC는 200DMA 아래이고 7D %+.1f%% · 30D %+.1f%%입니다. 200DMA 회복 전까지 중기 추세 확인은 보수적으로 봅니다.", ret7, ret30))
    }()

    let leverageDimension: MarketReadDimension = {
        guard let oi = fast?.openInterestChange1h, let funding = fast?.fundingRatePercent else {
            return MarketReadDimension(id: "lev", label: "레버리지", signal: "데이터 부족", explanation: "OI와 Funding 데이터를 기다리고 있습니다.")
        }
        if oi >= 5.0, funding >= 0.05 {
            return MarketReadDimension(id: "lev", label: "레버리지", signal: "롱 과열", explanation: String(format: "OI가 1h +%.1f%% 늘고 Funding이 +%.3f%%입니다. 롱 포지션 과밀과 롱 스퀴즈 위험을 같이 봅니다.", oi, funding))
        }
        if oi >= 5.0, funding <= -0.05 {
            return MarketReadDimension(id: "lev", label: "레버리지", signal: "숏 과밀", explanation: String(format: "OI가 1h +%.1f%% 늘고 Funding이 %.3f%%입니다. 숏 쏠림으로 인한 숏 스퀴즈 가능성을 별도 위험으로 봅니다.", oi, funding))
        }
        if oi <= -3.0 {
            return MarketReadDimension(id: "lev", label: "레버리지", signal: "디레버리징", explanation: String(format: "OI가 1h %.1f%% 줄었습니다. 포지션이 정리되는 흐름이라 레버리지 과밀은 완화되는 쪽입니다.", oi))
        }
        if abs(funding) >= 0.10 {
            return MarketReadDimension(id: "lev", label: "레버리지", signal: "편향 큼", explanation: String(format: "Funding이 %+.3f%%로 한쪽 포지션 비용이 높습니다. 방향 신호보다 포지션 쏠림 신호로 읽습니다.", funding))
        }
        if oi >= 3.0 {
            return MarketReadDimension(id: "lev", label: "레버리지", signal: "증가 중", explanation: String(format: "OI가 1h +%.1f%%로 늘고 있습니다. 아직 극단은 아니지만 가격 상승과 같이 빠르게 커지는지 관찰합니다.", oi))
        }
        return MarketReadDimension(id: "lev", label: "레버리지", signal: "중립", explanation: String(format: "OI 1h %+.1f%%, Funding %+.3f%%로 현재 기준에서는 극단적인 포지션 쏠림이 뚜렷하지 않습니다.", oi, funding))
    }()

    let retailDimension: MarketReadDimension = {
        guard let kimchi = premium?.value else {
            return MarketReadDimension(id: "retail", label: "국내 심리", signal: "데이터 부족", explanation: "김치프리미엄 데이터를 기다리고 있습니다.")
        }
        if kimchi >= 7.0 {
            return MarketReadDimension(id: "retail", label: "국내 심리", signal: "과열", explanation: String(format: "김프 +%.1f%%로 국내 매수 수요가 글로벌 시장보다 강하게 붙은 상태입니다. 상투 확정이 아니라 리테일 FOMO 경고로 봅니다.", kimchi))
        }
        if kimchi >= 5.0 {
            return MarketReadDimension(id: "retail", label: "국내 심리", signal: "높음", explanation: String(format: "김프 +%.1f%%로 국내 수요가 높은 편입니다. 가격·OI·Funding 과열이 같이 나타나는지 확인합니다.", kimchi))
        }
        if kimchi >= 2.0 {
            return MarketReadDimension(id: "retail", label: "국내 심리", signal: "다소 높음", explanation: String(format: "김프 +%.1f%%입니다. 국내 수요 우위가 있지만 단독 과열 신호로 볼 정도는 아닙니다.", kimchi))
        }
        if kimchi <= -1.0 {
            return MarketReadDimension(id: "retail", label: "국내 심리", signal: "역프", explanation: String(format: "김프 %.1f%%로 국내 가격이 글로벌 환산가보다 낮습니다. 국내 수요가 상대적으로 약한 상태인지 확인합니다.", kimchi))
        }
        return MarketReadDimension(id: "retail", label: "국내 심리", signal: "중립", explanation: String(format: "김프 %+.1f%%로 현재 기준에서는 국내 리테일 과열이 두드러지지 않습니다.", kimchi))
    }()

    let priceDimension: MarketReadDimension = {
        guard let day = btcChange24h else {
            return MarketReadDimension(id: "price", label: "가격", signal: "데이터 부족", explanation: "BTC 24h 가격 변화를 기다리고 있습니다.")
        }
        if let short = btcChange5m {
            if day > 0.5, short > 0.10 {
                return MarketReadDimension(id: "price", label: "가격", signal: "강세 동행", explanation: String(format: "BTC 24h %+.1f%%, 5m %+.2f%%로 큰 방향과 단기 모멘텀이 모두 위를 향합니다.", day, short))
            }
            if day > 0.5, short < -0.10 {
                return MarketReadDimension(id: "price", label: "가격", signal: "상승 중 조정", explanation: String(format: "BTC 24h %+.1f%%지만 5m %+.2f%%입니다. 큰 방향은 강하지만 단기적으로 숨 고르기인지 확인합니다.", day, short))
            }
            if day < -0.5, short > 0.10 {
                return MarketReadDimension(id: "price", label: "가격", signal: "약세 중 반등", explanation: String(format: "BTC 24h %+.1f%%지만 5m %+.2f%%입니다. 추세 전환보다 하락 흐름 안의 단기 반등일 가능성을 먼저 염두에 둡니다.", day, short))
            }
            if day < -0.5, short < -0.10 {
                return MarketReadDimension(id: "price", label: "가격", signal: "약세 동행", explanation: String(format: "BTC 24h %+.1f%%, 5m %+.2f%%로 큰 방향과 단기 모멘텀이 모두 약합니다.", day, short))
            }
            return MarketReadDimension(id: "price", label: "가격", signal: "단기 혼조", explanation: String(format: "BTC 24h %+.1f%%, 5m %+.2f%%입니다. 단기 움직임이 큰 시장 맥락을 아직 강화하지는 않습니다.", day, short))
        }
        return MarketReadDimension(id: "price", label: "가격", signal: day >= 0 ? "24h 강세" : "24h 약세", explanation: String(format: "BTC 24h %+.1f%%입니다. 단기 5m 기준이 준비되면 큰 방향과 단기 모멘텀의 일치 여부도 같이 봅니다.", day))
    }()

    return MarketRead(
        title: title,
        summary: summary,
        decision: decision,
        reversal: reversal,
        basis: basisParts.joined(separator: " · "),
        alignment: title == "혼조·전환 구간" ? "신호 혼조" : "핵심 정렬 \(min(aligned, alignmentTotal))/\(alignmentTotal)",
        dimensions: [flowDimension, leadershipDimension, spotDemandDimension, trendDimension, leverageDimension, retailDimension, priceDimension],
        tone: tone,
        badges: badges
    )
}


private func makeMarketReadEnglish(
    macro: MacroMarketSnapshot?,
    fast: FastMarketSnapshot?,
    investor: InvestorMarketSnapshot?,
    premium: PremiumSnapshot?,
    btcChange24h: Double?,
    btcChange5m: Double?
) -> MarketRead {
    guard let macro else {
        return MarketRead(
            title: "Building market context",
            summary: "Waiting for dominance and market-cap data. Once the core inputs arrive, Catoshi separates liquidity, leadership, spot demand, medium-term trend, leverage and Korean retail sentiment.",
            decision: "There is not enough data yet to make a directional read.",
            reversal: "Keep the Market tab open; the interpretation updates automatically when the macro data arrives.",
            basis: "Waiting for BTC.D · USDT.D · TOTAL3*",
            alignment: "Waiting for data",
            dimensions: [
                MarketReadDimension(id: "flow", label: "Liquidity", signal: "Waiting", explanation: "Waiting for USDT.D and market-cap data."),
                MarketReadDimension(id: "lead", label: "Leadership", signal: "Waiting", explanation: "BTC.D, TOTAL3 and ETH/BTC will be used to compare BTC and altcoin relative strength."),
                MarketReadDimension(id: "spot", label: "Spot demand", signal: "Waiting", explanation: "Waiting for US spot BTC ETF flow data."),
                MarketReadDimension(id: "trend", label: "Medium trend", signal: "Waiting", explanation: "Waiting for 7D, 30D and 200DMA data."),
                MarketReadDimension(id: "lev", label: "Leverage", signal: "Waiting", explanation: "Waiting for open interest and funding data."),
                MarketReadDimension(id: "retail", label: "Korea retail", signal: "Waiting", explanation: "The kimchi premium will be used as a Korean retail-heat check once available.")
            ],
            tone: .neutral,
            badges: []
        )
    }

    let btc = metricTrend(macro.btcDominanceChange24hPP, threshold: 0.15)
    let usdt = metricTrend(macro.usdtDominanceChange24hPP, threshold: 0.10)
    let total3 = metricTrend(macro.total3Change24h, threshold: 0.75)
    let eth = metricTrend(fast?.ethBTCChange24h, threshold: 0.50)

    var title = "Mixed / transition regime"
    var summary = "Leadership and liquidity are not aligned in one direction. In this regime, waiting for USDT.D and TOTAL3 to confirm each other is usually more informative than reading BTC.D alone."
    var decision = "Avoid forcing a directional conclusion. Prioritize whether liquidity and market breadth begin confirming the same regime; short price moves are easy to overread during mixed conditions."
    var reversal = "Watch for USDT.D and TOTAL3 to stop contradicting each other and begin pointing to the same market regime."
    var tone: MarketReadTone = .neutral
    var badges: [String] = []
    var aligned = 1
    let alignmentTotal = 4

    if btc == .down, usdt == .down, total3 == .up {
        title = "Alt rotation strengthening"
        summary = "BTC share and USDT share are both falling while market cap outside BTC and ETH is expanding. This is closer to genuine alt-market expansion than a simple drop in BTC dominance caused by BTC weakness."
        decision = "For an alt-strength read, TOTAL3 expansion matters more than BTC.D falling by itself. If ETH/BTC also rises, large-cap alt relative strength confirms that the rotation is broadening."
        reversal = "A renewed rise in USDT.D or a downturn in TOTAL3 weakens the alt-rotation read. If ETH/BTC also rolls over, re-check whether breadth is fading."
        tone = .constructive
        badges.append("Alt rotation")
        aligned = 3 + (eth == .up ? 1 : 0)
    } else if btc == .up, usdt == .down {
        title = "BTC-led risk-on"
        summary = "BTC dominance is rising while USDT dominance is falling. That combination fits a market where risk exposure is increasing but demand is concentrating in BTC first."
        decision = "Read this as BTC leadership rather than broad market strength. Until TOTAL3 and ETH/BTC follow higher, do not automatically extend BTC strength to the whole altcoin market."
        reversal = "If BTC.D turns down while TOTAL3 and ETH/BTC rise together, re-check for a leadership shift from BTC concentration toward alt rotation."
        tone = .constructive
        badges.append("BTC-led")
        aligned = 2 + ((total3 == .flat || total3 == .down) ? 1 : 0) + ((eth == .flat || eth == .down) ? 1 : 0)
    } else if btc == .down, usdt == .up {
        title = "Risk-off / capital retreat"
        summary = "BTC share is falling while USDT share is rising. That looks more like reduced crypto risk exposure and defensive stablecoin positioning than healthy altcoin rotation."
        decision = "This is a common setup in which falling BTC.D can be mistaken for alt strength. Check whether TOTAL3 is actually shrinking, and avoid assuming risk appetite has recovered until USDT.D turns lower."
        reversal = "A turn lower in USDT.D together with a recovery in TOTAL3 would be an early sign that capital-retreat pressure is easing."
        tone = .riskOff
        badges.append("Risk-off")
        aligned = 2 + (total3 == .down ? 1 : 0) + (eth == .down ? 1 : 0)
    } else if btc == .flat, eth == .up, total3 == .up {
        title = "ETH-led rotation"
        summary = "BTC dominance is broadly stable while ETH/BTC and TOTAL3 rise together. Relative strength is spreading from BTC toward large-cap alts while the broader alt market also expands."
        decision = "ETH/BTC is more meaningful when TOTAL3 confirms it. When both rise, the move is more likely to reflect broadening market participation rather than isolated ETH strength."
        reversal = "If ETH/BTC stalls or TOTAL3 turns down, re-check whether the rotation is weakening. A concurrent rise in USDT.D would make the read more defensive."
        tone = .constructive
        badges.append("ETH-led")
        aligned = 3 + (usdt != .up ? 1 : 0)
    }

    var basisParts = [
        "BTC.D \(btc.rawValue)",
        "USDT.D \(usdt.rawValue)",
        "TOTAL3 \(total3.rawValue)"
    ]
    if eth != .unknown { basisParts.append("ETH/BTC \(eth.rawValue)") }
    if let btcChange24h { basisParts.append(String(format: "BTC 24h %+.1f%%", btcChange24h)) }
    if let btcChange5m { basisParts.append(String(format: "5m %+.2f%%", btcChange5m)) }

    if let stable7d = investor?.stablecoinSupplyChange7d {
        basisParts.append(String(format: "Stables 7D %+.2f%%", stable7d))
        if stable7d >= 0.50 {
            badges.append("Liquidity expanding")
            if usdt == .down {
                summary += " USDT+USDC supply is also expanding over 7 days while USDT.D falls, which strengthens the case that the move is supported by actual stablecoin liquidity rather than only a market-cap denominator effect."
                decision += " For a liquidity-inflow read, keep checking whether stablecoin supply continues to grow instead of relying on USDT.D alone."
            } else if usdt == .up {
                summary += " Stablecoin supply is expanding, but USDT.D is also rising, so some of that new liquidity may still be waiting in stablecoins rather than being deployed into risk assets."
                reversal += " A turn lower in USDT.D would be a useful sign that waiting stable liquidity is being deployed."
            }
        } else if stable7d <= -0.50 {
            badges.append("Liquidity contracting")
            if usdt == .down {
                summary += " However, USDT+USDC supply is contracting over 7 days, so falling USDT.D cannot be treated as straightforward evidence of fresh capital inflow."
                decision += " In that case, prioritize TOTAL3 and the persistence of actual prices over the dominance move."
            } else {
                summary += " USDT+USDC supply is contracting over 7 days, adding evidence that stablecoin liquidity available to the crypto market is shrinking."
            }
            if tone == .constructive || tone == .neutral { tone = .caution }
        }
    }

    if let etf5d = investor?.etfFiveDayFlowUSD {
        basisParts.append("ETF 5D " + formatSignedUSDFlow(etf5d))
        if etf5d >= 500_000_000 {
            badges.append("ETF inflow")
            summary += " US spot BTC ETFs also show a clear net inflow over the latest five trading days, providing a spot-demand tailwind for BTC."
            if btc == .up {
                decision += " When rising BTC.D is accompanied by ETF inflows, the move has more evidence of spot demand and is less dependent on derivatives leverage alone."
            }
        } else if etf5d <= -500_000_000 {
            badges.append("ETF outflow")
            summary += " US spot BTC ETFs show a sizable net outflow over the latest five trading days, so institutional spot demand is not fully supporting the price move."
            decision += " If price rises while ETF outflows persist, check whether OI growth is replacing spot demand and weakening the quality of the rally."
            if tone == .constructive || tone == .neutral { tone = .caution }
        }
    }

    if let ret30 = investor?.btcReturn30d, let above200 = investor?.btcAbove200DMA {
        basisParts.append(String(format: "BTC 30D %+.1f%%", ret30))
        basisParts.append(above200 ? "Above 200DMA" : "Below 200DMA")
        if above200, ret30 >= 5.0 {
            badges.append("Medium uptrend")
            summary += " BTC is above its 200-day moving average with healthy 30-day performance, so the short-term signals are occurring inside a constructive medium-term structure."
            decision += " Distinguish a short-term pullback from actual trend damage by watching both the 200DMA and 30-day momentum."
        } else if !above200, ret30 <= -5.0 {
            badges.append("Medium weakness")
            summary += " BTC is below its 200-day moving average with weak 30-day performance, so a short-term bounce should first be treated as a rebound inside a weaker medium-term structure."
            decision += " Do not call a trend reversal from short-term strength alone; look for a 200DMA recovery and improving 30-day momentum together."
            if tone == .constructive || tone == .neutral { tone = .caution }
        } else {
            summary += " The 200-day position and 30-day momentum are not fully aligned, so medium-term trend confirmation remains mixed."
        }
    }

    if let oi = fast?.openInterestChange1h,
       let funding = fast?.fundingRatePercent,
       oi >= 5.0, funding >= 0.05 {
        badges.append("Crowded longs")
        summary += " OI is rising quickly and funding is meaningfully positive, so long positioning is becoming crowded even if the broader direction remains constructive."
        decision += " Liquidations can turn a small pullback into a larger move; entry price and loss tolerance matter more when leverage is crowded."
        reversal += " Slower OI growth and funding normalization would signal easing leverage pressure."
        basisParts.append(String(format: "OI +%.1f%%/1h", oi))
        basisParts.append(String(format: "Funding +%.3f%%", funding))
        if tone == .constructive || tone == .neutral { tone = .caution }
    } else if let oi = fast?.openInterestChange1h,
              let funding = fast?.fundingRatePercent,
              oi >= 5.0, funding <= -0.05 {
        badges.append("Crowded shorts")
        summary += " OI is rising quickly while funding is deeply negative, suggesting short positioning may be crowded."
        decision += " If spot price and trading strengthen, a short squeeze can amplify volatility; negative funding should not be read as a bearish signal by itself."
        reversal += " Falling OI or funding returning toward zero would indicate less crowded positioning."
        basisParts.append(String(format: "OI +%.1f%%/1h", oi))
        basisParts.append(String(format: "Funding %.3f%%", funding))
        if tone == .neutral { tone = .caution }
    } else if let funding = fast?.fundingRatePercent, funding >= 0.10 {
        badges.append("Funding hot")
        summary += " Funding is unusually positive, making long crowding a separate risk factor."
        decision += " Even with strong price action, persistently high funding raises the risk of chasing the move."
        basisParts.append(String(format: "Funding +%.3f%%", funding))
        if tone == .constructive || tone == .neutral { tone = .caution }
    } else if let funding = fast?.fundingRatePercent, funding <= -0.10 {
        badges.append("Funding negative")
        summary += " Funding is unusually negative, increasing the chance that shorts are crowded."
        decision += " Negative funding is a positioning signal, not proof of further downside; read it with spot direction."
        basisParts.append(String(format: "Funding %.3f%%", funding))
        if tone == .neutral { tone = .caution }
    }

    if let kimchi = premium?.value, kimchi >= 7.0 {
        badges.append("Korea FOMO")
        summary += " The kimchi premium is above 7%, which raises the risk of overheated Korean retail demand."
        decision += " Korean overheating does not validate the global trend, so do not use the premium alone to infer that strength will persist."
        reversal += " A rapid normalization of the premium would indicate that domestic FOMO is cooling."
        basisParts.append(String(format: "Kimchi +%.1f%%", kimchi))
        if tone != .riskOff { tone = .caution }
    } else if let kimchi = premium?.value, kimchi >= 5.0 {
        badges.append("Kimchi elevated")
        summary += " The kimchi premium is elevated, so additional Korean retail overheating deserves attention."
        basisParts.append(String(format: "Kimchi +%.1f%%", kimchi))
        if tone == .constructive { tone = .caution }
    }

    let flowDimension: MarketReadDimension = {
        let stable = investor?.stablecoinSupplyChange7d
        if usdt == .down, let stable, stable >= 0.50 {
            return MarketReadDimension(id: "flow", label: "Liquidity", signal: "Inflow confirmed", explanation: String(format: "USDT.D is falling while USDT+USDC supply is up %+.2f%% over 7D. Falling stablecoin share and expanding supply together provide stronger evidence of deployable risk liquidity.", stable))
        }
        if usdt == .down, let stable, stable <= -0.50 {
            return MarketReadDimension(id: "flow", label: "Liquidity", signal: "Denominator risk", explanation: String(format: "USDT.D is falling, but USDT+USDC supply is also down %+.2f%% over 7D. The dominance move may reflect rising asset prices rather than fresh capital, so TOTAL3 and price persistence matter more.", stable))
        }
        if usdt == .up, let stable, stable >= 0.50 {
            return MarketReadDimension(id: "flow", label: "Liquidity", signal: "Cash waiting", explanation: String(format: "USDT+USDC supply is up %+.2f%% over 7D while USDT.D also rises. New liquidity may be arriving but remaining parked in stables for now.", stable))
        }
        if usdt == .up, let stable, stable <= -0.50 {
            return MarketReadDimension(id: "flow", label: "Liquidity", signal: "Defensive / shrinking", explanation: String(format: "USDT.D is rising while USDT+USDC supply is down %+.2f%% over 7D, combining defensive stablecoin share with contracting overall stable liquidity.", stable))
        }
        switch usdt {
        case .down: return MarketReadDimension(id: "flow", label: "Liquidity", signal: "Risk-on leaning", explanation: "USDT.D is down over 24h. That fits deployment into risk assets, but without clear stablecoin-supply growth, denominator effects remain possible.")
        case .up: return MarketReadDimension(id: "flow", label: "Liquidity", signal: "Defensive leaning", explanation: "USDT.D is up over 24h. A higher stablecoin share fits cash-like positioning; stablecoin supply and TOTAL3 help distinguish defense from new liquidity waiting to deploy.")
        case .flat: return MarketReadDimension(id: "flow", label: "Liquidity", signal: "Neutral", explanation: "USDT.D has moved little. Use stablecoin supply, TOTAL3 and actual price action to infer the direction of capital.")
        case .unknown: return MarketReadDimension(id: "flow", label: "Liquidity", signal: "No data", explanation: "Waiting for USDT.D change data.")
        }
    }()

    let leadershipDimension: MarketReadDimension = {
        if btc == .down, total3 == .up, eth == .up { return MarketReadDimension(id: "lead", label: "Leadership", signal: "Alt breadth", explanation: "BTC.D is falling while TOTAL3 and ETH/BTC rise together, one of the cleaner combinations for relative strength spreading from BTC into alts.") }
        if btc == .down, total3 == .up { return MarketReadDimension(id: "lead", label: "Leadership", signal: "Alt attempt", explanation: "TOTAL3 is expanding, but ETH/BTC confirmation is missing. The alt market is growing, though breadth into large-cap alts needs confirmation.") }
        if btc == .up && (total3 == .down || total3 == .flat) { return MarketReadDimension(id: "lead", label: "Leadership", signal: "BTC concentration", explanation: "BTC.D is rising while TOTAL3 is not keeping pace, so relative strength is concentrating in BTC.") }
        if eth == .up, total3 == .up { return MarketReadDimension(id: "lead", label: "Leadership", signal: "ETH / alts", explanation: "ETH/BTC and TOTAL3 are rising together, improving both large-cap alt relative strength and broader market breadth.") }
        if btc == .up, total3 == .up { return MarketReadDimension(id: "lead", label: "Leadership", signal: "Broad rise, BTC stronger", explanation: "BTC and alt market cap are both rising, but BTC dominance is also increasing. The market is broadening while BTC remains relatively stronger.") }
        return MarketReadDimension(id: "lead", label: "Leadership", signal: "Mixed", explanation: "BTC.D, TOTAL3 and ETH/BTC are not aligned strongly enough to identify a clear leading segment.")
    }()

    let spotDemandDimension: MarketReadDimension = {
        guard let fiveDay = investor?.etfFiveDayFlowUSD else { return MarketReadDimension(id: "spot", label: "Spot demand", signal: "No data", explanation: "Waiting for US spot BTC ETF flows. The five-trading-day sum is more useful than one day.") }
        let latestText = investor?.etfLatestFlowUSD.map { " · latest " + formatSignedUSDFlow($0) } ?? ""
        if fiveDay >= 500_000_000 { return MarketReadDimension(id: "spot", label: "Spot demand", signal: "Strong inflow", explanation: "BTC ETF 5D " + formatSignedUSDFlow(fiveDay) + latestText + ". Persistent spot inflows strengthen the quality of BTC price and dominance gains.") }
        if fiveDay >= 100_000_000 { return MarketReadDimension(id: "spot", label: "Spot demand", signal: "Inflow", explanation: "BTC ETF 5D " + formatSignedUSDFlow(fiveDay) + latestText + ". Spot demand is supportive; watch whether the cumulative flow persists.") }
        if fiveDay <= -500_000_000 { return MarketReadDimension(id: "spot", label: "Spot demand", signal: "Strong outflow", explanation: "BTC ETF 5D " + formatSignedUSDFlow(fiveDay) + latestText + ". If price remains strong without ETF demand, check whether leverage is taking a larger role.") }
        if fiveDay <= -100_000_000 { return MarketReadDimension(id: "spot", label: "Spot demand", signal: "Outflow", explanation: "BTC ETF 5D " + formatSignedUSDFlow(fiveDay) + latestText + ". Spot demand is somewhat weak; read trend damage together with price and OI.") }
        return MarketReadDimension(id: "spot", label: "Spot demand", signal: "Neutral", explanation: "The 5-day ETF flow is not large enough to strongly confirm or reject the current market direction.")
    }()

    let trendDimension: MarketReadDimension = {
        guard let ret7 = investor?.btcReturn7d, let ret30 = investor?.btcReturn30d, let above = investor?.btcAbove200DMA else { return MarketReadDimension(id: "trend", label: "Medium trend", signal: "No data", explanation: "Waiting for BTC 7D, 30D and 200DMA data.") }
        if above, ret30 >= 5.0 { return MarketReadDimension(id: "trend", label: "Medium trend", signal: "Uptrend structure", explanation: String(format: "BTC 7D %+.1f%% · 30D %+.1f%% and above the 200DMA. Short-term weakness should first be tested as a pullback within an uptrend.", ret7, ret30)) }
        if !above, ret30 <= -5.0 { return MarketReadDimension(id: "trend", label: "Medium trend", signal: "Weak structure", explanation: String(format: "BTC 7D %+.1f%% · 30D %+.1f%% and below the 200DMA. Short-term strength should first be treated as a rebound inside a weaker regime.", ret7, ret30)) }
        if above { return MarketReadDimension(id: "trend", label: "Medium trend", signal: "Above 200D", explanation: String(format: "BTC is above the 200DMA, but 7D %+.1f%% · 30D %+.1f%% momentum is mixed. Watch 200DMA support and the 30D direction together.", ret7, ret30)) }
        return MarketReadDimension(id: "trend", label: "Medium trend", signal: "Below 200D", explanation: String(format: "BTC is below the 200DMA with 7D %+.1f%% · 30D %+.1f%%. Medium-term confirmation remains conservative until the 200DMA is recovered.", ret7, ret30))
    }()

    let leverageDimension: MarketReadDimension = {
        guard let oi = fast?.openInterestChange1h, let funding = fast?.fundingRatePercent else { return MarketReadDimension(id: "lev", label: "Leverage", signal: "No data", explanation: "Waiting for OI and funding data.") }
        if oi >= 5.0, funding >= 0.05 { return MarketReadDimension(id: "lev", label: "Leverage", signal: "Crowded longs", explanation: String(format: "OI is up 1h +%.1f%% and funding is +%.3f%%. Long crowding raises long-squeeze risk.", oi, funding)) }
        if oi >= 5.0, funding <= -0.05 { return MarketReadDimension(id: "lev", label: "Leverage", signal: "Crowded shorts", explanation: String(format: "OI is up 1h +%.1f%% and funding is %.3f%%. Crowded shorts raise short-squeeze risk.", oi, funding)) }
        if oi <= -3.0 { return MarketReadDimension(id: "lev", label: "Leverage", signal: "Deleveraging", explanation: String(format: "OI is down %.1f%% over 1h. Positions are being reduced, easing leverage crowding.", oi)) }
        if abs(funding) >= 0.10 { return MarketReadDimension(id: "lev", label: "Leverage", signal: "Large bias", explanation: String(format: "Funding is %+.3f%%, making one side of positioning expensive. Read it as crowding, not direction.", funding)) }
        if oi >= 3.0 { return MarketReadDimension(id: "lev", label: "Leverage", signal: "Building", explanation: String(format: "OI is up 1h +%.1f%%. It is not extreme yet, but watch whether it accelerates alongside price.", oi)) }
        return MarketReadDimension(id: "lev", label: "Leverage", signal: "Neutral", explanation: String(format: "OI 1h %+.1f%% and funding %+.3f%% do not currently show extreme positioning.", oi, funding))
    }()

    let retailDimension: MarketReadDimension = {
        guard let kimchi = premium?.value else { return MarketReadDimension(id: "retail", label: "Korea retail", signal: "No data", explanation: "Waiting for kimchi-premium data.") }
        if kimchi >= 7.0 { return MarketReadDimension(id: "retail", label: "Korea retail", signal: "Overheated", explanation: String(format: "Kimchi premium +%.1f%% shows Korean buying demand well above the global converted price. Treat it as a retail-FOMO warning, not proof of a top.", kimchi)) }
        if kimchi >= 5.0 { return MarketReadDimension(id: "retail", label: "Korea retail", signal: "High", explanation: String(format: "Kimchi premium +%.1f%% is elevated. Check whether price, OI and funding are also overheating.", kimchi)) }
        if kimchi >= 2.0 { return MarketReadDimension(id: "retail", label: "Korea retail", signal: "Somewhat high", explanation: String(format: "Kimchi premium +%.1f%% shows stronger Korean demand, but not enough by itself to call the market overheated.", kimchi)) }
        if kimchi <= -1.0 { return MarketReadDimension(id: "retail", label: "Korea retail", signal: "Discount", explanation: String(format: "Kimchi premium %.1f%% means the Korean price is below the global converted price. Check whether domestic demand is relatively weak.", kimchi)) }
        return MarketReadDimension(id: "retail", label: "Korea retail", signal: "Neutral", explanation: String(format: "Kimchi premium %+.1f%% does not currently indicate pronounced Korean retail overheating.", kimchi))
    }()

    let priceDimension: MarketReadDimension = {
        guard let day = btcChange24h else { return MarketReadDimension(id: "price", label: "Price", signal: "No data", explanation: "Waiting for BTC 24h price change.") }
        if let short = btcChange5m {
            if day > 0.5, short > 0.10 { return MarketReadDimension(id: "price", label: "Price", signal: "Bullish alignment", explanation: String(format: "BTC 24h %+.1f%% and 5m %+.2f%%: both the larger move and short-term momentum point higher.", day, short)) }
            if day > 0.5, short < -0.10 { return MarketReadDimension(id: "price", label: "Price", signal: "Pullback in up move", explanation: String(format: "BTC 24h %+.1f%% but 5m %+.2f%%. The larger direction is strong while short-term momentum is cooling.", day, short)) }
            if day < -0.5, short > 0.10 { return MarketReadDimension(id: "price", label: "Price", signal: "Bounce in weak move", explanation: String(format: "BTC 24h %+.1f%% but 5m %+.2f%%. Treat this first as a short bounce inside a weaker move rather than a confirmed trend reversal.", day, short)) }
            if day < -0.5, short < -0.10 { return MarketReadDimension(id: "price", label: "Price", signal: "Bearish alignment", explanation: String(format: "BTC 24h %+.1f%% and 5m %+.2f%%: both the larger move and short-term momentum are weak.", day, short)) }
            return MarketReadDimension(id: "price", label: "Price", signal: "Short-term mixed", explanation: String(format: "BTC 24h %+.1f%% and 5m %+.2f%%. The short-term move is not yet reinforcing the broader context.", day, short))
        }
        return MarketReadDimension(id: "price", label: "Price", signal: day >= 0 ? "24h bullish" : "24h bearish", explanation: String(format: "BTC 24h %+.1f%%. Once the 5m reference is ready, compare short-term momentum with the larger direction.", day))
    }()

    return MarketRead(
        title: title,
        summary: summary,
        decision: decision,
        reversal: reversal,
        basis: basisParts.joined(separator: " · "),
        alignment: title == "Mixed / transition regime" ? "Signals mixed" : "Core alignment \(min(aligned, alignmentTotal))/\(alignmentTotal)",
        dimensions: [flowDimension, leadershipDimension, spotDemandDimension, trendDimension, leverageDimension, retailDimension, priceDimension],
        tone: tone,
        badges: badges
    )
}

