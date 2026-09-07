import AppKit
import Foundation
import SwiftUI

@MainActor
struct CatoshiSettingsView: View {
    @ObservedObject var model: MarketModel
    @State private var marketReactionExpanded = false

    private let previewColumns = Array(
        repeating: GridItem(.flexible(minimum: 72), spacing: 8),
        count: 5
    )

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
                SettingsCard(
                    model.appLanguage.pick("고양이 선택", "Choose your Catoshi"),
                    subtitle: model.appLanguage.pick(
                        "메뉴바와 미리보기에 즉시 반영됩니다.",
                        "Applied immediately in the menu bar and previews."
                    )
                ) {
                    HStack(spacing: 8) {
                        ForEach(CatoshiCoat.allCases) { coat in
                            CatoshiCoatButton(
                                coat: coat,
                                selected: model.catoshiCoat == coat,
                                language: model.appLanguage
                            ) {
                                model.catoshiCoat = coat
                            }
                        }
                    }
                }

                SettingsCard(
                    model.appLanguage.pick("일상 행동", "Daily Behavior"),
                    subtitle: model.appLanguage.pick(
                        "움직임과 산책·휴식 빈도를 조절합니다.",
                        "Control motion and the frequency of walks and rests."
                    )
                ) {
                    VStack(spacing: 11) {
                        SettingToggleRow(
                            model.appLanguage.pick("고양이 동작", "Cat Motion"),
                            detail: model.appLanguage.pick(
                                "걷기·자세 전환·미세 동작을 재생합니다.",
                                "Plays walking, transitions and micro-movements."
                            ),
                            isOn: $model.catoshiAnimationEnabled
                        )

                        Divider()

                        SettingToggleRow(
                            model.appLanguage.pick("랜덤 일상", "Daily Life"),
                            detail: model.appLanguage.pick(
                                "메뉴바를 산책하고 중간중간 쉽니다.",
                                "Lets Catoshi roam the menu bar and rest along the way."
                            ),
                            isOn: $model.catoshiRandomLifeEnabled
                        )
                        .disabled(!model.catoshiAnimationEnabled)
                        .opacity(model.catoshiAnimationEnabled ? 1 : 0.48)

                        HStack(alignment: .center, spacing: 12) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(model.appLanguage.pick("활동량", "Activity"))
                                    .font(.system(size: CatoshiType.body, weight: .medium))
                                Text(model.appLanguage.pick(
                                    "산책·휴식 사이의 평균 간격",
                                    "Typical interval between walks and rests"
                                ))
                                    .font(.system(size: CatoshiType.secondary))
                                    .catoshiText(.secondary)
                            }
                            Spacer(minLength: 12)
                            Picker(model.appLanguage.pick("활동량", "Activity"), selection: $model.catoshiActivity) {
                                ForEach(CatoshiActivity.allCases) { item in
                                    Text(item.label(model.appLanguage)).tag(item)
                                }
                            }
                            .labelsHidden()
                            .pickerStyle(.segmented)
                            .frame(width: 185)
                        }
                        .disabled(!model.catoshiAnimationEnabled || !model.catoshiRandomLifeEnabled)
                        .opacity(model.catoshiAnimationEnabled && model.catoshiRandomLifeEnabled ? 1 : 0.48)

