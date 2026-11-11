import XCTest
import SwiftData
@testable import PersonalFitness

@MainActor private final class ReportHealthStub: HealthHistoryReading {
    var isAvailable = true
    var hasCompletedRequest = false
    var requests = 0
    var windows: [LocalDayWindow] = []
    var weightStart: Date?
    var handler: ((LocalDayWindow) async -> HealthDaySnapshot)?
    func requestReadAccess() async throws { requests += 1; hasCompletedRequest = true }
    func readDay(_ window: LocalDayWindow) async -> HealthDaySnapshot {
        windows.append(window)
        if let handler { return await handler(window) }
        return HealthDaySnapshot(window: window, refreshedAt: window.end,
            resting: .value(1600), active: .value(500), steps: .value(1000), workouts: .unavailable, weight: .unavailable)
    }
    func readWeights(start: Date, end: Date) async -> HealthReading<[WeightObservation]> {
        weightStart = start; return .unavailable
    }
}

final class ProgressModelTests: XCTestCase {
    @MainActor func testRecentPresetsUseLocalCalendarDaysAcrossDSTAndClearSelectionForCustomRange() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "America/New_York"))
        let now = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 11, day: 3, hour: 12)))
        let model = ProgressModel(now: now, calendar: calendar, health: ReportHealthStub())
        for count in [7, 30, 90] {
            model.selectRecentDays(count)
            XCTAssertTrue(model.isRecentDays(count))
            let range = try ReportRange(period: model.period, anchor: model.anchor, customStart: model.customStart,
                                        customEnd: model.customEnd, now: now, calendar: calendar)
            XCTAssertEqual(range.days.count, count)
            XCTAssertEqual(range.days.last, calendar.startOfDay(for: now))
        }
        model.customEnd = try XCTUnwrap(calendar.date(byAdding: .day, value: -1, to: model.customEnd))
        XCTAssertFalse(model.isRecentDays(90))
    }
    @MainActor func testCancelledReportReleasesLoadingState() async throws {
        let container = try AppPersistence.makeContainer(inMemory: true)
        let health = ReportHealthStub(); health.hasCompletedRequest = true
        var continuation: CheckedContinuation<HealthDaySnapshot, Never>?
        var scope: LocalDayWindow?
        health.handler = { window in scope = window; return await withCheckedContinuation { continuation = $0 } }
        let model = ProgressModel(health: health); model.period = .day
        let task = Task { await model.load(context: container.mainContext) }
        while continuation == nil { await Task.yield() }
        task.cancel()
        let window = try XCTUnwrap(scope)
        continuation?.resume(returning: HealthDaySnapshot(window: window, refreshedAt: window.end,
            resting: .unavailable, active: .unavailable, steps: .unavailable, workouts: .unavailable, weight: .unavailable))
        await task.value
        XCTAssertFalse(model.loading)
        XCTAssertNil(model.report)
    }

    @MainActor func testOfflineReportsNeverRequestAccessAndKeepMissingFoodAndEnergyExplicit() async throws {
        let container = try AppPersistence.makeContainer(inMemory: true)
        let health = ReportHealthStub()
        let model = ProgressModel(health: health); model.period = .day
        await model.load(context: container.mainContext)
        let report = try XCTUnwrap(model.report)
        XCTAssertEqual(health.requests, 0); XCTAssertTrue(health.windows.isEmpty)
        XCTAssertNil(report.days[0].consumed)
        XCTAssertNil(report.days[0].assessment.balance.expenditure)
        XCTAssertTrue(report.healthWorkouts.isEmpty)
        XCTAssertEqual(report.readableWorkoutDays, 0)
    }
    @MainActor func testHistoricalCalculationAndSixDayWeightLookback() async throws {
        let container = try AppPersistence.makeContainer(inMemory: true)
        let health = ReportHealthStub(); health.hasCompletedRequest = true
        let now = Date.now
        let calendar = Calendar.current
        let yesterday = calendar.date(byAdding: .day, value: -1, to: calendar.startOfDay(for: now))!
        container.mainContext.insert(FoodEntry(name: "Historical food", calories: 2000, loggedAt: yesterday))
        let weightDate = calendar.date(byAdding: .day, value: -3, to: yesterday)!
        try ProgressStore(context: container.mainContext).saveWeight(WeightObservation(id: UUID(), date: weightDate, kilograms: 80, origin: .manual))
        let model = ProgressModel(now: now, calendar: calendar, health: health)
        model.period = .day; model.anchor = yesterday
        await model.load(context: container.mainContext, now: now)
        let report = try XCTUnwrap(model.report)
        XCTAssertEqual(report.days[0].assessment.balance.net, -100)
        XCTAssertFalse(report.days[0].window.isPartial)
        XCTAssertEqual(report.totals.matchedClosedDays, 1)
        XCTAssertEqual(report.weights.count, 1)
        XCTAssertTrue(report.trend.isEmpty, "Lookback samples inform means but cannot invent points inside the range")
        XCTAssertEqual(health.weightStart, calendar.date(byAdding: .day, value: -6, to: yesterday))
        XCTAssertEqual(health.requests, 0)
        model.period = .month; model.anchor = now
        XCTAssertFalse(model.canMoveForward)
        model.movePeriod(by: -1)
        XCTAssertTrue(model.canMoveForward)
        model.movePeriod(by: 1)
        XCTAssertFalse(model.canMoveForward)
    }
    @MainActor func testLateReadCannotOverwriteNewDateSelection() async throws {
        let container = try AppPersistence.makeContainer(inMemory: true)
        let health = ReportHealthStub(); health.hasCompletedRequest = true
        var continuation: CheckedContinuation<HealthDaySnapshot, Never>?
        var oldWindow: LocalDayWindow?
        health.handler = { window in oldWindow = window; return await withCheckedContinuation { continuation = $0 } }
        let model = ProgressModel(health: health); model.period = .day
        let old = Task { await model.load(context: container.mainContext) }
        while continuation == nil { await Task.yield() }
        model.anchor = Calendar.current.date(byAdding: .day, value: -1, to: model.anchor)!
        health.handler = nil
        await model.load(context: container.mainContext)
        let current = model.report?.range.start
        continuation?.resume(returning: HealthDaySnapshot(window: oldWindow!, refreshedAt: oldWindow!.end,
            resting: .unavailable, active: .unavailable, steps: .unavailable, workouts: .unavailable, weight: .unavailable))
        await old.value
        XCTAssertEqual(model.report?.range.start, current)
        XCTAssertNotEqual(current, oldWindow?.start)
    }
    @MainActor func testRequestOccursOnlyAfterConnectAndWorkoutRecordsAreNotCombinedWithManualCounts() async throws {
        let container = try AppPersistence.makeContainer(inMemory: true)
        let health = ReportHealthStub()
        let model = ProgressModel(health: health); model.period = .day
        await model.connect(context: container.mainContext)
        XCTAssertEqual(health.requests, 1)
        let id = UUID()
        health.handler = { window in
            let workout = HealthWorkout(id: id, title: "Strength", start: window.start, end: window.end, durationSeconds: 60, activity: .strength)
            return HealthDaySnapshot(window: window, refreshedAt: window.end, resting: .value(1600), active: .value(500), steps: .unavailable,
                workouts: .value([workout, workout]), weight: .unavailable)
        }
        await model.load(context: container.mainContext)
        let report = try XCTUnwrap(model.report)
        XCTAssertEqual(report.healthWorkouts.count, 1)
        XCTAssertTrue(report.local.strength.isEmpty)
        XCTAssertEqual(report.days[0].assessment.balance.expenditure, 2100)
    }
    @MainActor
    func testCalendarIdentifierChangePreservesHistoricalReportAndCustomRange() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let now = calendar.date(from: DateComponents(year: 2026, month: 10, day: 13, hour: 12))!
        let model = ProgressModel(now: now, calendar: calendar, health: ReportHealthStub())
        model.anchor = calendar.date(byAdding: .day, value: -2, to: model.today)!
        let anchor = model.anchor, start = model.customStart, end = model.customEnd
        var buddhist = Calendar(identifier: .buddhist)
        buddhist.timeZone = calendar.timeZone
        model.foreground(now: now, calendar: buddhist)
        XCTAssertEqual(model.anchor, anchor)
        XCTAssertEqual(model.customStart, start)
        XCTAssertEqual(model.customEnd, end)
    }

}
