import SwiftUI

/// Shared typography and text-contrast tokens for popovers and settings.
/// The menu-bar strip intentionally keeps its own compact sizing.
enum CatoshiType {
    static let tab: CGFloat = 13.0
    static let sectionTitle: CGFloat = 14.0
    static let cardTitle: CGFloat = 12.0
    static let rowTitle: CGFloat = 12.5
    static let body: CGFloat = 12.0
    static let secondary: CGFloat = 11.5
    static let metric: CGFloat = 13.3
    static let price: CGFloat = 18.0
    static let table: CGFloat = 11.1
    static let tableHeader: CGFloat = 10.8
    static let metadata: CGFloat = 10.5
    static let button: CGFloat = 11.5
    static let badge: CGFloat = 12.0
}

enum CatoshiTextTone {
    case primary
    case body
    case secondary
    case metadata
    case disabled
}

private struct CatoshiTextToneModifier: ViewModifier {
    let tone: CatoshiTextTone
    @Environment(\.colorScheme) private var colorScheme

    private var color: Color {
        if colorScheme == .dark {
            switch tone {
            case .primary: return .white.opacity(0.98)
            case .body: return .white.opacity(0.90)
            case .secondary: return .white.opacity(0.76)
            case .metadata: return .white.opacity(0.62)
            case .disabled: return .white.opacity(0.38)
            }
        }

        switch tone {
        case .primary: return .primary
        case .body: return .primary.opacity(0.90)
        case .secondary: return .primary.opacity(0.68)
        case .metadata: return .primary.opacity(0.56)
        case .disabled: return .primary.opacity(0.34)
        }
    }

    func body(content: Content) -> some View {
        content.foregroundStyle(color)
    }
}

extension View {
    func catoshiText(_ tone: CatoshiTextTone) -> some View {
        modifier(CatoshiTextToneModifier(tone: tone))
    }
}
