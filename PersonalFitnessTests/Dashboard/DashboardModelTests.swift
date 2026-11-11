import XCTest
@testable import PersonalFitness

final class DashboardModelTests: XCTestCase {
    private var calendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        return value
    }

    private func date(_ day: Int, hour: Int = 12) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 3, day: day, hour: hour))!
    }

    @MainActor
    func testSelectionNormalizesAndPreventsFutureDates() {
        let model = DashboardModel(now: date(10), calendar: calendar, health: MockHealthService())
        XCTAssertEqual(model.selectedDate, calendar.startOfDay(for: date(10)))
        model.select(date(12))
        XCTAssertTrue(model.isToday)
        XCTAssertFalse(model.canMoveForward)
        model.select(date(9))
        XCTAssertTrue(model.canMoveForward)
    }

    @MainActor
    func testDayNavigationUsesCalendarAcrossSpringDST() {
        let model = DashboardModel(now: date(9), calendar: calendar, health: MockHealthService())
        model.moveDay(by: -1)
        let march8 = model.selectedDate
        model.moveDay(by: 1)
        XCTAssertEqual(model.selectedDate.timeIntervalSince(march8), 23 * 3600)
        XCTAssertTrue(model.isToday)
    }

    @MainActor
    func testMidnightFollowsToday() {
        let model = DashboardModel(now: date(9), calendar: calendar, health: MockHealthService())
        model.updateToday(date(10))
        XCTAssertTrue(model.isToday)
        XCTAssertEqual(model.selectedDate, calendar.startOfDay(for: date(10)))
    }

    @MainActor
    func testMidnightPreservesHistoricalSelection() {
        let model = DashboardModel(now: date(9), calendar: calendar, health: MockHealthService())
        model.select(date(7))
        model.updateToday(date(10))
        XCTAssertEqual(model.selectedDate, calendar.startOfDay(for: date(7)))
    }

    @MainActor
    func testLoadedSummaryAndSelectingSameDateDoesNotLeaveLoading() async throws {
        let container = try AppPersistence.makeContainer(inMemory: true)
        let model = DashboardModel(now: date(9), calendar: calendar, health: MockHealthService())
        await model.load(from: FoodEntryStore(context: container.mainContext))
        model.select(date(9, hour: 18))
        guard case .loaded(let totals) = model.state else {
            return XCTFail("Same-day selection must retain the loaded summary")
        }
        XCTAssertEqual(totals.totals.entryCount, 0)
        XCTAssertNil(model.assessment(for: totals).balance.expenditure)
        XCTAssertNil(model.assessment(for: totals).balance.net)
    }
    @MainActor
    func testCalendarIdentifierChangeKeepsHistoricalDayInsteadOfReinterpretingYear() {
        let model = DashboardModel(now: date(10), calendar: calendar, health: MockHealthService())
        model.select(date(7))
        var buddhist = Calendar(identifier: .buddhist)
        buddhist.timeZone = calendar.timeZone
        model.updateToday(date(10), calendar: buddhist)
        XCTAssertEqual(model.selectedDate, buddhist.startOfDay(for: date(7)))
    }

    @MainActor
    func testTimeZoneChangePreservesHistoricalCivilDate() {
        let model = DashboardModel(now: date(10), calendar: calendar, health: MockHealthService())
        model.select(date(7))
        var next = calendar
        next.timeZone = TimeZone(identifier: "Asia/Tokyo")!
        model.updateToday(date(10), calendar: next)
        XCTAssertEqual(next.dateComponents([.year, .month, .day], from: model.selectedDate),
                       DateComponents(year: 2026, month: 3, day: 7))
    }

}
