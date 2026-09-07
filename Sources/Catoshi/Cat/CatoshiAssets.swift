import AppKit
import Foundation
import SwiftUI

private struct CatoshiAtlasFrame {
    let x: CGFloat
    let width: CGFloat
    let height: CGFloat
}

private enum CatoshiAtlasCatalog {
    static let frames: [String: CatoshiAtlasFrame] = [
        "idle": .init(x: 0, width: 59, height: 40),
        "sit": .init(x: 61, width: 32, height: 40),
        "loaf": .init(x: 95, width: 81, height: 40),
        "stretch": .init(x: 178, width: 54, height: 40),
        "groom": .init(x: 234, width: 36, height: 40),
        "sleep": .init(x: 272, width: 77, height: 40),
        "happy": .init(x: 351, width: 64, height: 40),
        "zoom1": .init(x: 417, width: 82, height: 40),
        "zoom2": .init(x: 501, width: 86, height: 40),
        "run1": .init(x: 589, width: 65, height: 40),
        "run2": .init(x: 656, width: 65, height: 40),
        "scared": .init(x: 723, width: 61, height: 40),
        "flee": .init(x: 786, width: 98, height: 40),
        // Dedicated turn sequence derived from the coat's own idle/front/walk art.
        // The narrow side frames lead into a front-facing pivot, hiding the mirror
        // change at menu-bar scale instead of flipping a full-width cat in place.
        "turn1": .init(x: 886, width: 45, height: 40),
        "turn2": .init(x: 933, width: 32, height: 40),
        "turn3": .init(x: 967, width: 45, height: 40),
        // Four-phase walking gait. The body silhouette stays stable while the paw
        // groups alternate far enough to remain legible after 40 px art is rendered
        // at menu-bar scale.
        "walk1": .init(x: 1014, width: 59, height: 40),
        "walk2": .init(x: 1075, width: 59, height: 40),
        "walk3": .init(x: 1136, width: 59, height: 40),
        "walk4": .init(x: 1197, width: 59, height: 40),
        "idleBlink": .init(x: 1258, width: 59, height: 40),
        "idleEar": .init(x: 1319, width: 59, height: 40),
        "idleTail": .init(x: 1380, width: 59, height: 40),
        "sitBlink": .init(x: 1441, width: 32, height: 40),
        "sitEar": .init(x: 1475, width: 32, height: 40),
        "sitTail": .init(x: 1509, width: 32, height: 40),
        "loafBlink": .init(x: 1543, width: 81, height: 40)
    ]
}

@MainActor
private final class CatoshiAtlasStore {
    static let shared = CatoshiAtlasStore()

    private let atlasCache: NSCache<NSString, NSImage> = {
        let cache = NSCache<NSString, NSImage>()
        cache.countLimit = 2
        cache.totalCostLimit = 1_000_000
        return cache
    }()

    private let previewCache: NSCache<NSString, NSImage> = {
        let cache = NSCache<NSString, NSImage>()
        cache.countLimit = 12
        return cache
    }()

    func atlas(for coat: CatoshiCoat) -> NSImage? {
        let key = coat.rawValue as NSString
        if let image = atlasCache.object(forKey: key) { return image }
        guard let url = Bundle.main.url(forResource: coat.atlasResourceName, withExtension: "png"),
              let image = NSImage(contentsOf: url) else { return nil }
        let cost = Int(image.size.width * image.size.height * 4)
        atlasCache.setObject(image, forKey: key, cost: cost)
        return image
    }

    /// Settings previews are sparse and tiny. Crop only when requested and keep a very
    /// small cache; the menu-bar animation itself draws directly from the atlas.
    func previewImage(frame name: String, coat: CatoshiCoat) -> NSImage? {
        let cacheKey = "\(coat.rawValue):\(name)" as NSString
        if let image = previewCache.object(forKey: cacheKey) { return image }
        guard let atlas = atlas(for: coat), let meta = CatoshiAtlasCatalog.frames[name] else { return nil }
        let source = NSRect(x: meta.x, y: 0, width: meta.width, height: meta.height)
        let output = NSImage(size: NSSize(width: meta.width, height: meta.height))
        output.lockFocus()
        atlas.draw(
            in: NSRect(x: 0, y: 0, width: meta.width, height: meta.height),
            from: source,
            operation: .sourceOver,
            fraction: 1,
            respectFlipped: false,
            hints: [.interpolation: NSImageInterpolation.high]
        )
        output.unlockFocus()
        previewCache.setObject(output, forKey: cacheKey)
        return output
    }
}

@MainActor
enum CatoshiAssets {
    @MainActor
    static func sprite(named frame: String, coat: CatoshiCoat = .calico) -> NSImage? {
        CatoshiAtlasStore.shared.previewImage(frame: frame, coat: coat)
    }
}

