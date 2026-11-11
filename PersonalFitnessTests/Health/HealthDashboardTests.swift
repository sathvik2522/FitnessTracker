import XCTest
@testable import PersonalFitness

final class HealthDashboardTests: XCTestCase {
    @MainActor
    func testCancelledHealthRefreshReleasesLoadingState() async throws {
        let service = MockHealthService(); service.hasCompletedRequest = true
        var continuation: CheckedContinuation<HealthDaySnapshot, Never>?
        var scope: LocalDayWindow?
        service.handler = { window in scope = window; return await withCheckedContinuation { continuation = $0 } }
        let model = DashboardModel(health: service)
        let task = Task { await model.refreshHealth() }
        while continuation == nil { await Task.yield() }
        task.cancel()
        continuation?.resume(returning: service.snapshot(try XCTUnwrap(scope)))
        await task.value
        if case .idle = model.healthState {} else { XCTFail("Cancelled refresh must not keep a spinner") }
        XCTAssertNil(model.healthSnapshot)
    }

    @MainActor
    private func balance(_ model: DashboardModel, _ totals: NutritionTotals) -> EnergyBalance {
        model.assessment(for: DailyNutrition(totals: totals, window: model.healthSnapshot!.window)).balance
    }

    @MainActor
    func testLaunchAndRefreshNeverRequestAuthorization() async throws {
        let service = MockHealthService()
        let model = DashboardModel(health: service)
        let container = try AppPersistence.makeContainer(inMemory: true)
        await model.load(from: FoodEntryStore(context: container.mainContext))
        XCTAssertEqual(service.requestCount, 0)
        XCTAssertTrue(service.windows.isEmpty)
        if case .notRequested = model.healthConnection {} else { XCTFail("Expected explicit connection") }
    }

    @MainActor
    func testExplicitConnectCompletesRequestWithoutAssumingReadableData() async {
        let service = MockHealthService()
        let model = DashboardModel(health: service)
        await model.connectHealth()
        XCTAssertEqual(service.requestCount, 1)
        XCTAssertEqual(service.windows.count, 1)
        XCTAssertNil(model.healthSnapshot?.resting.value)
        XCTAssertNil(balance(model, NutritionTotals(portions: [])).expenditure)
        if case .requestCompleted = model.healthConnection {} else { XCTFail("Expected request completed, not access granted") }
    }

    @MainActor
    func testFailedRequestAndUnavailableDeviceDoNotQuery() async {
        let service = MockHealthService()
        service.requestFails = true
        let model = DashboardModel(health: service)
        await model.connectHealth()
        await model.refreshHealth()
        XCTAssertTrue(service.windows.isEmpty)
        if case .requestFailed = model.healthConnection {} else { XCTFail("Expected request failure") }
        service.isAvailable = false
        await model.connectHealth()
        XCTAssertEqual(service.requestCount, 1)
        if case .unavailable = model.healthConnection {} else { XCTFail("Expected unavailable") }
    }

    @MainActor
    func testPartialFailuresPreserveOtherMetricsAndSuppressDerivedEnergy() async {
        let service = MockHealthService()
        service.hasCompletedRequest = true
        service.snapshot = { window in
            HealthDaySnapshot(window: window, refreshedAt: window.end,
                              resting: .value(1600), active: .failed(.deviceLocked), steps: .value(5000),
                              workouts: .unavailable, weight: .unavailable)
        }
        let model = DashboardModel(health: service)
        await model.refreshHealth()
        XCTAssertEqual(model.healthSnapshot?.steps.value, 5000)
        XCTAssertEqual(model.healthSnapshot?.active.issue, .deviceLocked)
        XCTAssertNil(balance(model, NutritionTotals(portions: [])).expenditure)
    }

