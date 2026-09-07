import AppKit
import Foundation
import SwiftUI
import UniformTypeIdentifiers

enum CatoshiShareFormat: String, CaseIterable, Identifiable {
    case feed
    case story
    case square

    var id: String { rawValue }

    var pixelSize: NSSize {
        switch self {
        case .feed: return NSSize(width: 1080, height: 1350)
        case .story: return NSSize(width: 1080, height: 1920)
        case .square: return NSSize(width: 1080, height: 1080)
        }
    }

    func label(_ language: AppLanguage) -> String {
        switch self {
        case .feed: return language.pick("Instagram 피드", "Instagram Feed")
        case .story: return "Story"
        case .square: return language.pick("정사각형", "Square")
        }
    }

    var dimensionsLabel: String {
        "\(Int(pixelSize.width))×\(Int(pixelSize.height))"
    }
}

enum CatoshiShareSection: String {
    case prices
    case market
    case domestic
    case info

    func title(_ language: AppLanguage) -> String {
        switch self {
        case .prices: return language.pick("시세", "Price")
        case .market: return language.pick("시장", "Market")
        case .domestic: return language.pick("국내 거래소", "KR Exchanges")
        case .info: return language.pick("정보", "About")
        }
    }

    var filenameStem: String {
        switch self {
        case .prices: return "price"
        case .market: return "market"
        case .domestic: return "kr-exchanges"
        case .info: return "about"
        }
    }
}

struct CatoshiShareContent {
    let systemText: String
    let fullCaption: String
    let githubURL: URL
    let attributionURL: URL?
}

enum CatoshiShareSummary {
    static func text(for read: MarketRead, language: AppLanguage, format: CatoshiShareFormat) -> String {
        if fits(read.summary, format: format) { return read.summary }

        // Keep a complete core sentence and every compact signal, including risk
        // qualifiers that occur late in the full read. Never shrink the body font
        // or let a fixed drawing rectangle silently cut a sentence in half.
        var firstSentence = read.summary
        read.summary.enumerateSubstrings(in: read.summary.startIndex..., options: .bySentences) { sentence, _, _, stop in
            firstSentence = sentence?.trimmingCharacters(in: .whitespacesAndNewlines) ?? read.summary
            stop = true
        }
        let signals = read.badges.isEmpty ? "" : language.pick("함께 볼 신호: ", "Other signals: ")
            + read.badges.joined(separator: " · ") + "."
        let compact = [firstSentence, signals].filter { !$0.isEmpty }.joined(separator: " ")
        if fits(compact, format: format) { return compact }

        // The title already identifies the main regime. Keep all signal labels
        // if a future translation makes the first sentence unusually long.
        let fallback = signals.isEmpty
            ? language.pick("전체 시장 해석은 앱에서 확인하세요.", "See the full market read in the app.")
            : signals
        return fallback
    }

    static func fits(_ text: String, format: CatoshiShareFormat) -> Bool {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byWordWrapping
        paragraph.lineSpacing = 7
        let bounds = NSAttributedString(string: text, attributes: [
            .font: NSFont.systemFont(ofSize: 23, weight: .medium),
            .paragraphStyle: paragraph
        ]).boundingRect(with: NSSize(width: 864, height: CGFloat.greatestFiniteMagnitude),
                        options: [.usesLineFragmentOrigin, .usesFontLeading])
        return ceil(bounds.height) <= (format == .story ? 174 : 134) - 1
    }
}

enum CatoshiShareCaptionBuilder {
    static func content(section: CatoshiShareSection, language: AppLanguage, observation: String? = nil) -> CatoshiShareContent {
        let intro: String
        let hashtags: [String]

        switch section {
        case .prices:
            intro = language.pick(
                "BTC 시세와 김치프리미엄 현황 🐈",
                "BTC prices and the Kimchi Premium at a glance 🐈"
            )
            hashtags = language == .korean
                ? ["#Catoshi", "#Bitcoin", "#BTC", "#비트코인", "#김치프리미엄"]
                : ["#Catoshi", "#Bitcoin", "#BTC", "#KimchiPremium", "#macOS"]
        case .market:
            intro = language.pick(
                "BTC 시장 스냅샷 🐈",
                "A BTC market snapshot 🐈"
            )
            hashtags = language == .korean
                ? ["#Catoshi", "#Bitcoin", "#BTC", "#비트코인", "#CryptoMarket"]
                : ["#Catoshi", "#Bitcoin", "#BTC", "#CryptoMarket", "#macOS"]
        case .domestic:
            intro = language.pick(
                "국내 거래소 24h 거래대금과 현재 활동 🐈",
                "24h Korean-exchange trading share and current activity 🐈"
            )
            hashtags = language == .korean
                ? ["#Catoshi", "#Bitcoin", "#BTC", "#비트코인", "#국내거래소", "#김치프리미엄"]
                : ["#Catoshi", "#Bitcoin", "#BTC", "#KoreanExchanges", "#CryptoMarket", "#macOS"]
        case .info:
            intro = language.pick(
                "Mac 메뉴바에서 BTC 시세와 시장 흐름을 가볍게 확인합니다. 🐈",
                "A lightweight way to keep BTC and market context in the Mac menu bar. 🐈"
            )
            hashtags = language == .korean
                ? ["#Catoshi", "#Bitcoin", "#BTC", "#비트코인", "#macOS"]
                : ["#Catoshi", "#Bitcoin", "#BTC", "#macOS"]
        }

        let githubURL = CatoshiCommunity.githubRepositoryURL
        let telegramURL = CatoshiCommunity.telegramURL
        let appLine = language.pick("Catoshi for macOS · 비상업적 개인 사용 전용 · 무료 소스 공개", "Catoshi for macOS · Noncommercial personal use only · Free source-available project")
        let githubLine = "GitHub: \(githubURL.absoluteString)"
        let telegramLine = "Telegram: \(telegramURL.absoluteString)"
        let tagsLine = hashtags.joined(separator: " ")
        let attribution = CatoshiShareMetadata.attribution(section: section)
            + (section == .market ? "\nhttps://www.coingecko.com/" : "")
        let dataNote = CatoshiShareMetadata.dataNote(section: section, language: language)
        let details = [attribution, observation, dataNote].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: "\n")
        let systemText = [intro, "", details, "", appLine, telegramLine, "", tagsLine].joined(separator: "\n")
        let fullCaption = [intro, "", details, "", appLine, githubLine, telegramLine, "", tagsLine].joined(separator: "\n")

        return CatoshiShareContent(
            systemText: systemText,
            fullCaption: fullCaption,
            githubURL: githubURL,
            attributionURL: section == .market ? URL(string: "https://www.coingecko.com/") : nil
        )
    }
}

enum CatoshiShareMetadata {
    static func attribution(section: CatoshiShareSection) -> String {
        switch section {
        case .prices: return "Binance · Upbit | Catoshi"
        case .market: return "Powered by CoinGecko · coingecko.com | Binance · DeFiLlama · Farside Investors"
        case .domestic: return "Upbit · Bithumb · Coinone · Korbit · GOPAX | Catoshi"
        case .info: return "Catoshi · macOS · Noncommercial personal use only"
        }
    }