@MainActor
private final class CatoshiAtlasNSView: NSView {
    var coat: CatoshiCoat = .calico { didSet { needsDisplay = true } }
    var frameName: String = "idle" { didSet { needsDisplay = true } }

    override var isOpaque: Bool { false }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard let atlas = CatoshiAtlasStore.shared.atlas(for: coat),
              let meta = CatoshiAtlasCatalog.frames[frameName] else { return }

        let aspect = meta.width / meta.height
        var drawHeight = bounds.height
        var drawWidth = drawHeight * aspect
        if drawWidth > bounds.width {
            drawWidth = bounds.width
            drawHeight = drawWidth / aspect
        }
        let destination = NSRect(
            x: (bounds.width - drawWidth) / 2,
            y: (bounds.height - drawHeight) / 2,
            width: drawWidth,
            height: drawHeight
        )
        atlas.draw(
            in: destination,
            from: NSRect(x: meta.x, y: 0, width: meta.width, height: meta.height),
            operation: .sourceOver,
            fraction: 1,
            respectFlipped: false,
            hints: [.interpolation: NSImageInterpolation.high]
        )
    }
}

private struct CatoshiAtlasSprite: NSViewRepresentable {
    let coat: CatoshiCoat
    let frameName: String

    func makeNSView(context: Context) -> CatoshiAtlasNSView {
        let view = CatoshiAtlasNSView(frame: .zero)
        view.coat = coat
        view.frameName = frameName
        return view
    }

    func updateNSView(_ nsView: CatoshiAtlasNSView, context: Context) {
        if nsView.coat != coat { nsView.coat = coat }
        if nsView.frameName != frameName { nsView.frameName = frameName }
    }
}

struct CatoshiMenuMascot: View {
    static let layoutWidth: CGFloat = 78

    let state: CatoshiState
    let coat: CatoshiCoat
    let animationEnabled: Bool
    let stateStartedAt: Date
    let basePositionX: CGFloat
    let facing: CGFloat
    let moveDuration: Double
    let microMotion: CatoshiMicroMotion
    let microActive: Bool
    let language: AppLanguage

    private func elapsed(at date: Date) -> Double {
        max(0, date.timeIntervalSince(stateStartedAt))
    }

    private func frameIndex(at date: Date) -> Int {
        let frames = state.frameSequence
        guard frames.count > 1 else { return 0 }

        // Ordinary walking is advanced by the same discrete position steps that move
        // the cat across the menu bar. This removes the second TimelineView clock that
        // could drift from horizontal motion and makes every paw phase correspond to
        // actual travel.
        if state == .walk {
            let phaseDistance = max(CGFloat(1.0), CGFloat(state.travelPointsPerFrame))
            return Int((abs(basePositionX) / phaseDistance).rounded()) % frames.count
        }

        guard state.framesPerSecond > 0 else { return 0 }
        return Int(elapsed(at: date) * state.framesPerSecond) % frames.count
    }

    private func baseFrameName(at date: Date) -> String {
        let frames = state.frameSequence
        guard !frames.isEmpty else { return "idle" }
        return frames[min(frameIndex(at: date), frames.count - 1)]
    }

    private func microFrameOverride() -> String? {
        guard animationEnabled, microActive else { return nil }
        switch (state, microMotion) {
        case (.idle, .blink): return "idleBlink"
        case (.idle, .earTwitch): return "idleEar"
        case (.idle, .tailFlick): return "idleTail"
        case (.sit, .blink): return "sitBlink"
        case (.sit, .earTwitch): return "sitEar"
        case (.sit, .tailFlick): return "sitTail"
        case (.loaf, .blink): return "loafBlink"
        default: return nil
        }
    }

    private func frameName(at date: Date) -> String {
        microFrameOverride() ?? baseFrameName(at: date)
    }

    private func phasedMotion(
        _ phases: [(y: CGFloat, rotation: Double)],
        frameIndex: Int,
        scaleX: CGFloat = 1,
        scaleY: CGFloat = 1
    ) -> (x: CGFloat, y: CGFloat, rotation: Double, flip: CGFloat, sx: CGFloat, sy: CGFloat) {
        let phase = phases[frameIndex % phases.count]
        return (0, phase.y, phase.rotation, facing, scaleX, scaleY)
    }

