import Foundation

enum DomesticActivityLevel: Int, Equatable {
    case warmingUp
    case normal
    case elevated
    case surging

    func label(_ language: AppLanguage) -> String {
        switch self {
        case .warmingUp:
            return language.pick("측정 중", "Measuring")
        case .normal:
            return language.pick("평소", "Normal")
        case .elevated:
            return language.pick("증가", "Elevated")
        case .surging:
            return language.pick("급증", "Surging")
        }
    }

    var symbol: String {
        switch self {
        case .warmingUp: return "·"
        case .normal: return "●"
        case .elevated: return "▲"
        case .surging: return "▲▲"
        }
    }
}

enum DomesticActivityPhase: Equatable {
    case measuring
    case quickEstimate(minutes: Int)
    case fifteenMinute
}

struct DomesticExchangeActivity: Identifiable, Equatable {
    let exchange: DomesticExchange
    let activityRatio: Double?
    let shareDeltaPP: Double?
    let level: DomesticActivityLevel
    let baselineIntervals: Int

    var id: String { exchange.rawValue }
}

struct DomesticActivitySnapshot: Equatable {
    let entries: [DomesticExchangeActivity]
    let updatedAt: Date
    let baselineIntervals: Int
    let phase: DomesticActivityPhase
    let isApproximation: Bool

    func entry(for exchange: DomesticExchange) -> DomesticExchangeActivity? {
        entries.first { $0.exchange == exchange }
    }
}

/// Lightweight activity radar built from exchange-wide public 24h KRW turnover snapshots.
///
/// The radar does not block the UI until a full local baseline exists. It starts with a
/// short-window estimate after roughly 2-5 minutes, switches to a rolling 15-minute
/// observation as soon as that window exists, and progressively blends in locally observed
/// 15-minute history. The fallback baseline is the venue's current 24h
/// turnover normalized to the observation duration. This keeps startup useful without
/// fanning out into per-market candle/trade requests or permanent all-market WebSockets.
///
/// This remains an activity-acceleration proxy rather than exact 15-minute traded value,
/// because rolling 24h totals can lose old turnover while new turnover enters the window.
@MainActor
final class DomesticActivityRadarEngine {
    private struct StoredSample: Codable, Sendable {
        let timestamp: Date
        let values: [String: Double]
    }

    private let interval: TimeInterval = 15 * 60
    private let quickTarget: TimeInterval = 3 * 60
    private let quickMinimum: TimeInterval = 2 * 60
    private let quickMaximum: TimeInterval = 6 * 60
    private let historyWindow: TimeInterval = 6.5 * 60 * 60
    private let intervalTolerance: TimeInterval = 4 * 60
    private let minimumStableBaselineIntervals = 4
    private let targetBaselineIntervals = 20
    private let persistInterval: TimeInterval = 12 * 60
    // A mature 15m reading should not disappear merely because the user opens the tab
    // between sparse background sample boundaries. Keep the last computed result only
    // for a bounded period; after sleep/network gaps it expires and warm-up becomes honest again.
    private let retainedFifteenMinuteMaxAge: TimeInterval = 22 * 60
    private let retainedQuickEstimateMaxAge: TimeInterval = 7 * 60

    /// During a cold start we temporarily collect one lightweight aggregate sample every
    /// three minutes. After a rolling 15-minute window exists, background cadence falls back
    /// to the normal 15 minutes. A visible Domestic tab still uses the model's 1-minute cadence.
    let warmStartBackgroundCadence: TimeInterval = 3 * 60
    let steadyBackgroundCadence: TimeInterval = 15 * 60

    private var samples: [StoredSample] = []
    private var lastPersistedAt: Date?
    private var latestObservationComplete = false
    private var latestDisplaySnapshot: DomesticActivitySnapshot?
    private let historyURL: URL?
    private let persistenceQueue = DispatchQueue(label: "Catoshi.ActivityRadarPersistence", qos: .utility)

