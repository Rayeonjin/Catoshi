import Foundation

struct FreshValue<Value> {
    let value: Value
    let receivedAt: Date

    func remaining(at now: Date, lifetime: TimeInterval) -> TimeInterval {
        let age = now.timeIntervalSince(receivedAt)
        guard age.isFinite, age >= 0 else { return 0 }
        return max(0, lifetime - age)
    }
}

struct VenueRetryState {
    private(set) var failureCount = 0
    private(set) var failedAt: Date?
    private(set) var state: DomesticExchangeDataState = .unknown

    mutating func record(_ state: DomesticExchangeDataState, at date: Date) {
        self.state = state
        if state == .available {
            failureCount = 0
            failedAt = nil
        } else {
            failureCount = min(failureCount + 1, 3)
            failedAt = date
        }
    }

    func shouldRetry(at now: Date, force: Bool) -> Bool {
        guard !force, let failedAt else { return true }
        let age = now.timeIntervalSince(failedAt)
        let delay: TimeInterval = failureCount <= 1 ? 180 : failureCount == 2 ? 300 : 900
        return age < 0 || age >= delay
    }
}

struct SparklineSelection: Equatable {
    var binance: Bool
    var upbit: Bool
    var premium: Bool
    static let all = Self(binance: true, upbit: true, premium: true)
    var isEmpty: Bool { !binance && !upbit && !premium }
}