    static func dataNote(section: CatoshiShareSection, language: AppLanguage) -> String {
        switch section {
        case .prices:
            return language.pick("김치프리미엄: Catoshi 계산 · 마지막 수신값 · 투자 조언 아님", "Kimchi Premium: calculated by Catoshi · Last received values · Not investment advice")
        case .market:
            return language.pick("TOTAL3*·변화량: Catoshi 계산/추정 · 오래된 입력은 해석에서 제외 · 투자 조언 아님", "TOTAL3*/changes: Catoshi estimates · Stale inputs excluded from interpretation · Not investment advice")
        case .domestic:
            return language.pick("활동·상대비중: 24h 누적값 차분 추정 · 실제 단기 체결량과 다를 수 있음 · 투자 조언 아님", "Activity/share: estimates from changes in rolling 24h values; may differ from short-window trades · Not advice")
        case .info:
            return language.pick("비상업적 개인 사용 전용 · 데이터 제공자와 제휴/공식 승인 관계 없음", "Noncommercial personal use only · Not affiliated with or endorsed by data providers")
        }
    }

    static func time(_ date: Date?, full: Bool = false, timeZone: TimeZone = .current) -> String {
        guard let date else { return "--" }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = full ? "yyyy-MM-dd HH:mm:ss XXX" : "MM-dd HH:mm"
        return formatter.string(from: date)
    }

    static func etfDate(_ date: Date?, language: AppLanguage, now: Date) -> String {
        guard let date else { return language.pick("보고일 없음", "No report date") }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        let state = MarketInterpretationInputs.etfReportIsCurrent(date, now: now) ? "" : language.pick(" · 오래됨", " · Stale")
        return formatter.string(from: date) + state
    }

    static func domesticStatus(updatedAt: Date?, isPartial: Bool, issue: DomesticRefreshIssue?,
                               language: AppLanguage, now: Date) -> String {
        // A recent cached complete snapshot cannot clear a later refresh failure.
        switch issue {
        case .refreshFailed:
            return updatedAt == nil
                ? language.pick("갱신 실패 · 값 없음", "Refresh failed; no data")
                : language.pick("갱신 실패 · 이전값", "Refresh failed; retained")
        case .partialDataRetainingLastComplete:
            return language.pick("일부 누락 · 이전 전체값", "Partial; last complete")
        case .partialData:
            return language.pick("일부 누락", "Partial")
        case nil:
            guard let updatedAt,
                  MarketRefreshState.isCurrent(updatedAt, maximumAge: 20 * 60, now: now) else {
                return language.pick("오래됨/대기", "Stale/waiting")
            }
            return isPartial ? language.pick("일부 누락", "Partial") : language.pick("수신", "Received")
        }
    }

    @MainActor
    static func premiumUpdatedAt(_ model: MarketModel) -> Date? {
        guard let binance = model.binanceLastTickAt, let upbit = model.upbitLastTickAt else { return nil }
        return min(binance, upbit)
    }

    @MainActor
    static func observation(section: CatoshiShareSection, model: MarketModel, now: Date, fullTimestamps: Bool = false) -> String {
        let language = model.appLanguage
        let context = model.marketContext
        func observed(_ date: Date?) -> String { time(date, full: fullTimestamps) }
        func price(_ name: String, _ date: Date?, _ state: SocketConnectionState) -> String {
            let status = date.map { MarketRefreshState.isCurrent($0, maximumAge: 180, now: now) } == true
                ? state.label(language) : language.pick("오래됨/대기", "Stale/waiting")
            return "\(name) \(observed(date)) · \(status)"
        }
        switch section {
        case .prices:
            return price("Binance", model.binanceLastTickAt, model.binanceState) + " | "
                + price("Upbit", model.upbitLastTickAt, model.upbitState)
        case .market:
            return "CoinGecko \(observed(context.macro?.updatedAt)) · \(context.status(for: .macro, at: now).label(language)) | "
                + "Binance \(observed(context.fast?.updatedAt)) · \(context.status(for: .fast, at: now).label(language)) | "
                + "Investor \(observed(context.investor?.updatedAt)) · \(context.status(for: .investor, at: now).label(language))"
        case .domestic:
            let snapshot = context.domestic
            let status = domesticStatus(updatedAt: snapshot?.updatedAt, isPartial: snapshot?.isPartial == true,
                                        issue: context.domesticRefreshIssue, language: language, now: now)
            return language.pick("24h 관측 ", "24h observed ") + observed(snapshot?.updatedAt) + " · " + status
                + language.pick(" | 활동 측정 ", " | Activity measured ") + observed(context.domesticActivity?.updatedAt)
                + ((context.domesticActivity.map { MarketRefreshState.isCurrent($0.updatedAt, maximumAge: 20 * 60, now: now) } == true)
                    ? "" : language.pick(" · 오래됨/대기", " · Stale/waiting"))
        case .info:
            return CatoshiCommunity.githubRepositoryURL.absoluteString
        }
    }
}

@MainActor
struct CatoshiShareCardPopover: View {
    @ObservedObject var model: MarketModel
    let section: CatoshiShareSection

