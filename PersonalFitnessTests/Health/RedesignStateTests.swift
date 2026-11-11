import XCTest
import SwiftData
@testable import PersonalFitness

@MainActor private final class WeightHistoryStub: HealthHistoryReading {
    var isAvailable = true
    var hasCompletedRequest = true
    var requests = 0
    var continuation: CheckedContinuation<HealthReading<[WeightObservation]>, Never>?
    var suspended = true
    func requestReadAccess() async throws { requests += 1 }
    func readDay(_ window: HealthDayWindow) async -> HealthDaySnapshot {
        HealthDaySnapshot(window: window, refreshedAt: window.end, resting: .unavailable, active: .unavailable,
                          steps: .unavailable, workouts: .unavailable, weight: .unavailable)
    }
    func readWeights(start: Date, end: Date) async -> HealthReading<[WeightObservation]> {
        if suspended { return await withCheckedContinuation { continuation = $0 } }
        return .unavailable
    }
}
final class RedesignStateTests: XCTestCase {
    @MainActor func testLateWeightReadCannotReplaceNewSelectedDayOrInventMissingValues() async throws {
        let container = try AppPersistence.makeContainer(inMemory: true)
        let stub = WeightHistoryStub()
        let value = DashboardWeightModel(health: stub)
        let now = Date.now
        let old = Task { await value.load(day: now, context: container.mainContext, now: now) }
        while stub.continuation == nil { await Task.yield() }
        stub.suspended = false
        let past = try XCTUnwrap(Calendar.current.date(byAdding: .day, value: -30, to: now))
        await value.load(day: past, context: container.mainContext, now: now)
        stub.continuation?.resume(returning: .value([WeightObservation(id: UUID(), date: now, kilograms: 80, origin: .health)]))
        await old.value
        XCTAssertTrue(value.weights.isEmpty)
        XCTAssertFalse(value.loading); XCTAssertEqual(stub.requests, 0)
        stub.hasCompletedRequest = false
        await value.load(day: now, context: container.mainContext)
        XCTAssertTrue(value.weights.isEmpty); XCTAssertEqual(stub.requests, 0)
    }
    @MainActor func testMovingMealRetainsSnapshotDateAndTotals() throws {
        let container = try AppPersistence.makeContainer(inMemory: true)
        let store = NutritionStore(context: container.mainContext)
        let definition = FoodDefinition(name: "Historic", preparation: .raw,
            nutrients: FoodNutrients(calories: 200, protein: 10, carbohydrates: 30, fat: 5),
            referenceQuantity: 100, referenceUnit: .grams, equivalents: [:])
        let id = UUID(), date = Date(timeIntervalSince1970: 1_700_000_000)
        try store.saveEntry(id: id, definition: definition, quantity: 50, unit: .grams, loggedAt: date,
                            sourceID: nil, sourceKind: nil, meal: .breakfast)
        let entry = try XCTUnwrap(container.mainContext.fetch(FetchDescriptor<FoodEntry>()).first)
        let snapshot = entry.referenceSnapshot
        try store.moveEntry(id: id, meal: .dinner)
        XCTAssertEqual(entry.mealCategory, .dinner); XCTAssertEqual(entry.loggedAt, date)
        XCTAssertEqual(entry.referenceSnapshot, snapshot); XCTAssertEqual(entry.calories, 100)
        XCTAssertEqual(try container.mainContext.fetchCount(FetchDescriptor<FoodEntry>()), 1)
        try store.moveEntry(id: id, meal: .unassigned)
        XCTAssertNil(entry.mealCategoryRaw)
        XCTAssertThrowsError(try store.moveEntry(id: UUID(), meal: .lunch))
    }
    @MainActor func testExportV2PreservesAllTablesAndReadsV1WithoutNewSettings() throws {
        let container = try AppPersistence.makeContainer(inMemory: true)
        let suite = "ExportGoalsTest." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let goals = NutritionGoals(calories: 2400, protein: 145)
        try GoalPreferences(defaults: defaults).save(goals)
        defaults.set("light", forKey: GoalPreferences.appearanceKey)
        let export = try LocalDataExport.capture(context: container.mainContext, preferencesDefaults: defaults)
        let roundTrip = try LocalDataExport.decode(export.encoded())
        XCTAssertEqual(roundTrip.preferences?.goals, goals)
        XCTAssertEqual(roundTrip.preferences?.appearance, "light")
        XCTAssertEqual(export.formatVersion, 3)
        XCTAssertNotNil(export.preferences)
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: export.encoded()) as? [String: Any])
        json.removeValue(forKey: "preferences")
        XCTAssertThrowsError(try LocalDataExport.decode(JSONSerialization.data(withJSONObject: json)))
        json["formatVersion"] = 1
        let old = try LocalDataExport.decode(JSONSerialization.data(withJSONObject: json))
        XCTAssertEqual(old.formatVersion, 1); XCTAssertNil(old.preferences)
        XCTAssertEqual(old.recordCount, export.recordCount)
    }
}