    init() {
        let fm = FileManager.default
        if let base = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
            let directory = base.appendingPathComponent("Catoshi", isDirectory: true)
            try? fm.createDirectory(at: directory, withIntermediateDirectories: true)
            // Keep the established history filename so activity baselines survive app upgrades.
            historyURL = directory.appendingPathComponent("domestic_activity_history_v1.json")
        } else {
            historyURL = nil
        }
        loadHistory()
        restoreLatestDisplaySnapshotFromHistory()
    }

    /// Ingests one aggregate exchange snapshot and materializes the radar result immediately.
    /// This is intentionally independent from popover visibility: the Domestic tab displays an
    /// already-running measurement instead of becoming the thing that starts measurement.
    func ingest(_ snapshot: DomesticVolumeSnapshot) -> DomesticActivitySnapshot {
        record(snapshot)
        return analyzeAndRetain(current: snapshot)
    }

    func latestSnapshot(now: Date = Date()) -> DomesticActivitySnapshot? {
        guard let latestDisplaySnapshot else { return nil }
        guard isRetainable(latestDisplaySnapshot, at: now) else { return nil }
        return latestDisplaySnapshot
    }

    private func record(_ snapshot: DomesticVolumeSnapshot) {
        let values = Dictionary(uniqueKeysWithValues: snapshot.entries.map { ($0.exchange.rawValue, $0.krw24h) })
        latestObservationComplete = hasCompleteVenueSet(values)
        guard !values.isEmpty else { return }

        let sample = StoredSample(timestamp: snapshot.updatedAt, values: values)
        if let last = samples.last, abs(last.timestamp.timeIntervalSince(sample.timestamp)) < 30 {
            samples[samples.count - 1] = sample
        } else {
            samples.append(sample)
        }
        prune(relativeTo: snapshot.updatedAt)

        let shouldPersist = lastPersistedAt.map {
            snapshot.updatedAt.timeIntervalSince($0) >= persistInterval
        } ?? true
        if shouldPersist {
            persistHistory(now: snapshot.updatedAt)
        }
    }

    /// Chooses the lowest background cadence needed for a useful startup experience.
    /// This only affects aggregate exchange snapshots; it never enables per-market streams.
    func preferredBackgroundCadence(now: Date = Date()) -> TimeInterval {
        // Stay on the temporary warm-start cadence until both the latest sample and a real
        // ~15-minute reference contain all five venues. After an outage recovers, this keeps
        // sampling every three minutes long enough for the recovered venue to rebuild its own
        // 15m comparison instead of immediately dropping back to a 15-minute sleep.
        guard latestObservationComplete,
              let latest = samples.last,
              hasCompleteVenueSet(latest.values),
              let reference15 = fifteenMinuteReferenceSample(now: now),
              hasCompleteVenueSet(reference15.values) else {
            return warmStartBackgroundCadence
        }
        return steadyBackgroundCadence
    }

    private func analyzeAndRetain(current snapshot: DomesticVolumeSnapshot) -> DomesticActivitySnapshot {
        let now = snapshot.updatedAt
        let currentValues = Dictionary(uniqueKeysWithValues: snapshot.entries.map { ($0.exchange.rawValue, $0.krw24h) })
        let candidate = analyzeRaw(now: now, currentValues: currentValues)

        if let previous = latestDisplaySnapshot,
           phaseRank(candidate.phase) < phaseRank(previous.phase),
           isRetainable(previous, at: now) {
            // Sparse 15m background sampling means an arbitrary foreground fetch can land
            // between reference boundaries. Do not visually reset a mature measurement to
            // Measuring/Quick merely because the tab was opened at that moment.
            return previous
        }

        latestDisplaySnapshot = candidate
        return candidate
    }

    private func analyzeRaw(
        now: Date,
        currentValues: [String: Double]
    ) -> DomesticActivitySnapshot {
        if let previous15 = fifteenMinuteReferenceSample(now: now) {
            return analyzeFifteenMinute(
                now: now,
                currentValues: currentValues,
                previous15: previous15
            )
        }

        if let quickSample = quickReferenceSample(now: now) {
            return analyzeQuickEstimate(
                now: now,
                currentValues: currentValues,
                previous: quickSample
            )
        }

        return measuringSnapshot(now: now)
    }

    func flush() {
        persistHistory(now: Date(), force: true)
    }

    private func analyzeQuickEstimate(
        now: Date,
        currentValues: [String: Double],
        previous: StoredSample
    ) -> DomesticActivitySnapshot {
        let elapsed = max(quickMinimum, now.timeIntervalSince(previous.timestamp))
        let currentActivity = activityAmounts(end: currentValues, start: previous.values)
        let shareComparisonAvailable = hasCompleteVenueSet(currentValues)
            && hasCompleteVenueSet(previous.values)
            && hasCompleteActivitySet(currentActivity)
        let currentShares = shareComparisonAvailable ? shares(for: currentActivity) : [:]
        let dailyShares = shareComparisonAvailable ? sharesForRawValues(currentValues) : [:]
        let observationMinutes = max(2, Int((elapsed / 60).rounded()))

        var result: [DomesticExchangeActivity] = []
        result.reserveCapacity(DomesticExchange.allCases.count)

        for exchange in DomesticExchange.allCases {
            let currentAmount = currentActivity[exchange]
            let baseline = normalizedDailyBaseline(
                exchange: exchange,
                values: currentValues,
                duration: elapsed
            )
            let ratio = activityRatio(current: currentAmount, baseline: baseline)

            let shareDelta: Double?
            if let currentShare = currentShares[exchange], let referenceShare = dailyShares[exchange] {
                shareDelta = currentShare - referenceShare
            } else {
                shareDelta = nil
            }

            let level = classify(
                ratio: ratio,
                shareDeltaPP: shareDelta,
                stableBaseline: false,
                quickEstimate: true
            )

            result.append(
                DomesticExchangeActivity(
                    exchange: exchange,
                    activityRatio: ratio,
                    shareDeltaPP: shareDelta,
                    level: level,
                    baselineIntervals: 0
                )
            )
        }

        return DomesticActivitySnapshot(
            entries: result,
            updatedAt: now,
            baselineIntervals: 0,
            phase: .quickEstimate(minutes: observationMinutes),
            isApproximation: true
        )
    }

    private func analyzeFifteenMinute(
        now: Date,
        currentValues: [String: Double],
        previous15: StoredSample
    ) -> DomesticActivitySnapshot {
        let elapsed = max(60, now.timeIntervalSince(previous15.timestamp))
        let currentActivity = activityAmounts(end: currentValues, start: previous15.values)
        let shareComparisonAvailable = hasCompleteVenueSet(currentValues)
            && hasCompleteVenueSet(previous15.values)
            && hasCompleteActivitySet(currentActivity)
        let currentShares = shareComparisonAvailable ? shares(for: currentActivity) : [:]
        let dailyShares = shareComparisonAvailable ? sharesForRawValues(currentValues) : [:]

        var previousIntervals: [[DomesticExchange: Double]] = []
        previousIntervals.reserveCapacity(targetBaselineIntervals)

        for offset in 1...targetBaselineIntervals {
            let endTarget = now.addingTimeInterval(-Double(offset) * interval)
            let startTarget = now.addingTimeInterval(-Double(offset + 1) * interval)
            guard let endSample = sample(near: endTarget, tolerance: intervalTolerance),
                  let startSample = sample(near: startTarget, tolerance: intervalTolerance),
                  endSample.timestamp > startSample.timestamp else {
                continue
            }
            previousIntervals.append(activityAmounts(end: endSample.values, start: startSample.values))
        }

        // Local activity baselines are per venue and can safely use partial intervals.
        // Relative-share history cannot: changing the denominator when one venue disappears
        // would manufacture a false +pp/-pp move. Only complete five-venue intervals qualify.
        let completeShareIntervals = previousIntervals.filter(hasCompleteActivitySet)
        let previousShares = shareComparisonAvailable
            ? (completeShareIntervals.first.map(shares(for:)) ?? [:])
            : [:]
        let shareHistoryWeight = shareComparisonAvailable
            ? min(1, Double(completeShareIntervals.count) / Double(minimumStableBaselineIntervals))
            : 0

        var result: [DomesticExchangeActivity] = []
        result.reserveCapacity(DomesticExchange.allCases.count)
        var baselineDepths: [Int] = []

        for exchange in DomesticExchange.allCases {
            let history = previousIntervals.compactMap { $0[exchange] }
            let baselineDepth = history.count
            baselineDepths.append(baselineDepth)

            let fallbackBaseline = normalizedDailyBaseline(
                exchange: exchange,
                values: currentValues,
                duration: elapsed
            )
            let localAverage = history.isEmpty ? nil : history.reduce(0, +) / Double(history.count)
            let localWeight = min(1, Double(baselineDepth) / Double(minimumStableBaselineIntervals))
            let blendedBaseline = blend(
                fallback: fallbackBaseline,
                local: localAverage,
                localWeight: localWeight
            )
            let ratio = activityRatio(current: currentActivity[exchange], baseline: blendedBaseline)

            let referenceShare: Double?
            if let dailyShare = dailyShares[exchange] {
                if let previousShare = previousShares[exchange] {
                    referenceShare = dailyShare * (1 - shareHistoryWeight) + previousShare * shareHistoryWeight
                } else {
                    referenceShare = dailyShare
                }
            } else {
                referenceShare = previousShares[exchange]
            }

            let shareDelta: Double?
            if let currentShare = currentShares[exchange], let referenceShare {
                shareDelta = currentShare - referenceShare
            } else {
                shareDelta = nil
            }

            let level = classify(
                ratio: ratio,
                shareDeltaPP: shareDelta,
                stableBaseline: baselineDepth >= minimumStableBaselineIntervals,
                quickEstimate: false
            )

            result.append(
                DomesticExchangeActivity(
                    exchange: exchange,
                    activityRatio: ratio,
                    shareDeltaPP: shareDelta,
                    level: level,
                    baselineIntervals: baselineDepth
                )
            )
        }

        let sortedDepths = baselineDepths.sorted()
        let globalDepth = sortedDepths.isEmpty ? 0 : sortedDepths[sortedDepths.count / 2]
        return DomesticActivitySnapshot(
            entries: result,
            updatedAt: now,
            baselineIntervals: globalDepth,
            phase: .fifteenMinute,
            isApproximation: true
        )
    }

    private func measuringSnapshot(now: Date) -> DomesticActivitySnapshot {
        let entries = DomesticExchange.allCases.map {
            DomesticExchangeActivity(
                exchange: $0,
                activityRatio: nil,
                shareDeltaPP: nil,
                level: .warmingUp,
                baselineIntervals: 0
            )
        }
        return DomesticActivitySnapshot(
            entries: entries,
            updatedAt: now,
            baselineIntervals: 0,
            phase: .measuring,
            isApproximation: true
        )
    }

    private func classify(
        ratio: Double?,
        shareDeltaPP: Double?,
        stableBaseline: Bool,
        quickEstimate: Bool
    ) -> DomesticActivityLevel {
        guard let ratio else { return .warmingUp }

        // When one venue is unavailable, cross-venue Relative Share Delta is intentionally
        // absent because the denominator is incomplete. Keep the available venues useful by
        // falling back to stricter ratio-only thresholds rather than freezing the whole radar.
        if shareDeltaPP == nil {
            if quickEstimate {
                if ratio >= 3.0 { return .surging }
                if ratio >= 2.0 { return .elevated }
                return .normal
            }
            if stableBaseline {
                if ratio >= 2.5 { return .surging }
                if ratio >= 1.8 { return .elevated }
                return .normal
            }
            if ratio >= 2.8 { return .surging }
            if ratio >= 2.0 { return .elevated }
            return .normal
        }

        let shareDelta = shareDeltaPP ?? 0

        // Early estimates deliberately use stricter gates because their baseline is a
        // 24h pace normalization rather than a mature local 15-minute history.
        if quickEstimate {
            if ratio >= 2.5, shareDelta >= 1.0 { return .surging }
            if ratio >= 1.8, shareDelta >= 0.5 { return .elevated }
            return .normal
        }

        if stableBaseline {
            if ratio >= 2.0, shareDelta >= 0.5 { return .surging }
            if ratio >= 1.5, shareDelta > 0 { return .elevated }
            return .normal
        }

        // A full 15-minute observation is already useful before four local baseline
        // intervals exist, but keep the gates slightly conservative until history matures.
        if ratio >= 2.4, shareDelta >= 0.8 { return .surging }
        if ratio >= 1.7, shareDelta >= 0.3 { return .elevated }
        return .normal
    }

    private func activityRatio(current: Double?, baseline: Double?) -> Double? {
        guard let current, let baseline, current.isFinite, baseline.isFinite, baseline > 1 else { return nil }
        return min(max(0, current / baseline), 9.99)
    }

    private func normalizedDailyBaseline(
        exchange: DomesticExchange,
        values: [String: Double],
        duration: TimeInterval
    ) -> Double? {
        guard let daily = values[exchange.rawValue], daily.isFinite, daily > 0 else { return nil }
        return daily * max(60, duration) / (24 * 60 * 60)
    }

    private func blend(fallback: Double?, local: Double?, localWeight: Double) -> Double? {
        switch (fallback, local) {
        case let (.some(fallback), .some(local)):
            let weight = min(max(localWeight, 0), 1)
            return fallback * (1 - weight) + local * weight
        case let (.some(fallback), .none):
            return fallback
        case let (.none, .some(local)):
            return local
        case (.none, .none):
            return nil
        }
    }

    private func activityAmounts(
        end: [String: Double],
        start: [String: Double]
    ) -> [DomesticExchange: Double] {
        var result: [DomesticExchange: Double] = [:]
        for exchange in DomesticExchange.allCases {
            guard let current = end[exchange.rawValue],
                  let previous = start[exchange.rawValue],
                  current.isFinite, previous.isFinite else { continue }
            // 24h totals are rolling on some venues. A negative delta means more old
            // turnover left the 24h window than new turnover entered it; for a surge
            // detector that contributes zero rather than becoming "negative volume".
            result[exchange] = max(0, current - previous)
        }
        return result
    }


    private func hasCompleteVenueSet(_ values: [String: Double]) -> Bool {
        DomesticExchange.allCases.allSatisfy { exchange in
            guard let value = values[exchange.rawValue] else { return false }
            return value.isFinite && value >= 0
        }
    }

    private func hasCompleteActivitySet(_ amounts: [DomesticExchange: Double]) -> Bool {
        DomesticExchange.allCases.allSatisfy { exchange in
            guard let value = amounts[exchange] else { return false }
            return value.isFinite && value >= 0
        }
    }

    private func shares(for amounts: [DomesticExchange: Double]) -> [DomesticExchange: Double] {
        let total = amounts.values.reduce(0, +)
        guard total > 0 else { return [:] }
        return amounts.mapValues { $0 / total * 100 }
    }

    private func sharesForRawValues(_ values: [String: Double]) -> [DomesticExchange: Double] {
        var mapped: [DomesticExchange: Double] = [:]
        for exchange in DomesticExchange.allCases {
            guard let value = values[exchange.rawValue], value.isFinite, value >= 0 else { continue }
            mapped[exchange] = value
        }
        return shares(for: mapped)
    }


    private func fifteenMinuteReferenceSample(now: Date) -> StoredSample? {
        var best: StoredSample?
        var bestDistance = TimeInterval.greatestFiniteMagnitude

        for candidate in samples {
            let elapsed = now.timeIntervalSince(candidate.timestamp)
            // Keep the public phase label honest: only eligible 14-19 minute samples
            // participate. The previous implementation first chose the nearest sample and
            // then rejected it, which could ignore a second-nearest but valid 15m reference.
            guard elapsed >= 14 * 60, elapsed <= 19 * 60 else { continue }
            let distance = abs(elapsed - interval)
            if distance < bestDistance {
                bestDistance = distance
                best = candidate
            }
        }
        return best
    }

    private func quickReferenceSample(now: Date) -> StoredSample? {
        var best: StoredSample?
        var bestDistance = TimeInterval.greatestFiniteMagnitude

        for candidate in samples {
            let elapsed = now.timeIntervalSince(candidate.timestamp)
            guard elapsed >= quickMinimum, elapsed <= quickMaximum else { continue }
            let distance = abs(elapsed - quickTarget)
            if distance < bestDistance {
                bestDistance = distance
                best = candidate
            }
        }
        return best
    }

    private func sample(near target: Date, tolerance: TimeInterval) -> StoredSample? {
        var best: StoredSample?
        var bestDistance = TimeInterval.greatestFiniteMagnitude
        for candidate in samples {
            let distance = abs(candidate.timestamp.timeIntervalSince(target))
            if distance < bestDistance {
                bestDistance = distance
                best = candidate
            }
        }
        guard bestDistance <= tolerance else { return nil }
        return best
    }

    private func phaseRank(_ phase: DomesticActivityPhase) -> Int {
        switch phase {
        case .measuring: return 0
        case .quickEstimate: return 1
        case .fifteenMinute: return 2
        }
    }

    private func isRetainable(_ snapshot: DomesticActivitySnapshot, at now: Date) -> Bool {
        let age = now.timeIntervalSince(snapshot.updatedAt)
        guard age >= 0 else { return false }
        switch snapshot.phase {
        case .measuring:
            return false
        case .quickEstimate:
            return age <= retainedQuickEstimateMaxAge
        case .fifteenMinute:
            return age <= retainedFifteenMinuteMaxAge
        }
    }

    private func restoreLatestDisplaySnapshotFromHistory(now: Date = Date()) {
        guard let latest = samples.last else { return }
        let candidate = analyzeRaw(now: latest.timestamp, currentValues: latest.values)
        guard isRetainable(candidate, at: now) else { return }
        latestDisplaySnapshot = candidate
    }

    private func prune(relativeTo now: Date) {
        let cutoff = now.addingTimeInterval(-historyWindow)
        samples.removeAll { $0.timestamp < cutoff }
        if samples.count > 480 {
            samples.removeFirst(samples.count - 480)
        }
    }

    private func loadHistory() {
        guard let historyURL,
              let data = try? Data(contentsOf: historyURL),
              let decoded = try? JSONDecoder().decode([StoredSample].self, from: data) else {
            return
        }
        samples = decoded.sorted { $0.timestamp < $1.timestamp }
        prune(relativeTo: Date())
        lastPersistedAt = samples.last?.timestamp
        latestObservationComplete = samples.last.map { hasCompleteVenueSet($0.values) } ?? false
    }

    private func persistHistory(now: Date, force: Bool = false) {
        guard let historyURL else { return }
        if !force, let lastPersistedAt, now.timeIntervalSince(lastPersistedAt) < persistInterval {
            return
        }
        prune(relativeTo: now)
        let snapshot = samples
        lastPersistedAt = now
        let write: @Sendable () -> Void = {
            guard let data = try? JSONEncoder().encode(snapshot) else { return }
            try? data.write(to: historyURL, options: .atomic)
        }

        if force {
            // App termination needs a real flush, not a detached task that may be torn
            // down before it reaches disk. The serial queue also orders any prior write.
            persistenceQueue.sync(execute: write)
        } else {
            // Normal persistence remains off MainActor and serial, preventing stale
            // snapshots from racing a newer atomic write.
            persistenceQueue.async(execute: write)
        }
    }
}
