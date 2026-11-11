import XCTest
#if SWIFT_PACKAGE
@testable import PersonalFitnessCore
#else
@testable import PersonalFitness
#endif

final class ProgressLogicTests: XCTestCase {
    func testChartSelectionUsesObservedLocalDayAndNeverSnapsAcrossDSTGaps() throws {
        let now = date(11, 5)
        let first = try day(date(10, 31), now: now, calories: 1500)
        let second = try day(date(11, 2), now: now, calories: 1800)
        let points = ReportSeries.points([first, second], metrics: [.consumed, .expenditure])
        let selection = date(11, 1, hour: 12)
        XCTAssertTrue(ReportSelection.values(on: selection, from: points, calendar: calendar, day: \.day).isEmpty)
        let historical = ReportSelection.values(on: date(11, 2, hour: 23), from: points, calendar: calendar, day: \.day)
        XCTAssertEqual(historical.count, 1)
        XCTAssertEqual(historical.first?.value, 1800)
        XCTAssertTrue(ReportSelection.values(on: nil, from: points, calendar: calendar, day: \.day).isEmpty)
        XCTAssertTrue(ReportSelection.values(on: Date(timeIntervalSince1970: .nan), from: points, calendar: calendar, day: \.day).isEmpty)
    }
    private var calendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(identifier: "America/New_York")!
        value.firstWeekday = 2
        return value
    }
    private func date(_ month: Int, _ day: Int, hour: Int = 12) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: month, day: day, hour: hour))!
    }
    private func range(_ period: ReportPeriod = .custom, start: Date, end: Date, now: Date) throws -> ReportRange {
        try ReportRange(period: period, anchor: end, customStart: start, customEnd: end, now: now, calendar: calendar)
    }
    private func day(_ date: Date, now: Date, calories: Double? = nil, resting: Double? = nil, active: Double? = nil) throws -> ReportDay {
        let window = try LocalDayWindow(day: date, now: now, calendar: calendar)
        let foods = calories.map { [ReportFood(id: UUID(), date: window.start, name: "Fixture", portion: NutritionPortion(calories: $0, protein: 10, carbohydrates: 20, fat: 5))] } ?? []
        return ReportDay(window: window, food: foods, aggregates: [EnergyAggregate(kind: .resting, reading: resting.map(CalorieReading.value) ?? .missing, window: window), EnergyAggregate(kind: .active, reading: active.map(CalorieReading.value) ?? .missing, window: window)])
    }
    func testDayWeekMonthRangesUseLocalCalendarAndClampToday() throws {
        let now = date(10, 13)
        let week = try range(.week, start: now, end: now, now: now)
        XCTAssertEqual(week.days.count, 2)
        XCTAssertEqual(week.start, date(10, 12, hour: 0))
        let month = try range(.month, start: now, end: now, now: now)
        XCTAssertEqual(month.days.count, 13)
        XCTAssertEqual(month.end, date(10, 14, hour: 0))
        XCTAssertEqual(try range(.day, start: now, end: now, now: now).days.count, 1)
        XCTAssertEqual(try range(.month, start: date(2, 1), end: date(2, 15), now: now).days.count, 28)
    }
    func testDSTExclusiveBoundariesAndMidnight() throws {
        let now = date(11, 5)
        let fall = try range(start: date(11, 1), end: date(11, 1), now: now)
        XCTAssertEqual(fall.end.timeIntervalSince(fall.start), 25 * 3600)
        let spring = try range(start: date(3, 8), end: date(3, 8), now: now)
        XCTAssertEqual(spring.end.timeIntervalSince(spring.start), 23 * 3600)
        let window = try LocalDayWindow(day: fall.start, now: now, calendar: calendar)
        let food = ReportFood(id: UUID(), date: fall.end, name: "Next day", portion: NutritionPortion(calories: 100, protein: 1, carbohydrates: 1, fat: 1))
        XCTAssertTrue(ReportDay(window: window, food: [food], aggregates: []).food.isEmpty)
    }
    func testInvalidReverseFutureAndExcessiveRanges() {
        let now = date(10, 13)
        XCTAssertThrowsError(try range(start: date(10, 13), end: date(10, 12), now: now))
        XCTAssertThrowsError(try range(start: now, end: date(10, 14), now: now))
        XCTAssertThrowsError(try range(start: date(1, 1), end: now, now: now))
        XCTAssertThrowsError(try range(start: Date(timeIntervalSince1970: .nan), end: now, now: now))
    }
    func testMissingFoodDiffersFromLoggedZeroAndMissingEnergyFromZero() throws {
        let now = date(10, 13)
        let missing = try day(date(10, 12), now: now)
        XCTAssertNil(missing.consumed); XCTAssertNil(missing.protein)
        XCTAssertNil(missing.assessment.balance.expenditure)
        let zero = try day(date(10, 12), now: now, calories: 0, resting: 0, active: 0)
        XCTAssertEqual(zero.consumed, 0)
        XCTAssertEqual(zero.assessment.balance.net, 0)
        XCTAssertEqual(zero.assessment.expenditureQuality, .partial, "Historical coverage is still unverified")
    }
    func testTotalsCompareOnlyMatchedClosedDaysAndPreservePartialToday() throws {
        let now = date(10, 13)
        let reports = [try day(date(10, 10), now: now, calories: 2000, resting: 1600, active: 500),
                       try day(date(10, 11), now: now, resting: 1600, active: 400),
                       try day(date(10, 12), now: now, calories: 1800, resting: 1600),
                       try day(now, now: now, calories: 1000, resting: 800, active: 100)]
        let total = ReportTotals(reports)
        XCTAssertEqual(total.days, 4); XCTAssertEqual(total.foodDays, 3)
        XCTAssertEqual(total.calories, 4800)
        XCTAssertEqual(total.protein, 30)
        XCTAssertEqual(total.matchedClosedDays, 1)
        XCTAssertEqual(total.matchedIntake, 2000); XCTAssertEqual(total.matchedExpenditure, 2100)
        XCTAssertEqual(total.matchedBalance, -100)
        XCTAssertTrue(reports.last!.window.isPartial)
        XCTAssertTrue(reports.last!.assessment.balanceReasons.contains(.dayInProgress))
    }
    func testEmptyAndInvalidTotalsAndChartGaps() throws {
        let now = date(10, 13)
        let missing = try day(date(10, 11), now: now)
        XCTAssertNil(ReportTotals([missing]).calories)
        XCTAssertNil(ReportTotals([missing]).matchedBalance)
        let invalid = try day(date(10, 10), now: now, calories: -1)
        let valid = try day(date(10, 12), now: now, calories: 100)
        XCTAssertNil(ReportTotals([invalid, valid]).calories, "Invalid logged data cannot be silently dropped")
        let first = try day(date(10, 10), now: now, calories: 0)
        let points = ReportSeries.points([first, missing, valid], metrics: [.consumed])
        XCTAssertEqual(points.count, 2); XCTAssertEqual(points[0].value, 0)
        XCTAssertNotEqual(points[0].segment, points[1].segment)
    }
    func testWeightMeanUsesLatestDailySamplesPerSourceWithoutPoolingOrCarryForward() {
        let samples = [WeightObservation(id: UUID(), date: date(10, 10, hour: 8), kilograms: 100, origin: .health),
                       WeightObservation(id: UUID(), date: date(10, 10, hour: 18), kilograms: 80, origin: .health),
                       WeightObservation(id: UUID(), date: date(10, 11), kilograms: 82, origin: .health),
                       WeightObservation(id: UUID(), date: date(10, 13), kilograms: 84, origin: .health),
                       WeightObservation(id: UUID(), date: date(10, 11), kilograms: 90, origin: .manual)]
        let points = WeightTrend.points(samples + [samples[1]], calendar: calendar)
        XCTAssertEqual(points.count, 4)
        let health = points.filter { $0.origin == .health }
        XCTAssertEqual(health[0].kilograms, 80); XCTAssertNil(health[0].mean)
        XCTAssertEqual(health[1].mean, 81)
        XCTAssertEqual(health[2].mean, 82); XCTAssertEqual(health[2].recordedDays, 3)
        XCTAssertNotEqual(health[1].segment, health[2].segment)
        XCTAssertNil(points.first { $0.origin == .manual }!.mean)
        XCTAssertFalse(points.contains { calendar.isDate($0.day, inSameDayAs: date(10, 12)) })
    }
    func testWeightWindowExpiresOldSamplesAndRejectsInvalidValues() throws {
        let samples = [WeightObservation(id: UUID(), date: date(10, 1), kilograms: 80, origin: .manual),
                       WeightObservation(id: UUID(), date: date(10, 8), kilograms: 82, origin: .manual)]
        XCTAssertNil(WeightTrend.points(samples, calendar: calendar).last!.mean)
        for value in [0.0, -1, .nan, .infinity] {
            XCTAssertThrowsError(try WeightObservation(id: UUID(), date: date(10, 1), kilograms: value, origin: .manual).validated(now: date(10, 13)))
        }
        XCTAssertThrowsError(try WeightObservation(id: UUID(), date: date(10, 14), kilograms: 80, origin: .manual).validated(now: date(10, 13)))
    }
    func testCurrentDayIncludesFoodSavedEarlierInTheSameSecond() throws {
        let start = calendar.startOfDay(for: date(10, 13))
        let now = start.addingTimeInterval(3600.75)
        let window = try LocalDayWindow(day: start, now: now, calendar: calendar)
        let food = ReportFood(id: UUID(), date: start.addingTimeInterval(3600.25), name: "Just logged",
                              portion: NutritionPortion(calories: 100, protein: 10, carbohydrates: 10, fat: 2))
        XCTAssertEqual(ReportDay(window: window, food: [food], aggregates: []).consumed, 100)
    }

}