    private func activeMotion(at date: Date) -> (x: CGFloat, y: CGFloat, rotation: Double, flip: CGFloat, sx: CGFloat, sy: CGFloat) {
        let t = elapsed(at: date)
        let index = frameIndex(at: date)
        guard animationEnabled else { return (0, 0, 0, facing, 1, 1) }

        switch state {
        case .walk:
            // Bobbing is keyed to the same four phases that drive paw placement and
            // horizontal displacement. There is no second sine-wave clock to drift.
            return phasedMotion(
                [(0.00, -0.25), (-0.55, 0.25), (0.00, 0.20), (-0.45, -0.20)],
                frameIndex: index
            )
        case .turn:
            return phasedMotion(
                [(0.10, -0.35), (0.20, 0.0), (0.10, 0.35)],
                frameIndex: index,
                scaleY: 0.995
            )
        case .standUp:
            return phasedMotion(
                [(0.25, 0.0), (-0.20, -0.25), (0.00, 0.0)],
                frameIndex: index
            )
        case .sitDown:
            return phasedMotion(
                [(0.00, 0.0), (0.15, 0.20), (0.30, 0.0)],
                frameIndex: index
            )
        case .stretch:
            return (0, -CGFloat(sin(min(t / 1.2, 1) * .pi)) * 0.7, -sin(t * 2.4) * 0.8, facing, 1.01, 0.99)
        case .groom:
            return (CGFloat(sin(t * 2.1)) * 0.45, -CGFloat(abs(sin(t * 4.0))) * 0.35, sin(t * 2.8) * 1.0, facing, 1, 1)
        case .happy:
            return phasedMotion(
                [(-0.3, -0.8), (-1.35, 0.9), (-0.2, 0.7), (-1.15, -0.7)],
                frameIndex: index,
                scaleX: 1.01
            )
        case .zoomies:
            return phasedMotion(
                [(0.0, -0.5), (-1.25, 0.5), (-0.15, -0.25), (-1.35, 0.45), (0.0, -0.45), (-1.15, 0.35)],
                frameIndex: index,
                scaleX: 1.01,
                scaleY: 0.99
            )
        case .rocket:
            return phasedMotion(
                [(-0.2, -1.1), (-1.8, 1.2), (-0.3, -0.7), (-1.7, 1.1), (-0.1, -1.0), (-1.6, 0.8)],
                frameIndex: index,
                scaleX: 1.02,
                scaleY: 0.98
            )
        case .alert:
            return (0, -CGFloat(abs(sin(t * 2.2))) * 0.25, sin(t * 1.8) * 0.7, facing, 1, 1)
        case .scared:
            return (CGFloat(sin(t * 16.0)) * 0.8, 0, sin(t * 13.0) * 1.4, facing, 0.995, 1.01)
        case .flee:
            return phasedMotion(
                [(0.0, 0.0), (-1.05, 0.25), (-0.15, -0.15), (-1.15, 0.20), (-0.05, 0.0)],
                frameIndex: index,
                scaleX: 1.01,
                scaleY: 0.99
            )
        default:
            return microTransform()
        }
    }

    private func microTransform() -> (x: CGFloat, y: CGFloat, rotation: Double, flip: CGFloat, sx: CGFloat, sy: CGFloat) {
        guard microActive else { return (0, 0, 0, facing, 1, 1) }
        switch microMotion {
        case .none, .blink, .earTwitch, .tailFlick:
            // These motions now live in actual sprite frames rather than whole-body
            // rotation/scaling tricks.
            return (0, 0, 0, facing, 1, 1)
        case .breathe:
            return (0, -0.20, 0, facing, 1.003, 1.022)
        case .settle:
            return (0, 0.25, 0, facing, 1.015, 0.985)
        }
    }

    @ViewBuilder
    private func renderedMascot(at date: Date) -> some View {
        let m = activeMotion(at: date)
        ZStack {
            if state == .rocket && animationEnabled {
                Text("✦")
                    .font(.system(size: 7, weight: .bold))
                    .foregroundStyle(.orange)
                    .offset(x: 24, y: -7)
            }

            CatoshiAtlasSprite(coat: coat, frameName: frameName(at: date))
                .frame(width: 60, height: 20)
                .scaleEffect(x: m.flip * m.sx, y: m.sy)
                .rotationEffect(.degrees(m.rotation))
                .offset(x: m.x, y: m.y)
        }
        .frame(width: Self.layoutWidth, height: 20)
        .clipped()
    }

    var body: some View {
        // Do not instantiate TimelineView at all for idle/static poses or ordinary walk.
        // Walking is already advanced by position steps; a paused timeline still adds an
        // unnecessary scheduling/render layer to the always-on status item.
        let animateWithTimeline = animationEnabled && state.needsTimeline && state != .walk
        Group {
            if animateWithTimeline {
                let timelineInterval = state.framesPerSecond > 0
                    ? max(0.10, 1.0 / state.framesPerSecond)
                    : 0.25
                TimelineView(.animation(minimumInterval: timelineInterval)) { context in
                    renderedMascot(at: context.date)
                }
            } else {
                renderedMascot(at: stateStartedAt)
            }
        }
        .frame(width: Self.layoutWidth, height: 20)
        .offset(x: basePositionX)
        .animation(state == .walk ? nil : .linear(duration: max(0.06, moveDuration)), value: basePositionX)
        .animation(.easeInOut(duration: microMotion == .breathe ? 1.15 : 0.18), value: microActive)
        .accessibilityLabel("Catoshi")
        .accessibilityValue(state.label(language))
    }
}