    @State private var format: CatoshiShareFormat = .feed
    @State private var statusMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(model.appLanguage.pick("공유 카드", "Share Card"))
                    .font(.system(size: CatoshiType.sectionTitle, weight: .semibold))
                Text(model.appLanguage.pick(
                    "마지막으로 수신한 \(section.title(model.appLanguage)) 데이터를 관측 시점과 함께 이미지로 만듭니다.",
                    "Create an image of the last received \(section.title(model.appLanguage)) data and its observation times."
                ))
                    .font(.system(size: CatoshiType.body))
                    .catoshiText(.secondary)
            }

            HStack(spacing: 6) {
                ForEach(CatoshiShareFormat.allCases) { item in
                    Button {
                        format = item
                        statusMessage = nil
                    } label: {
                        VStack(spacing: 2) {
                            Text(item.label(model.appLanguage))
                                .font(.system(size: CatoshiType.button, weight: format == item ? .semibold : .medium))
                            Text(item.dimensionsLabel)
                                .font(.system(size: CatoshiType.metadata, design: .monospaced))
                                .catoshiText(.metadata)
                        }
                        .frame(maxWidth: .infinity, minHeight: 42)
                    }
                    .buttonStyle(.plain)
                    .background {
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .fill(format == item ? Color.accentColor.opacity(0.18) : Color(nsColor: .controlBackgroundColor).opacity(0.72))
                    }
                    .overlay {
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .stroke(format == item ? Color.accentColor.opacity(0.55) : Color.secondary.opacity(0.18), lineWidth: 0.8)
                    }
                }
            }

            Divider()

            LazyVGrid(
                columns: Array(
                    repeating: GridItem(.flexible(), spacing: 7),
                    count: 2
                ),
                spacing: 7
            ) {
                Button {
                    perform(.copyImage)
                } label: {
                    Label(model.appLanguage.pick("이미지 복사", "Copy Image"), systemImage: "doc.on.doc")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)

                Button {
                    perform(.copyCaption)
                } label: {
                    Label(model.appLanguage.pick("캡션 복사", "Copy Caption"), systemImage: "text.quote")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)

                Button {
                    perform(.save)
                } label: {
                    Label(model.appLanguage.pick("이미지 저장", "Save Image"), systemImage: "square.and.arrow.down")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)

                Button {
                    perform(.share)
                } label: {
                    Label(model.appLanguage.pick("macOS 공유", "macOS Share"), systemImage: "square.and.arrow.up")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
            }
            .controlSize(.small)

            if let statusMessage {
                Text(statusMessage)
                    .font(.system(size: CatoshiType.metadata, weight: .medium))
                    .catoshiText(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Text(model.appLanguage.pick(
                "카드는 마지막 수신값·출처·관측 시점을 담습니다. 오래된 값은 상태를 표시하며 해석에서 제외합니다. 계산 지표는 추정값이며, 데이터 이용 조건은 제공자별로 적용됩니다.",
                "Cards include the last received values, sources and observation times. Stale inputs are labeled and excluded from interpretations. Derived metrics are estimates; provider terms apply to data use."
            ))
                .font(.system(size: CatoshiType.metadata))
                .catoshiText(.metadata)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .frame(width: 430)
    }

    private enum Action {
        case copyImage
        case copyCaption
        case save
        case share
    }

    private func perform(_ action: Action) {
        let now = Date()
        let shareContent = CatoshiShareCaptionBuilder.content(
            section: section, language: model.appLanguage,
            observation: CatoshiShareMetadata.observation(section: section, model: model, now: now, fullTimestamps: true)
        )

        if case .copyCaption = action {
            if CatoshiShareService.copy(text: shareContent.fullCaption) {
                statusMessage = model.appLanguage.pick("캡션과 해시태그를 복사했습니다.", "Caption and hashtags copied.")
            } else {
                statusMessage = model.appLanguage.pick("캡션을 복사하지 못했습니다.", "Could not copy the caption.")
            }
            return
        }

        guard let image = CatoshiShareCardRenderer.render(section: section, format: format, model: model, now: now) else {
            statusMessage = model.appLanguage.pick("공유 이미지를 만들지 못했습니다.", "Could not create the share image.")
            return
        }

        let filename = CatoshiShareService.suggestedFilename(section: section, format: format)
        switch action {
        case .copyImage:
            if CatoshiShareService.copy(image: image) {
                statusMessage = model.appLanguage.pick("이미지를 클립보드에 복사했습니다.", "Image copied to the clipboard.")
            } else {
                statusMessage = model.appLanguage.pick("클립보드에 복사하지 못했습니다.", "Could not copy the image.")
            }
        case .copyCaption:
            break
        case .save:
            do {
                let saved = try CatoshiShareService.save(image: image, suggestedFilename: filename)
                statusMessage = saved
                    ? model.appLanguage.pick("이미지를 저장했습니다.", "Image saved.")
                    : nil
            } catch {
                statusMessage = model.appLanguage.pick("이미지를 저장하지 못했습니다.", "Could not save the image.")
            }
        case .share:
            do {
                try CatoshiShareService.share(
                    image: image,
                    suggestedFilename: filename,
                    content: shareContent
                )
                statusMessage = nil
            } catch {
                statusMessage = model.appLanguage.pick("macOS 공유 메뉴를 열지 못했습니다.", "Could not open the macOS share menu.")
            }
        }
    }
}

@MainActor
enum CatoshiShareService {
    private static var activePicker: NSSharingServicePicker?
    static func suggestedFilename(section: CatoshiShareSection, format: CatoshiShareFormat, date: Date = Date()) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmm"
        return "Catoshi_\(section.filenameStem)_\(format.rawValue)_\(formatter.string(from: date)).png"
    }

    static func copy(image: NSImage) -> Bool {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        return pasteboard.writeObjects([image])
    }

    static func copy(text: String) -> Bool {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        return pasteboard.setString(text, forType: .string)
    }

    static func save(image: NSImage, suggestedFilename: String) throws -> Bool {
        guard let data = pngData(for: image) else { throw ShareError.encodingFailed }
        let panel = NSSavePanel()
        panel.title = "Save Catoshi Share Card"
        panel.nameFieldStringValue = suggestedFilename
        panel.allowedContentTypes = [.png]
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else { return false }
        try data.write(to: url, options: .atomic)
        return true
    }

    static func share(
        image: NSImage,
        suggestedFilename: String,
        content: CatoshiShareContent?
    ) throws {
        guard let data = pngData(for: image) else { throw ShareError.encodingFailed }
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("CatoshiShare", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        pruneTemporaryCards(in: directory)
        let url = directory.appendingPathComponent(UUID().uuidString + "_" + suggestedFilename)
        try data.write(to: url, options: .atomic)

        guard let anchor = NSApp.keyWindow?.contentView ?? NSApp.mainWindow?.contentView else {
            throw ShareError.missingAnchor
        }

        var items: [Any] = [url]
        if let content {
            items.append(content.systemText)
            items.append(content.githubURL)
            if let attributionURL = content.attributionURL { items.append(attributionURL) }
        }

        let picker = NSSharingServicePicker(items: items)
        activePicker = picker
        picker.show(relativeTo: anchor.bounds, of: anchor, preferredEdge: .minY)
    }

    private static func pruneTemporaryCards(in directory: URL, now: Date = Date()) {
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else { return }

        for file in files {
            guard let values = try? file.resourceValues(forKeys: [.contentModificationDateKey]),
                  let modified = values.contentModificationDate else { continue }
            if now.timeIntervalSince(modified) > 2 * 60 * 60 {
                try? FileManager.default.removeItem(at: file)
            }
        }
    }

    private static func pngData(for image: NSImage) -> Data? {
        // Renderer-created cards already carry an exact-pixel bitmap representation.
        // Encode that representation directly so a 1080×1920 card stays exactly that
        // size and we avoid an unnecessary TIFF round-trip/allocation.
        if let bitmap = image.representations.compactMap({ $0 as? NSBitmapImageRep }).max(by: {
            ($0.pixelsWide * $0.pixelsHigh) < ($1.pixelsWide * $1.pixelsHigh)
        }) {
            return bitmap.representation(using: .png, properties: [:])
        }
        guard let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff) else { return nil }
        return bitmap.representation(using: .png, properties: [:])
    }

    private enum ShareError: Error {
        case encodingFailed
        case missingAnchor
    }
}

@MainActor
enum CatoshiShareCardRenderer {
    private static let background = NSColor(calibratedRed: 0.045, green: 0.055, blue: 0.075, alpha: 1)
    private static let panel = NSColor(calibratedRed: 0.085, green: 0.105, blue: 0.14, alpha: 1)
    private static let panelAlt = NSColor(calibratedRed: 0.11, green: 0.13, blue: 0.17, alpha: 1)
    private static let primary = NSColor(calibratedWhite: 0.97, alpha: 1)
    private static let secondary = NSColor(calibratedWhite: 0.82, alpha: 1)
    private static let metadata = NSColor(calibratedWhite: 0.62, alpha: 1)
    private static let positive = NSColor.systemGreen
    private static let negative = NSColor.systemRed
    private static let accent = NSColor.systemOrange

