import XCTest
#if SWIFT_PACKAGE
@testable import PersonalFitnessCore
#else
@testable import PersonalFitness
#endif

final class LocalDayWindowTests: XCTestCase {
    private func calendar(_ zone: String) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: zone)!
        return calendar
    }

    func testSpringAndFallDSTDayLengths() throws {
        let calendar = calendar("America/Los_Angeles")
        for (month, day, hours) in [(3, 8, 23), (11, 1, 25)] {
            let start = calendar.date(from: DateComponents(year: 2026, month: month, day: day))!
            let window = try LocalDayWindow(day: start, now: start.addingTimeInterval(3 * 86400), calendar: calendar)
            XCTAssertEqual(window.start, start)
            XCTAssertEqual(window.end.timeIntervalSince(start), Double(hours * 3600))
            XCTAssertFalse(window.isPartial)
        }
    }

    func testTodayStopsAtNowAndHistoricalDayStopsAtNextMidnight() throws {
        let calendar = calendar("UTC")
        let start = calendar.date(from: DateComponents(year: 2026, month: 10, day: 13))!
        let now = start.addingTimeInterval(12 * 3600 + 0.75)
        let today = try LocalDayWindow(day: start, now: now, calendar: calendar)
        XCTAssertEqual(today.end, now)
        XCTAssertTrue(today.isPartial)
        let past = try LocalDayWindow(day: start.addingTimeInterval(-86400), now: now, calendar: calendar)
        XCTAssertEqual(past.end, start)
        XCTAssertFalse(past.isPartial)
    }

    func testTimeZoneChangesMidnightBoundary() throws {
        let instant = Date(timeIntervalSince1970: 1_792_000_000)
        let now = instant.addingTimeInterval(86400 * 3)
        let utc = try LocalDayWindow(day: instant, now: now, calendar: calendar("UTC"))
        let phoenix = try LocalDayWindow(day: instant, now: now, calendar: calendar("America/Phoenix"))
        XCTAssertNotEqual(utc.start, phoenix.start)
        XCTAssertEqual(phoenix.timeZoneIdentifier, "America/Phoenix")
    }

    func testFutureIsRejectedAndMidnightHasAnEmptyPartialWindow() throws {
        let calendar = calendar("UTC")
        let now = calendar.startOfDay(for: .now)
        let midnight = try LocalDayWindow(day: now, now: now, calendar: calendar)
        XCTAssertEqual(midnight.start, midnight.end)
        XCTAssertTrue(midnight.isPartial)
        XCTAssertThrowsError(try LocalDayWindow(day: now.addingTimeInterval(86400), now: now, calendar: calendar))
    }
}
