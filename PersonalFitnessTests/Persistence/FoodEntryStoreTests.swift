import XCTest
import SwiftData
@testable import PersonalFitness

final class FoodEntryStoreTests: XCTestCase {
    @MainActor
    func testDailyQueryIncludesStartAndExcludesNextMidnight() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let start = Date(timeIntervalSince1970: 1_728_000)
        let container = try AppPersistence.makeContainer(inMemory: true)
        let context = container.mainContext
        for (offset, calories) in [(-1.0, 999.0), (0, 100), (86399, 200), (86400, 888)] {
            context.insert(FoodEntry(name: "Boundary", calories: calories,
                                     loggedAt: start.addingTimeInterval(offset)))
        }
        try context.save()
        let totals = try FoodEntryStore(context: context).totals(for: start, calendar: calendar)
        XCTAssertEqual(totals.entryCount, 2)
        XCTAssertEqual(totals.calories, 300)
    }

    @MainActor
    func testDSTDayDoesNotIncludeFollowingDay() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        let start = calendar.date(from: DateComponents(year: 2026, month: 3, day: 8))!
        let end = calendar.date(byAdding: .day, value: 1, to: start)!
        let container = try AppPersistence.makeContainer(inMemory: true)
        container.mainContext.insert(FoodEntry(name: "Last second", calories: 100,
                                               loggedAt: end.addingTimeInterval(-1)))
        container.mainContext.insert(FoodEntry(name: "Tomorrow", calories: 200, loggedAt: end))
        let totals = try FoodEntryStore(context: container.mainContext).totals(for: start, calendar: calendar)
        XCTAssertEqual(end.timeIntervalSince(start), 23 * 3600)
        XCTAssertEqual(totals.entryCount, 1)
        XCTAssertEqual(totals.calories, 100)
    }
    @MainActor
    func testSnapshotIncludesFoodSavedEarlierInTheSameSecond() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let start = calendar.startOfDay(for: .now)
        let now = start.addingTimeInterval(3600.75)
        let container = try AppPersistence.makeContainer(inMemory: true)
        container.mainContext.insert(FoodEntry(name: "Just saved", calories: 100, loggedAt: start.addingTimeInterval(3600.25)))
        try container.mainContext.save()
        let window = try LocalDayWindow(day: start, now: now, calendar: calendar)
        let snapshot = try FoodEntryStore(context: container.mainContext).snapshot(in: window)
        XCTAssertEqual(snapshot.totals.calories, 100)
        XCTAssertEqual(snapshot.totals.entryCount, 1)
        XCTAssertEqual(snapshot.window.end, now)
    }

}
