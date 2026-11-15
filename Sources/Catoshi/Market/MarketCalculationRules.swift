import Foundation

enum MarketCalculationRules {
    static func synchronized(_ dates: [String?], reference: Date) -> Bool {
        guard dates.count >= 3 else { return false }
        let formatter = ISO8601DateFormatter()
        return dates.allSatisfy { value in
            guard let value else { return false }
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            let fractional = formatter.date(from: value)
            formatter.formatOptions = [.withInternetDateTime]
            guard let date = fractional ?? formatter.date(from: value) else { return false }
            return abs(date.timeIntervalSince(reference)) <= 120
        }
    }

    static func openInterestChange(_ points: [(Int64, Double)], now: Date) -> Double? {
        let rows = points.sorted { $0.0 < $1.0 }
        guard rows.count >= 2 else { return nil }
        let latest = rows[rows.count - 1], previous = rows[rows.count - 2]
        let age = now.timeIntervalSince1970 - Double(latest.0) / 1000
        guard age >= 0, age < 75 * 60, latest.0 - previous.0 == 3_600_000,
              latest.1.isFinite, previous.1.isFinite, latest.1 > 0, previous.1 > 0 else { return nil }
        return (latest.1 / previous.1 - 1) * 100
    }

    static func closedDailyPrices(_ rows: [[Any]], now: Date) -> [Double] {
        let points: [(Double, Double)] = rows.compactMap { row in
            guard row.count > 6, let closeTime = row[6] as? NSNumber,
                  closeTime.doubleValue < now.timeIntervalSince1970 * 1000,
                  let price = Double(String(describing: row[4])), price.isFinite, price > 0 else { return nil }
            return (closeTime.doubleValue, price)
        }.sorted { $0.0 < $1.0 }
        guard points.count >= 200, let last = points.last,
              now.timeIntervalSince1970 - last.0 / 1000 < 48 * 3600 else { return [] }
        for index in 1..<points.count {
            guard abs(points[index].0 - points[index - 1].0 - 86_400_000) < 1 else { return [] }
        }
        return points.map { $0.1 }
    }

    static func uniqueDailyFlows(_ points: [(date: Date, totalUSD: Double)], now: Date) -> [(date: Date, totalUSD: Double)] {
        let groups = Dictionary(grouping: points.filter { $0.date <= now && $0.totalUSD.isFinite }, by: { $0.date })
        return groups.compactMap { date, rows in
            guard let first = rows.first, rows.allSatisfy({ $0.totalUSD == first.totalUSD }) else { return nil }
            return (date, first.totalUSD)
        }
    }
}
