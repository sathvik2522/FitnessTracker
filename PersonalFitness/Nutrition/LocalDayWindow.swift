import Foundation

/// Immutable local-day scope shared by food reads, Health reads and reconciliation.
struct LocalDayWindow: Equatable, Sendable {
    let start: Date
    let end: Date
    let timeZoneIdentifier: String
    let isPartial: Bool

    static func interval(for day: Date, calendar: Calendar) throws -> DateInterval {
        guard let interval = calendar.dateInterval(of: .day, for: day) else {
            throw WindowError.invalidDay
        }
        return interval
    }

    /// Uses calendar midnights (including 23/25-hour DST days), with today's
    /// end clipped to now. Consumers treat the interval as [start, end).
    init(day: Date, now: Date, calendar: Calendar) throws {
        let interval = try Self.interval(for: day, calendar: calendar)
        guard interval.start <= now else { throw WindowError.invalidDay }
        start = interval.start
        end = min(interval.end, now)
        guard end >= start else { throw WindowError.invalidDay }
        timeZoneIdentifier = calendar.timeZone.identifier
        isPartial = end < interval.end
    }

    enum WindowError: Error { case invalidDay }
}

struct DailyNutrition {
    let totals: NutritionTotals
    let window: LocalDayWindow
}
