import Combine
import Foundation

/// Catoshi's render state is isolated from `MarketModel` so high-frequency motion does
/// not invalidate price, market-context or settings observers. Mutations are batched
/// through explicit methods, which avoids emitting several `objectWillChange` events
/// for a single pose transition.
@MainActor
final class CatoshiMotionModel {
    let objectWillChange = ObservableObjectPublisher()

    private(set) var state: CatoshiState = .idle
    private(set) var stateStartedAt: Date = Date()
    private(set) var positionX: CGFloat = 0
    private(set) var facing: CGFloat = 1
    private(set) var moveDuration: Double = 1.8
    private(set) var microMotion: CatoshiMicroMotion = .none
    private(set) var microActive = false

    func transition(to newState: CatoshiState, at date: Date = Date()) {
        objectWillChange.send()
        state = newState
        stateStartedAt = date
        microMotion = .none
        microActive = false
    }

    func restartAnimationClock(at date: Date = Date()) {
        objectWillChange.send()
        stateStartedAt = date
    }

    func setPosition(_ newPosition: CGFloat, duration: Double? = nil) {
        let positionChanged = abs(newPosition - positionX) > 0.001
        let durationChanged = duration.map { abs($0 - moveDuration) > 0.001 } ?? false
        guard positionChanged || durationChanged else { return }

        objectWillChange.send()
        positionX = newPosition
        if let duration { moveDuration = duration }
    }

    func setMoveDuration(_ duration: Double) {
        guard abs(duration - moveDuration) > 0.001 else { return }
        objectWillChange.send()
        moveDuration = duration
    }

    func setFacing(_ newFacing: CGFloat) {
        guard newFacing != facing else { return }
        objectWillChange.send()
        facing = newFacing
    }

    func setMicroMotion(_ motion: CatoshiMicroMotion, active: Bool) {
        guard microMotion != motion || microActive != active else { return }
        objectWillChange.send()
        microMotion = motion
        microActive = active
    }

    func clearMicroMotion() {
        setMicroMotion(.none, active: false)
    }

    func reset(positionX newPosition: CGFloat = 0, facing newFacing: CGFloat = 1) {
        objectWillChange.send()
        state = .idle
        stateStartedAt = Date()
        positionX = newPosition
        facing = newFacing
        moveDuration = 1.8
        microMotion = .none
        microActive = false
    }
}

// Swift 6.2 can express the actor isolation of a protocol conformance directly.
// Older Xcode/Swift toolchains that still build the Swift-tools-5.9 package use the
// legacy spelling, preserving source-build compatibility across supported Macs.
#if compiler(>=6.2)
extension CatoshiMotionModel: @MainActor ObservableObject {}
#else
extension CatoshiMotionModel: ObservableObject {}
#endif