                        Text(model.appLanguage.pick(
                            "Binance 왼쪽을 집으로 삼아 메뉴바 곳곳을 산책합니다. 낮잠·그루밍 때는 집으로 돌아옵니다.",
                            "Catoshi uses the space left of Binance as home, roams the menu bar, and returns home for naps or grooming."
                        ))
                            .font(.system(size: CatoshiType.secondary))
                            .catoshiText(.secondary)
                            .lineSpacing(1)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                SettingsCard(
                    model.appLanguage.pick("시장 반응 · Binance BTC 5m", "Market Reactions · Binance BTC 5m"),
                    subtitle: model.appLanguage.pick(
                        "BTC 5분 변동에 따른 반응을 조절합니다.",
                        "Control reactions to BTC 5-minute moves."
                    )
                ) {
                    DisclosureGroup(isExpanded: $marketReactionExpanded) {
                        VStack(spacing: 11) {
                            Divider()
                                .padding(.top, 4)

                            SettingToggleRow(
                                model.appLanguage.pick("시장 움직임에 반응", "React to Market Moves"),
                                detail: model.appLanguage.pick(
                                    "기준치를 넘으면 신남·우다다로 반응합니다.",
                                    "Triggers excited or zoomies reactions beyond the threshold."
                                ),
                                isOn: $model.catoshiMarketReactionsEnabled
                            )
                            .disabled(!model.catoshiAnimationEnabled)
                            .opacity(model.catoshiAnimationEnabled ? 1 : 0.48)

                            SettingToggleRow(
                                model.appLanguage.pick("급락에 반응", "React to Sharp Drops"),
                                detail: model.appLanguage.pick(
                                    "급락 시 놀라거나 집으로 도망갑니다.",
                                    "Allows spooked or flee reactions on sharp drops."
                                ),
                                isOn: $model.catoshiDropReactionEnabled
                            )
                            .disabled(!model.catoshiAnimationEnabled || !model.catoshiMarketReactionsEnabled)
                            .opacity(model.catoshiAnimationEnabled && model.catoshiMarketReactionsEnabled ? 1 : 0.48)

                            HStack(alignment: .center, spacing: 12) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(model.appLanguage.pick("민감도", "Sensitivity"))
                                        .font(.system(size: CatoshiType.body, weight: .medium))
                                    Text(model.catoshiSensitivity.detailedSummary(model.appLanguage))
                                        .font(.system(size: CatoshiType.secondary).monospacedDigit())
                                        .catoshiText(.secondary)
                                }
                                Spacer(minLength: 12)
                                Picker(model.appLanguage.pick("민감도", "Sensitivity"), selection: $model.catoshiSensitivity) {
                                    ForEach(CatoshiSensitivity.allCases) { item in
                                        Text(item.label(model.appLanguage)).tag(item)
                                    }
                                }
                                .labelsHidden()
                                .pickerStyle(.segmented)
                                .frame(width: 185)
                            }
                            .disabled(!model.catoshiAnimationEnabled || !model.catoshiMarketReactionsEnabled)
                            .opacity(model.catoshiAnimationEnabled && model.catoshiMarketReactionsEnabled ? 1 : 0.48)

                            HStack(spacing: 12) {
                                Text(model.appLanguage.pick("쿨다운", "Cooldown"))
                                    .font(.system(size: CatoshiType.body, weight: .medium))
                                Spacer(minLength: 12)
                                Picker(model.appLanguage.pick("쿨다운", "Cooldown"), selection: $model.catoshiCooldown) {
                                    ForEach(CatoshiCooldown.allCases) { item in
                                        Text(item.label(model.appLanguage)).tag(item)
                                    }
                                }
                                .labelsHidden()
                                .frame(width: 150)
                            }
                            .disabled(!model.catoshiAnimationEnabled || !model.catoshiMarketReactionsEnabled)
                            .opacity(model.catoshiAnimationEnabled && model.catoshiMarketReactionsEnabled ? 1 : 0.48)

                            Text(model.appLanguage.pick(
                                "같은 반응은 변동폭이 해제 기준까지 충분히 돌아온 뒤 다시 진입할 때만 재발동합니다. 더 강한 단계나 반대 방향의 급격한 전환은 쿨다운 중에도 즉시 반응할 수 있습니다.",
                                "The same reaction must retreat past its release threshold before it can arm again. A stronger tier or a sharp reversal can still react immediately during cooldown."
                            ))
                                .font(.system(size: CatoshiType.secondary))
                                .catoshiText(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    } label: {
                        HStack(spacing: 8) {
                            Text(model.appLanguage.pick("급등·급락 반응 설정", "Price-move reactions"))
                                .font(.system(size: CatoshiType.body, weight: .medium))
                            Spacer()
                            Text(model.fiveMinuteChange.map { String(format: "%+.2f%%", $0) }
                                 ?? model.appLanguage.pick("준비 중", "Warming up"))
                                .font(.system(size: CatoshiType.secondary, weight: .semibold).monospacedDigit())
                                .catoshiText(.secondary)
                        }
                    }
                }

                SettingsCard(
                    model.appLanguage.pick("동작 미리보기", "Motion Preview"),
                    subtitle: model.appLanguage.pick(
                        "선택한 동작을 잠시 재생합니다.",
                        "Preview one action without changing settings."
                    )
                ) {
                    LazyVGrid(columns: previewColumns, alignment: .leading, spacing: 8) {
                        PreviewButton(model.appLanguage.pick("걷기", "Walk")) { model.previewCatoshi(.walk) }
                        PreviewButton(model.appLanguage.pick("방향 전환", "Turn")) { model.previewCatoshi(.turn) }
                        PreviewButton(model.appLanguage.pick("앉기", "Sit")) { model.previewCatoshi(.sit) }
                        PreviewButton(model.appLanguage.pick("식빵", "Loaf")) { model.previewCatoshi(.loaf) }
                        PreviewButton(model.appLanguage.pick("기지개", "Stretch")) { model.previewCatoshi(.stretch) }
                        PreviewButton(model.appLanguage.pick("그루밍", "Groom")) { model.previewCatoshi(.groom) }
                        PreviewButton(model.appLanguage.pick("낮잠", "Nap")) { model.previewCatoshi(.sleep) }
                        PreviewButton(model.appLanguage.pick("신남", "Happy")) { model.previewCatoshi(.happy) }
                        PreviewButton(model.appLanguage.pick("우다다", "Zoomies")) { model.previewCatoshi(.zoomies) }
                        PreviewButton(model.appLanguage.pick("놀람", "Spooked")) { model.previewCatoshi(.scared) }
                        PreviewButton(model.appLanguage.pick("도망", "Flee")) { model.previewCatoshi(.flee) }
                    }
                    .disabled(!model.catoshiAnimationEnabled)
                    .opacity(model.catoshiAnimationEnabled ? 1 : 0.48)
                }

