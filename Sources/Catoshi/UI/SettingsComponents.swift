import AppKit
import SwiftUI

struct SettingsCard<Content: View>: View {
    let title: String
    let subtitle: String?
    private let content: Content

    init(_ title: String, subtitle: String? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.subtitle = subtitle
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 11) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: CatoshiType.cardTitle, weight: .semibold))
                if let subtitle {
                    Text(subtitle)
                        .font(.system(size: CatoshiType.secondary))
                        .catoshiText(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            content
        }
        .padding(14)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.48))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.secondary.opacity(0.14), lineWidth: 0.8)
        }
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

struct SettingToggleRow: View {
    let title: String
    let detail: String?
    @Binding var isOn: Bool

    init(_ title: String, detail: String? = nil, isOn: Binding<Bool>) {
        self.title = title
        self.detail = detail
        self._isOn = isOn
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: CatoshiType.body, weight: .medium))
                if let detail {
                    Text(detail)
                        .font(.system(size: CatoshiType.secondary))
                        .catoshiText(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 12)
            Toggle("", isOn: $isOn)
                .labelsHidden()
                .toggleStyle(.switch)
        }
        .frame(minHeight: 32)
        .contentShape(Rectangle())
    }
}