    @MainActor
    func testWorkoutRecordsNeverIncreaseExpenditure() async {
        let service = MockHealthService()
        service.hasCompletedRequest = true
        service.snapshot = { window in
            HealthDaySnapshot(window: window, refreshedAt: window.end,
                              resting: .value(1600), active: .value(500), steps: .value(0),
                              workouts: .value([HealthWorkout(id: UUID(), title: "Workout", start: window.start,
                                                             end: window.end, durationSeconds: 3600)]), weight: .unavailable)
        }
        let model = DashboardModel(health: service)
        await model.refreshHealth()
        XCTAssertEqual(balance(model, NutritionTotals(portions: [])).expenditure, 2100)
        XCTAssertNil(balance(model, NutritionTotals(portions: [])).net, "Empty intake is unknown, not a calorie deficit")
        let logged = NutritionTotals(portions: [NutritionPortion(calories: 2000, protein: 10, carbohydrates: 20, fat: 30)])
        XCTAssertEqual(balance(model, logged).net, -100)
        XCTAssertEqual(model.healthSnapshot?.steps.value, 0)
        // Simulate revocation / absent samples on the next refresh.
        service.snapshot = { window in
            HealthDaySnapshot(window: window, refreshedAt: window.end, resting: .unavailable,
                              active: .unavailable, steps: .unavailable, workouts: .unavailable, weight: .unavailable)
        }
        await model.refreshHealth()
        XCTAssertNil(balance(model, NutritionTotals(portions: [])).expenditure)
    }

    @MainActor
    func testOldDayResponseCannotOverwriteNewSelection() async {
        let service = MockHealthService()
        service.hasCompletedRequest = true
        var continuation: CheckedContinuation<HealthDaySnapshot, Never>?
        var oldWindow: HealthDayWindow?
        service.handler = { window in
            oldWindow = window
            return await withCheckedContinuation { continuation = $0 }
        }
        let model = DashboardModel(health: service)
        let task = Task { await model.refreshHealth() }
        while continuation == nil { await Task.yield() }
        model.moveDay(by: -1)
        service.handler = nil
        await model.refreshHealth()
        let currentStart = model.healthSnapshot?.window.start
        continuation?.resume(returning: service.snapshot(oldWindow!))
        await task.value
        XCTAssertEqual(model.healthSnapshot?.window.start, currentStart)
        XCTAssertNotEqual(currentStart, oldWindow?.start)
    }

    @MainActor
    func testTimeZoneChangePreservesSelectedCivilDateAndClearsSnapshot() async {
        let service = MockHealthService()
        service.hasCompletedRequest = true
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Phoenix")!
        let now = calendar.date(from: DateComponents(year: 2026, month: 10, day: 13, hour: 12))!
        let model = DashboardModel(now: now, calendar: calendar, health: service)
        model.moveDay(by: -1)
        await model.refreshHealth(now: now)
        XCTAssertNotNil(model.healthSnapshot)
        calendar.timeZone = TimeZone(identifier: "Asia/Tokyo")!
        model.updateToday(now, calendar: calendar)
        XCTAssertEqual(calendar.component(.day, from: model.selectedDate), 12)
        XCTAssertEqual(model.calendar.timeZone, calendar.timeZone)
        XCTAssertNil(model.healthSnapshot)
    }
    @MainActor
    func testFoodAndHealthUseIdenticalCutoffAndExcludeFutureDiaryEntries() async throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let start = calendar.date(from: DateComponents(year: 2026, month: 10, day: 13))!
        let now = start.addingTimeInterval(12 * 3600)
        let service = MockHealthService()
        service.hasCompletedRequest = true
        service.snapshot = { window in
            HealthDaySnapshot(window: window, refreshedAt: window.end,
                              resting: .value(800), active: .value(200), steps: .unavailable,
                              workouts: .unavailable, weight: .unavailable)
        }
        let model = DashboardModel(now: now, calendar: calendar, health: service)
        let container = try AppPersistence.makeContainer(inMemory: true)
        container.mainContext.insert(FoodEntry(name: "Logged", calories: 100,
                                               loggedAt: start.addingTimeInterval(3600)))
        container.mainContext.insert(FoodEntry(name: "Future timestamp", calories: 300,
                                               loggedAt: start.addingTimeInterval(13 * 3600)))
        await model.load(from: FoodEntryStore(context: container.mainContext), now: now)
        guard case .loaded(let nutrition) = model.state else { return XCTFail("Expected scoped diary") }
        XCTAssertEqual(nutrition.totals.calories, 100)
        XCTAssertEqual(nutrition.window, service.windows.last)
        XCTAssertEqual(nutrition.window.end, now)
        XCTAssertEqual(model.assessment(for: nutrition).balance.net, -900)
        XCTAssertEqual(model.assessment(for: nutrition).balanceQuality, .partial)
        XCTAssertEqual(service.requestCount, 0)
    }

}