    static func render(section: CatoshiShareSection, format: CatoshiShareFormat, model: MarketModel, now: Date = Date()) -> NSImage? {
        let size = format.pixelSize
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: Int(size.width),
            pixelsHigh: Int(size.height),
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ), let context = NSGraphicsContext(bitmapImageRep: rep) else { return nil }

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        background.setFill()
        NSRect(origin: .zero, size: size).fill()

        let canvas = Canvas(size: size)
        drawHeader(section: section, canvas: canvas, language: model.appLanguage)

        switch section {
        case .prices:
            drawPrices(model: model, canvas: canvas, format: format)
        case .market:
            drawMarket(model: model, canvas: canvas, format: format, now: now)
        case .domestic:
            drawDomestic(model: model, canvas: canvas, format: format, now: now)
        case .info:
            drawInfo(model: model, canvas: canvas, format: format)
        }

        drawFooter(section: section, model: model, canvas: canvas, now: now)
        context.flushGraphics()
        NSGraphicsContext.restoreGraphicsState()

        let image = NSImage(size: size)
        image.addRepresentation(rep)
        return image
    }

    private static func drawHeader(section: CatoshiShareSection, canvas: Canvas, language: AppLanguage) {
        canvas.text("Catoshi", top: 64, x: 72, width: 690, height: 72, font: .systemFont(ofSize: 54, weight: .bold), color: primary)
        canvas.text(section.title(language), top: 126, x: 74, width: 650, height: 48, font: .systemFont(ofSize: 29, weight: .semibold), color: secondary)

        let coats = CatoshiCoat.allCases
        let frames = ["idle", "sit", "loaf", "stretch", "happy", "groom"]
        if let coat = coats.randomElement(),
           let frame = frames.randomElement(),
           let cat = CatoshiAssets.sprite(named: frame, coat: coat) {
            canvas.image(cat, top: 54, x: 812, width: 190, height: 120)
        }
        canvas.line(top: 190, x: 72, width: 936, color: NSColor.white.withAlphaComponent(0.12))
    }

    private static func drawPrices(model: MarketModel, canvas: Canvas, format: CatoshiShareFormat) {
        let language = model.appLanguage
        let binanceValue = model.binanceBTC.map { formatUSD($0.price) } ?? "$---"
        let upbitValue = model.upbitBTC.map { formatKRW($0.price) } ?? "₩---"
        let premiumValue = model.premium.map { String(format: "%+.2f%%", $0.value) } ?? "--"
        let premiumColor: NSColor = (model.premium?.value ?? 0) >= 0 ? positive : negative

        if format == .story {
            canvas.metricTile(
                top: 300, x: 72, width: 936, height: 270,
                label: "Binance · BTC/USDT", value: binanceValue,
                detail: model.binanceBTC?.change24h.map { "24h \(formatPercent($0))" } ?? "24h --",
                valueColor: primary
            )
            canvas.metricTile(
                top: 602, x: 72, width: 936, height: 270,
                label: "Upbit · BTC/KRW", value: upbitValue,
                detail: model.upbitBTC?.change24h.map { "24h \(formatPercent($0))" } ?? "24h --",
                valueColor: primary
            )
            canvas.metricTile(
                top: 904, x: 72, width: 936, height: 290,
                label: language.pick("김치프리미엄", "Kimchi Premium"),
                value: premiumValue,
                detail: model.fiveMinuteChange.map { "BTC 5m \(formatPercent($0))" } ?? "BTC 5m --",
                valueColor: premiumColor
            )
            canvas.text(
                language.pick("Binance와 Upbit의 공개 시세를 기준으로 계산합니다.", "Calculated from public Binance and Upbit market data."),
                top: 1248, x: 82, width: 916, height: 90,
                font: .systemFont(ofSize: 27, weight: .medium), color: secondary
            )
            return
        }

        canvas.metricTile(
            top: 232, x: 72, width: 450, height: 250,
            label: "Binance · BTC/USDT", value: binanceValue,
            detail: model.binanceBTC?.change24h.map { "24h \(formatPercent($0))" } ?? "24h --",
            valueColor: primary
        )
        canvas.metricTile(
            top: 232, x: 558, width: 450, height: 250,
            label: "Upbit · BTC/KRW", value: upbitValue,
            detail: model.upbitBTC?.change24h.map { "24h \(formatPercent($0))" } ?? "24h --",
            valueColor: primary
        )
        canvas.metricTile(
            top: 518, x: 72, width: 936, height: 250,
            label: language.pick("김치프리미엄", "Kimchi Premium"),
            value: premiumValue,
            detail: model.fiveMinuteChange.map { "BTC 5m \(formatPercent($0))" } ?? "BTC 5m --",
            valueColor: premiumColor
        )

        canvas.text(
            language.pick("Binance와 Upbit의 공개 시세를 기준으로 계산합니다.", "Calculated from public Binance and Upbit market data."),
            top: 814, x: 82, width: 916, height: 90,
            font: .systemFont(ofSize: 26, weight: .medium), color: secondary
        )
    }

    private static func drawMarket(model: MarketModel, canvas: Canvas, format: CatoshiShareFormat, now: Date) {
        let language = model.appLanguage
        let context = model.marketContext
        let read = makeMarketRead(
            macro: context.macro,
            fast: context.fast,
            investor: context.investor,
            freshness: context.freshness,
            premium: model.premium,
            btcChange24h: model.binanceBTC?.change24h,
            btcChange5m: model.fiveMinuteChange,
            language: language,
            btcUpdatedAt: model.binanceLastTickAt,
            premiumUpdatedAt: CatoshiShareMetadata.premiumUpdatedAt(model),
            now: now
        )

        let summaryTop: CGFloat = format == .story ? 286 : 226
        let summaryHeight: CGFloat = format == .story ? 290 : 250
        canvas.roundedPanel(top: summaryTop, x: 72, width: 936, height: summaryHeight, radius: 28, color: panel)
        canvas.text(read.title, top: summaryTop + 32, x: 108, width: 864, height: 48, font: .systemFont(ofSize: 34, weight: .bold), color: toneColor(read.tone))
        canvas.text(CatoshiShareSummary.text(for: read, language: language, format: format), top: summaryTop + 94, x: 108, width: 864, height: summaryHeight - 116, font: .systemFont(ofSize: 23, weight: .medium), color: secondary, lineSpacing: 7)

        let metrics: [(String, String, String)] = [
            ("BTC.D", context.macro.map { String(format: "%.1f%%", $0.btcDominance) } ?? "--", context.macro?.btcDominanceChange24hPP.map { String(format: "%+.2f%%p", $0) } ?? "24h --"),
            ("TOTAL3*", context.macro.map { formatUSDMarketCap($0.total3USD) } ?? "--", context.macro?.total3Change24h.map { String(format: "%+.1f%%", $0) } ?? "24h --"),
            ("USDT.D", context.macro.map { String(format: "%.1f%%", $0.usdtDominance) } ?? "--", context.macro?.usdtDominanceChange24hPP.map { String(format: "%+.2f%%p", $0) } ?? "24h --"),
            ("ETH/BTC", context.fast.map { String(format: "%.4f", $0.ethBTC) } ?? "--", context.fast.map { String(format: "%+.2f%%", $0.ethBTCChange24h) } ?? "24h --"),
            ("BTC ETF 5D", context.investor?.etfFiveDayFlowUSD.map(formatSignedUSDFlow) ?? "--", CatoshiShareMetadata.etfDate(context.investor?.etfFlowDate, language: language, now: now)),
            ("Funding", context.fast?.fundingRatePercent.map { String(format: "%+.3f%%", $0) } ?? "--", language.pick("레버리지", "Leverage"))
        ]

        let count = format == .square ? 4 : 6
        let tileWidth: CGFloat = 450
        let tileHeight: CGFloat = format == .story ? 210 : 182
        let startTop: CGFloat = format == .story ? 620 : 514
        for (index, metric) in metrics.prefix(count).enumerated() {
            let row = index / 2
            let col = index % 2
            canvas.metricTile(
                top: startTop + CGFloat(row) * (tileHeight + (format == .story ? 34 : 26)),
                x: col == 0 ? 72 : 558,
                width: tileWidth,
                height: tileHeight,
                label: metric.0,
                value: metric.1,
                detail: metric.2,
                valueColor: primary,
                compact: true
            )
        }
    }

    private static func drawDomestic(model: MarketModel, canvas: Canvas, format: CatoshiShareFormat, now: Date) {
        let language = model.appLanguage
        let context = model.marketContext
        let activity = context.domesticActivity
        let volume = context.domestic
        let activityIsCurrent = activity.map { MarketRefreshState.isCurrent($0.updatedAt, maximumAge: 20 * 60, now: now) } == true
        let availability = Dictionary(uniqueKeysWithValues: context.domesticAvailability.map { ($0.exchange, $0.state) })

        // Share cards should read like a compact market snapshot, not a screenshot of
        // the in-app layout. Activity and 24h volume therefore share one horizontal
        // band. The detailed table below doubles as the donut legend, so there is no
        // duplicated legend beside the chart.
        let contentTop: CGFloat
        let bandHeight: CGFloat
        let activityWidth: CGFloat
        let interCardGap: CGFloat
        let pieDiameter: CGFloat
        switch format {
        case .story:
            contentTop = 276
            bandHeight = 480
            activityWidth = 286
            interCardGap = 20
            pieDiameter = 380
        case .feed:
            contentTop = 216
            bandHeight = 400
            activityWidth = 320
            interCardGap = 18
            pieDiameter = 340
        case .square:
            contentTop = 216
            bandHeight = 380
            activityWidth = 300
            interCardGap = 18
            pieDiameter = 340
        }

        let activityX: CGFloat = 72
        let volumeX = activityX + activityWidth + interCardGap
        let volumeWidth = 936 - activityWidth - interCardGap

        canvas.roundedPanel(top: contentTop, x: activityX, width: activityWidth, height: bandHeight, radius: 28, color: panel)
        let activityInset: CGFloat = format == .story ? 34 : 30
        let activityTitleSize: CGFloat = format == .story ? 30 : 27
        let activityBodySize: CGFloat = format == .story ? 23 : 20
        canvas.text(
            activity != nil && !activityIsCurrent
                ? language.pick("활동 · 마지막 측정", "Activity · Last observation")
                : domesticPhaseTitle(activity, language: language),
            top: contentTop + (format == .story ? 48 : 38),
            x: activityX + activityInset,
            width: activityWidth - activityInset * 2,
            height: 72,
            font: .systemFont(ofSize: activityTitleSize, weight: .bold),
            color: primary,
            lineSpacing: 4
        )
        canvas.text(
            activityIsCurrent ? domesticSummary(activity: activity, availability: availability, language: language)
                : language.pick("활동 해석 보류 · 아래 수치는 마지막 측정값입니다. 관측 시점을 확인하세요.", "Activity read paused. Values below are the last observations; check their timestamps."),
            top: contentTop + (format == .story ? 142 : 118),
            x: activityX + activityInset,
            width: activityWidth - activityInset * 2,
            height: bandHeight - (format == .story ? 184 : 154),
            font: .systemFont(ofSize: activityBodySize, weight: .medium),
            color: secondary,
            lineSpacing: format == .story ? 7 : 6
        )

        canvas.roundedPanel(top: contentTop, x: volumeX, width: volumeWidth, height: bandHeight, radius: 28, color: panelAlt)
        let pieTop = contentTop + (bandHeight - pieDiameter) / 2
        let pieX = volumeX + (format == .story ? 22 : 20)
        let completeVolume = volume.flatMap { snapshot -> DomesticVolumeSnapshot? in
            guard !snapshot.isPartial, !snapshot.entries.isEmpty, snapshot.total > 0 else { return nil }
            return snapshot
        }
        let infoX = pieX + pieDiameter + (format == .story ? 20 : 18)
        let infoWidth = volumeX + volumeWidth - (format == .story ? 24 : 22) - infoX

        if let completeVolume {
            let sortedEntries = completeVolume.entries.sorted { $0.krw24h > $1.krw24h }
            canvas.donutChart(
                entries: sortedEntries,
                total: completeVolume.total,
                top: pieTop,
                x: pieX,
                diameter: pieDiameter,
                holeRatio: 0.57
            )
            canvas.text(
                "24h",
                top: pieTop + pieDiameter * 0.30,
                x: pieX + pieDiameter * 0.18,
                width: pieDiameter * 0.64,
                height: 34,
                font: .systemFont(ofSize: format == .story ? 28 : 24, weight: .semibold),
                color: metadata,
                alignment: .center
            )
            canvas.text(
                formatKRWTradingValue(completeVolume.total, language: language),
                top: pieTop + pieDiameter * 0.45,
                x: pieX + pieDiameter * 0.08,
                width: pieDiameter * 0.84,
                height: 52,
                font: .monospacedDigitSystemFont(ofSize: format == .story ? 34 : 30, weight: .bold),
                color: primary,
                alignment: .center
            )

            canvas.text(
                language.pick("24h 거래대금 비중", "24h Trading Share"),
                top: contentTop + (format == .story ? 104 : 86),
                x: infoX,
                width: infoWidth,
                height: 72,
                font: .systemFont(ofSize: format == .story ? 27 : 23, weight: .bold),
                color: primary,
                lineSpacing: 3
            )
            canvas.text(
                language.pick("5개 거래소 합계", "Five-exchange total"),
                top: contentTop + (format == .story ? 190 : 164),
                x: infoX,
                width: infoWidth,
                height: 34,
                font: .systemFont(ofSize: format == .story ? 20 : 17, weight: .medium),
                color: secondary
            )
            canvas.text(
                language.pick("업데이트\n\(formatTime(completeVolume.updatedAt))", "Updated\n\(formatTime(completeVolume.updatedAt))"),
                top: contentTop + (format == .story ? 236 : 208),
                x: infoX,
                width: infoWidth,
                height: 64,
                font: .monospacedDigitSystemFont(ofSize: format == .story ? 18 : 15, weight: .medium),
                color: metadata,
                lineSpacing: 3
            )
        } else {
            canvas.emptyDonut(top: pieTop, x: pieX, diameter: pieDiameter, holeRatio: 0.57)
            canvas.text(
                "24h",
                top: pieTop + pieDiameter * 0.30,
                x: pieX + pieDiameter * 0.18,
                width: pieDiameter * 0.64,
                height: 34,
                font: .systemFont(ofSize: format == .story ? 28 : 24, weight: .semibold),
                color: metadata,
                alignment: .center
            )
            canvas.text(
                "--",
                top: pieTop + pieDiameter * 0.45,
                x: pieX + pieDiameter * 0.08,
                width: pieDiameter * 0.84,
                height: 52,
                font: .monospacedDigitSystemFont(ofSize: format == .story ? 34 : 30, weight: .bold),
                color: secondary,
                alignment: .center
            )
            canvas.text(
                language.pick("24h 거래대금 비중", "24h Trading Share"),
                top: contentTop + (format == .story ? 92 : 78),
                x: infoX,
                width: infoWidth,
                height: 72,
                font: .systemFont(ofSize: format == .story ? 27 : 23, weight: .bold),
                color: primary,
                lineSpacing: 3
            )
            canvas.text(
                language.pick("일부 거래소 데이터가 없어 합계와 파이차트를 표시하지 않습니다.", "The total and pie chart are withheld while some exchange data is unavailable."),
                top: contentTop + (format == .story ? 180 : 160),
                x: infoX,
                width: infoWidth,
                height: bandHeight - (format == .story ? 220 : 196),
                font: .systemFont(ofSize: format == .story ? 19 : 16, weight: .medium),
                color: secondary,
                lineSpacing: 5
            )
        }

        let headerTop: CGFloat
        let rowTop: CGFloat
        let rowHeight: CGFloat
        let panelInset: CGFloat
        switch format {
        case .story:
            headerTop = contentTop + bandHeight + 38
            rowTop = headerTop + 42
            rowHeight = 118
            panelInset = 10
        case .feed:
            headerTop = contentTop + bandHeight + 30
            rowTop = headerTop + 38
            rowHeight = 88
            panelInset = 8
        case .square:
            headerTop = contentTop + bandHeight + 20
            rowTop = headerTop + 32
            rowHeight = 58
            panelInset = 6
        }

        canvas.text(language.pick("거래소", "Exchange"), top: headerTop, x: 102, width: 180, height: 30, font: .systemFont(ofSize: 18, weight: .semibold), color: metadata)
        canvas.text(language.pick("상태", "State"), top: headerTop, x: 286, width: 196, height: 30, font: .systemFont(ofSize: 18, weight: .semibold), color: metadata)
        canvas.text(language.pick("활동", "Activity"), top: headerTop, x: 498, width: 84, height: 30, font: .systemFont(ofSize: 18, weight: .semibold), color: metadata, alignment: .right)
        canvas.text(language.pick("상대비중 Δ", "Share Δ"), top: headerTop, x: 596, width: 124, height: 30, font: .systemFont(ofSize: 18, weight: .semibold), color: metadata, alignment: .right)
        canvas.text(language.pick("24h 비중 · 거래대금", "24h Share · Value"), top: headerTop, x: 734, width: 240, height: 30, font: .systemFont(ofSize: 18, weight: .semibold), color: metadata, alignment: .right)

        let volumeMap = Dictionary(uniqueKeysWithValues: (volume?.entries ?? []).map { ($0.exchange, $0) })
        for (index, exchange) in DomesticExchange.allCases.enumerated() {
            let top = rowTop + CGFloat(index) * rowHeight
            canvas.roundedPanel(top: top, x: 72, width: 936, height: rowHeight - panelInset, radius: format == .square ? 14 : 20, color: index.isMultiple(of: 2) ? panel : panelAlt)

            let state = availability[exchange] ?? .unknown
            let activityEntry = activity?.entry(for: exchange)
            let volumeEntry = volumeMap[exchange]
            let share = volumeEntry.flatMap { volume?.share(for: $0) }
            let amount = volumeEntry.map { formatKRWTradingValue($0.krw24h, language: language) }

            let exchangeFont: CGFloat = format == .story ? 27 : (format == .square ? 18 : 23)
            let stateFont: CGFloat = format == .story ? 22 : (format == .square ? 15 : 18)
            let metricFont: CGFloat = format == .story ? 26 : (format == .square ? 17 : 21)
            let deltaFont: CGFloat = format == .story ? 24 : (format == .square ? 16 : 19)
            let amountFont: CGFloat = format == .story ? 21 : (format == .square ? 14 : 17)
            let mainTop: CGFloat = top + (rowHeight - panelInset - (format == .square ? 24 : 34)) / 2
            let mainHeight: CGFloat = format == .square ? 24 : 34

            canvas.dot(top: mainTop + (format == .square ? 7 : 9), x: 102, diameter: format == .square ? 9 : 11, color: domesticExchangeColor(exchange))
            canvas.text(exchange.label, top: mainTop, x: 120, width: 162, height: mainHeight, font: .systemFont(ofSize: exchangeFont, weight: .semibold), color: primary)
            canvas.text(domesticStateText(state: state, activity: activityEntry, language: language), top: mainTop + 1, x: 286, width: 196, height: mainHeight, font: .systemFont(ofSize: stateFont, weight: .medium), color: state == .maintenance ? accent : secondary)
            canvas.text(activityEntry?.activityRatio.map(formatActivityRatio) ?? "--", top: mainTop, x: 498, width: 84, height: mainHeight, font: .monospacedDigitSystemFont(ofSize: metricFont, weight: .semibold), color: primary, alignment: .right)
            canvas.text(activityEntry?.shareDeltaPP.map { String(format: "%+.1f%%p", $0) } ?? "--", top: mainTop, x: 596, width: 124, height: mainHeight, font: .monospacedDigitSystemFont(ofSize: deltaFont, weight: .medium), color: secondary, alignment: .right)

            // Share and amount stay on one visual line. Two independently aligned
            // subcolumns preserve the numeric axis while the table itself remains the
            // single legend for the donut above.
            // 100.0% needs 97 px at the Story font size; reserve the unit's width.
            canvas.text(share.map { String(format: "%.1f%%", $0) } ?? "--", top: mainTop, x: 734, width: 104, height: mainHeight, font: .monospacedDigitSystemFont(ofSize: metricFont, weight: .semibold), color: primary, alignment: .right)
            canvas.text("·", top: mainTop, x: 842, width: 12, height: mainHeight, font: .systemFont(ofSize: amountFont, weight: .medium), color: metadata, alignment: .center)
            canvas.text(amount ?? "--", top: mainTop, x: 858, width: 116, height: mainHeight, font: .monospacedDigitSystemFont(ofSize: amountFont, weight: .medium), color: metadata, alignment: .right)
        }
    }

    private static func domesticExchangeColor(_ exchange: DomesticExchange) -> NSColor {
        switch exchange {
        case .upbit: return .systemBlue
        case .bithumb: return .systemOrange
        case .coinone: return .systemPurple
        case .korbit: return .systemTeal
        case .gopax: return .systemYellow
        }
    }

    private static func drawInfo(model: MarketModel, canvas: Canvas, format: CatoshiShareFormat) {
        let language = model.appLanguage
        canvas.roundedPanel(top: 236, x: 72, width: 936, height: 230, radius: 28, color: panel)
        canvas.text(
            language.pick("가볍게 보는 BTC 메뉴바 모니터", "A lightweight BTC menu-bar monitor"),
            top: 274, x: 108, width: 864, height: 48,
            font: .systemFont(ofSize: 34, weight: .bold), color: primary
        )
        canvas.text(
            language.pick(
                "Binance와 Upbit 시세, 김치프리미엄, 시장 분위기와 국내 거래소 활동을 필요한 순간에 확인합니다.",
                "Check Binance and Upbit prices, the Kimchi Premium, market context and Korean-exchange activity when you need them."
            ),
            top: 338, x: 108, width: 864, height: 94,
            font: .systemFont(ofSize: 24, weight: .medium), color: secondary, lineSpacing: 7
        )

        let features = [
            language.pick("BTC/USDT · BTC/KRW · 김치프리미엄", "BTC/USDT · BTC/KRW · Kimchi Premium"),
            language.pick("시장 구조 · 유동성 · 현물 수요 · 레버리지", "Market structure · liquidity · spot demand · leverage"),
            language.pick("국내 거래소 Activity Radar", "Korean-exchange Activity Radar"),
            language.pick("로그인/API Key/지갑 연결 없음", "No login, API key or wallet connection"),
            language.pick("메뉴바에서 살아가는 Catoshi", "A Catoshi living in your menu bar")
        ]
        var top: CGFloat = format == .story ? 580 : 520
        let visibleFeatures = format == .square ? Array(features.prefix(4)) : features
        let featureSpacing: CGFloat = format == .story ? 82 : 64
        for feature in visibleFeatures {
            canvas.text("•", top: top, x: 108, width: 40, height: 38, font: .systemFont(ofSize: 27, weight: .bold), color: accent)
            canvas.text(feature, top: top, x: 150, width: 820, height: 44, font: .systemFont(ofSize: 25, weight: .medium), color: secondary)
            top += featureSpacing
        }

        let infoPanelHeight: CGFloat = format == .square ? 132 : 160
        canvas.roundedPanel(top: top + 20, x: 72, width: 936, height: infoPanelHeight, radius: 24, color: panelAlt)
        canvas.text(language.pick("제작자", "Developer"), top: top + 52, x: 108, width: 180, height: 34, font: .systemFont(ofSize: 21, weight: .medium), color: metadata)
        canvas.text(CatoshiCommunity.developerDisplayName, top: top + 48, x: 300, width: 620, height: 42, font: .systemFont(ofSize: 27, weight: .semibold), color: primary)
        canvas.text(language.pick("지원 환경", "Requires"), top: top + 100, x: 108, width: 180, height: 34, font: .systemFont(ofSize: 21, weight: .medium), color: metadata)
        canvas.text("macOS 13+ · v\(AppMetadata.version)", top: top + 96, x: 300, width: 620, height: 42, font: .monospacedDigitSystemFont(ofSize: 24, weight: .medium), color: secondary)
    }

    private static func drawFooter(section: CatoshiShareSection, model: MarketModel, canvas: Canvas, now: Date) {
        let language = model.appLanguage
        let top = canvas.size.height - 132
        canvas.line(top: top - 8, x: 72, width: 936, color: NSColor.white.withAlphaComponent(0.16))
        // Embedded source text is readable in the PNG; the matching URL is also
        // included in the caption and as a link item in the macOS sharing picker.
        canvas.text(CatoshiShareMetadata.attribution(section: section), top: top, x: 72, width: 936, height: 25,
                    font: .systemFont(ofSize: section == .market ? 18 : 16, weight: .semibold), color: secondary)
        canvas.text(CatoshiShareMetadata.observation(section: section, model: model, now: now),
                    top: top + 28, x: 72, width: 936, height: 40,
                    font: .systemFont(ofSize: 14, weight: .medium), color: secondary, lineSpacing: 2)
        canvas.text(CatoshiShareMetadata.dataNote(section: section, language: language),
                    top: top + 72, x: 72, width: 936, height: 25,
                    font: .systemFont(ofSize: 14, weight: .medium), color: metadata)
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss z"
        canvas.text(language.pick("Catoshi · 생성 ", "Catoshi · Created ") + formatter.string(from: now)
                    + language.pick(" · 모든 관측 시각은 같은 시간대", " · All observation times use this timezone"),
                    top: top + 104, x: 72, width: 936, height: 23,
                    font: .systemFont(ofSize: 14, weight: .medium), color: metadata)
    }

    private static func toneColor(_ tone: MarketReadTone) -> NSColor {
        switch tone {
        case .constructive: return positive
        case .caution: return accent
        case .riskOff: return negative
        case .neutral: return primary
        }
    }

    private static func domesticPhaseTitle(_ snapshot: DomesticActivitySnapshot?, language: AppLanguage) -> String {
        guard let snapshot else { return language.pick("현재 활동 · 측정 중", "Current Activity · Measuring") }
        switch snapshot.phase {
        case .measuring: return language.pick("현재 활동 · 측정 중", "Current Activity · Measuring")
        case .quickEstimate(let minutes): return language.pick("현재 활동 · 빠른 추정 \(minutes)m", "Current Activity · Quick \(minutes)m")
        case .fifteenMinute: return language.pick("현재 활동 · 15m", "Current Activity · 15m")
        }
    }

    private static func domesticSummary(
        activity: DomesticActivitySnapshot?,
        availability: [DomesticExchange: DomesticExchangeDataState],
        language: AppLanguage
    ) -> String {
        let maintenance = availability.compactMap { $0.value == .maintenance ? $0.key.label : nil }.sorted()
        let unavailable = availability.compactMap { $0.value == .unavailable ? $0.key.label : nil }.sorted()
        if !maintenance.isEmpty || !unavailable.isEmpty {
            let first = !maintenance.isEmpty ? maintenance.joined(separator: ", ") + language.pick(" 점검 중", " under maintenance") : unavailable.joined(separator: ", ") + language.pick(" 수신 불가", " unavailable")
            return language.pick("\(first) · 나머지 거래소 활동은 계속 측정합니다.", "\(first) · Other venues continue measuring activity.")
        }
        guard let activity else { return language.pick("활동 기준을 수집하고 있습니다.", "Collecting the activity baseline.") }
        let usable = activity.entries.filter { ($0.activityRatio ?? 0).isFinite && $0.activityRatio != nil }
        if let strongest = usable.max(by: { ($0.activityRatio ?? 0) < ($1.activityRatio ?? 0) }) {
            switch strongest.level {
            case .surging: return language.pick("\(strongest.exchange.label) 활동이 크게 증가했습니다.", "\(strongest.exchange.label) activity is surging.")
            case .elevated: return language.pick("\(strongest.exchange.label) 활동이 기준보다 증가했습니다.", "\(strongest.exchange.label) activity is above baseline.")
            default: break
            }
        }
        return language.pick("뚜렷한 거래소 활동 급증 신호는 없습니다.", "There is no clear exchange-activity surge signal.")
    }

    private static func domesticStateText(
        state: DomesticExchangeDataState,
        activity: DomesticExchangeActivity?,
        language: AppLanguage
    ) -> String {
        switch state {
        case .maintenance: return language.pick("점검 중", "Maintenance")
        case .unavailable: return language.pick("수신 불가", "Unavailable")
        case .unknown: return language.pick("확인 중", "Checking")
        case .available:
            guard let activity else { return language.pick("측정 중", "Measuring") }
            let prefix = activity.baselineIntervals >= 4 ? "" : language.pick("잠정 ", "Provisional ")
            return prefix + activity.level.label(language)
        }
    }

    private static func formatActivityRatio(_ ratio: Double) -> String {
        if ratio < 0.1 { return "<0.1×" }
        if ratio >= 10 { return String(format: "%.0f×", ratio) }
        return String(format: "%.1f×", ratio)
    }

    @MainActor
    private struct Canvas {
        let size: NSSize

        func rect(top: CGFloat, x: CGFloat, width: CGFloat, height: CGFloat) -> NSRect {
            NSRect(x: x, y: size.height - top - height, width: width, height: height)
        }

        func roundedPanel(top: CGFloat, x: CGFloat, width: CGFloat, height: CGFloat, radius: CGFloat, color: NSColor) {
            color.setFill()
            NSBezierPath(roundedRect: rect(top: top, x: x, width: width, height: height), xRadius: radius, yRadius: radius).fill()
        }

        func line(top: CGFloat, x: CGFloat, width: CGFloat, color: NSColor) {
            color.setFill()
            rect(top: top, x: x, width: width, height: 2).fill()
        }

        func dot(top: CGFloat, x: CGFloat, diameter: CGFloat, color: NSColor) {
            color.setFill()
            NSBezierPath(ovalIn: rect(top: top, x: x, width: diameter, height: diameter)).fill()
        }

        func donutChart(
            entries: [DomesticExchangeVolume],
            total: Double,
            top: CGFloat,
            x: CGFloat,
            diameter: CGFloat,
            holeRatio: CGFloat
        ) {
            guard total > 0, !entries.isEmpty else {
                emptyDonut(top: top, x: x, diameter: diameter, holeRatio: holeRatio)
                return
            }

            let bounds = rect(top: top, x: x, width: diameter, height: diameter)
            let center = NSPoint(x: bounds.midX, y: bounds.midY)
            let radius = diameter / 2
            var startAngle: CGFloat = 90

            for entry in entries {
                let sweep = CGFloat(max(0, entry.krw24h / total)) * 360
                let endAngle = startAngle - sweep
                let path = NSBezierPath()
                path.move(to: center)
                path.appendArc(
                    withCenter: center,
                    radius: radius,
                    startAngle: startAngle,
                    endAngle: endAngle,
                    clockwise: true
                )
                path.close()
                CatoshiShareCardRenderer.domesticExchangeColor(entry.exchange).setFill()
                path.fill()
                startAngle = endAngle
            }

            let holeDiameter = diameter * max(0.1, min(0.9, holeRatio))
            CatoshiShareCardRenderer.panelAlt.setFill()
            NSBezierPath(
                ovalIn: NSRect(
                    x: center.x - holeDiameter / 2,
                    y: center.y - holeDiameter / 2,
                    width: holeDiameter,
                    height: holeDiameter
                )
            ).fill()
        }

        func emptyDonut(top: CGFloat, x: CGFloat, diameter: CGFloat, holeRatio: CGFloat) {
            let bounds = rect(top: top, x: x, width: diameter, height: diameter)
            NSColor.white.withAlphaComponent(0.10).setFill()
            NSBezierPath(ovalIn: bounds).fill()

            let holeDiameter = diameter * max(0.1, min(0.9, holeRatio))
            CatoshiShareCardRenderer.panelAlt.setFill()
            NSBezierPath(
                ovalIn: NSRect(
                    x: bounds.midX - holeDiameter / 2,
                    y: bounds.midY - holeDiameter / 2,
                    width: holeDiameter,
                    height: holeDiameter
                )
            ).fill()
        }

        func image(_ image: NSImage, top: CGFloat, x: CGFloat, width: CGFloat, height: CGFloat) {
            let destination = rect(top: top, x: x, width: width, height: height)
            let aspect = image.size.width / max(1, image.size.height)
            var drawWidth = destination.width
            var drawHeight = drawWidth / aspect
            if drawHeight > destination.height {
                drawHeight = destination.height
                drawWidth = drawHeight * aspect
            }
            let drawRect = NSRect(
                x: destination.midX - drawWidth / 2,
                y: destination.midY - drawHeight / 2,
                width: drawWidth,
                height: drawHeight
            )
            image.draw(in: drawRect, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: false, hints: [.interpolation: NSImageInterpolation.high])
        }

        func text(
            _ string: String,
            top: CGFloat,
            x: CGFloat,
            width: CGFloat,
            height: CGFloat,
            font: NSFont,
            color: NSColor,
            alignment: NSTextAlignment = .left,
            lineSpacing: CGFloat = 3
        ) {
            let paragraph = NSMutableParagraphStyle()
            paragraph.alignment = alignment
            paragraph.lineBreakMode = .byWordWrapping
            paragraph.lineSpacing = lineSpacing
            let attributes: [NSAttributedString.Key: Any] = [
                .font: font,
                .foregroundColor: color,
                .paragraphStyle: paragraph
            ]
            NSAttributedString(string: string, attributes: attributes)
                .draw(with: rect(top: top, x: x, width: width, height: height), options: [.usesLineFragmentOrigin, .usesFontLeading])
        }

        func metricTile(
            top: CGFloat,
            x: CGFloat,
            width: CGFloat,
            height: CGFloat,
            label: String,
            value: String,
            detail: String,
            valueColor: NSColor,
            compact: Bool = false
        ) {
            roundedPanel(top: top, x: x, width: width, height: height, radius: compact ? 22 : 28, color: panel)
            text(label, top: top + 28, x: x + 32, width: width - 64, height: 36, font: .systemFont(ofSize: compact ? 21 : 24, weight: .semibold), color: metadata)
            text(value, top: top + (compact ? 70 : 82), x: x + 32, width: width - 64, height: compact ? 54 : 70, font: .monospacedDigitSystemFont(ofSize: compact ? 35 : 48, weight: .bold), color: valueColor)
            text(detail, top: top + (compact ? 128 : 170), x: x + 32, width: width - 64, height: 36, font: .monospacedDigitSystemFont(ofSize: compact ? 20 : 22, weight: .medium), color: secondary)
        }
    }
}
