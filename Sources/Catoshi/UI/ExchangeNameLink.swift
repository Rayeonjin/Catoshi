import SwiftUI

struct ExchangeNameLink: View {
    let title: String
    let destination: URL
    let fontSize: CGFloat
    let tone: CatoshiTextTone
    let hint: String

    @State private var isHovered = false

    var body: some View {
        Link(destination: destination) {
            Text(title)
                .font(.system(size: isHovered ? fontSize + 2 : fontSize, weight: isHovered ? .bold : .medium))
                .catoshiText(tone)
                .lineLimit(1)
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .help(hint)
        .accessibilityLabel(hint)
    }
}
