import XCTest
import SwiftData
@testable import PersonalFitness

final class WorkoutRecordTests: XCTestCase {
    func testHealthAdapterUsesExactIDReconciliationWithoutMergingDistinctRecords() {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let first = HealthWorkout(id: UUID(), title: "Strength training", start: start, end: start.addingTimeInterval(600), durationSeconds: 600, activity: .strength)
        let other = HealthWorkout(id: UUID(), title: "Strength training", start: start, end: start.addingTimeInterval(600), durationSeconds: 600, activity: .strength)
        let unique = HealthWorkout.uniqueRecords([first, first, other])
        XCTAssertEqual(unique.map(\.id), [first.id, other.id])
        XCTAssertEqual(WorkoutReconciliation.possibleMatches(for: first.recordSummary, in: unique.map(\.recordSummary)), [other.id])
    }
    @MainActor
    func testManualCalorieEstimatesNeverChangeDashboardEnergy() async throws {
        let container = try AppPersistence.makeContainer(inMemory: true)
        let service = MockHealthService()
        service.hasCompletedRequest = true
        service.snapshot = { window in
            HealthDaySnapshot(window: window, refreshedAt: window.end,
                resting: .value(1600), active: .value(500), steps: .value(1000),
                workouts: .unavailable, weight: .unavailable)
        }
        let model = DashboardModel(health: service)
        let timestamp = Calendar.current.startOfDay(for: .now)
        container.mainContext.insert(FoodEntry(name: "Fixture intake", calories: 2000, loggedAt: timestamp))
        try container.mainContext.save()
        let foods = FoodEntryStore(context: container.mainContext)
        await model.load(from: foods)
        let window = try XCTUnwrap(model.healthSnapshot?.window)
        let totals = NutritionTotals(portions: [NutritionPortion(calories: 2000, protein: 0, carbohydrates: 0, fat: 0)])
        let before = model.assessment(for: DailyNutrition(totals: totals, window: window)).balance
        let store = WorkoutStore(context: container.mainContext)
        var cardio = CardioDraft(activity: .stairs, start: Date.now.addingTimeInterval(-1800), durationSeconds: 600, reportedCalories: 900)
        try store.saveCardio(cardio)
        cardio.reportedCalories = 9999
        try store.saveCardio(cardio)
        await model.load(from: foods)
        let refreshed = try XCTUnwrap(model.healthSnapshot?.window)
        let after = model.assessment(for: DailyNutrition(totals: totals, window: refreshed)).balance
        XCTAssertEqual(before, after)
        XCTAssertEqual(after.active, 500)
        XCTAssertEqual(after.expenditure, 2100)
        XCTAssertEqual(after.net, -100)
    }

}