                HStack {
                    CatoshiCurrentStateText(
                        motion: model.catoshiMotion,
                        language: model.appLanguage
                    )
                    Spacer()
                    Button(model.appLanguage.pick("Catoshi 기본값 복원", "Restore Catoshi Defaults")) {
                        model.resetCatoshiSettings()
                    }
                    .controlSize(.small)
                }
        }
        .padding(12)
        .frame(width: 500, alignment: .topLeading)
        .fixedSize(horizontal: false, vertical: true)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}


@MainActor
private struct CatoshiCurrentStateText: View {
    @ObservedObject var motion: CatoshiMotionModel
    let language: AppLanguage

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(language.pick("현재 상태", "Current State"))
                .font(.system(size: CatoshiType.secondary))
                .catoshiText(.secondary)
            Text(motion.state.label(language))
                .font(.system(size: CatoshiType.cardTitle, weight: .semibold))
        }
    }
}

@MainActor
private struct CatoshiStateSummary: View {
    @ObservedObject var motion: CatoshiMotionModel
    let coat: CatoshiCoat
    let language: AppLanguage

    var body: some View {
        HStack(spacing: 9) {
            Group {
                if let image = CatoshiAssets.sprite(named: motion.state.representativeFrameName, coat: coat) {
                    Image(nsImage: image)
                        .resizable()
                        .interpolation(.none)
                        .scaledToFit()
                        .frame(width: 32, height: 22)
                }
            }

            VStack(alignment: .leading, spacing: 1) {
                Text("Catoshi")
                    .font(.system(size: CatoshiType.button, weight: .semibold))
                Text(motion.state.label(language))
                    .font(.system(size: CatoshiType.secondary))
                    .catoshiText(.secondary)
                    .lineLimit(1)
            }
        }
    }
}

@MainActor
struct CatoshiCoatButton: View {
    let coat: CatoshiCoat
    let selected: Bool
    let language: AppLanguage
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Group {
                    if let image = CatoshiAssets.sprite(named: "idle", coat: coat) {
                        Image(nsImage: image)
                            .resizable()
                            .interpolation(.none)
                            .scaledToFit()
                    } else {
                        Text("🐈")
                    }
                }
                .frame(width: 54, height: 30)

                Text(coat.label(language))
                    .font(.system(size: CatoshiType.metadata, weight: selected ? .semibold : .regular))
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, minHeight: 54)
            .background(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(selected ? Color.accentColor.opacity(0.14) : Color.secondary.opacity(0.05))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .stroke(selected ? Color.accentColor.opacity(0.75) : Color.secondary.opacity(0.16), lineWidth: selected ? 1.2 : 0.7)
            )
        }
        .buttonStyle(.plain)
        .help(language.pick("\(coat.label(language)) Catoshi 사용", "Use the \(coat.label(language)) Catoshi"))
    }
}

struct PreviewButton: View {
    let label: String
    let action: () -> Void

    init(_ label: String, action: @escaping () -> Void) {
        self.label = label
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: CatoshiType.button, weight: .medium))
                .frame(maxWidth: .infinity, minHeight: 26)
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
    }
}

@MainActor
struct CatoshiControlRow: View {
    @ObservedObject var model: MarketModel
    @Binding var showCatoshiEditor: Bool
    @Binding var showDisplayEditor: Bool

    private var momentumText: String {
        guard let change = model.fiveMinuteChange else {
            return model.appLanguage.pick("5m 준비 중", "5m warming up")
        }
        return "5m " + String(format: "%+.2f%%", change)
    }

    private var momentumColor: Color {
        guard let change = model.fiveMinuteChange else { return .secondary }
        if model.displayPalette == .monochrome { return .primary }
        return change >= 0 ? .green : .red
    }

    var body: some View {
        HStack(spacing: 9) {
            CatoshiStateSummary(
                motion: model.catoshiMotion,
                coat: model.catoshiCoat,
                language: model.appLanguage
            )

            Spacer(minLength: 2)

            Text(momentumText)
                .font(.system(size: CatoshiType.metadata, weight: .semibold, design: .monospaced))
                .foregroundStyle(momentumColor)
                .frame(width: 78, alignment: .trailing)

            Button {
                showDisplayEditor = false
                showCatoshiEditor.toggle()
            } label: {
                Label(
                    model.appLanguage.pick("고양이 꾸미기", "Customize Catoshi"),
                    systemImage: "pawprint.fill"
                )
                .font(.system(size: CatoshiType.button, weight: .semibold))
                .lineLimit(1)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .help(model.appLanguage.pick("털색과 행동을 꾸미고 시장 반응 설정", "Customize the cat's coat, behavior and market reactions"))
            .accessibilityLabel(model.appLanguage.pick("고양이 꾸미기", "Customize Catoshi"))
            .popover(isPresented: $showCatoshiEditor, arrowEdge: .leading) {
                CatoshiSettingsView(model: model)
            }
        }
    }
}
