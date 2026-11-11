import XCTest
import SwiftData
@testable import PersonalFitness

private enum OriginalDiarySchema: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(1, 0, 0) }
    static var models: [any PersistentModel.Type] { [FoodEntry.self] }
    @Model final class FoodEntry {
        @Attribute(.unique) var id: UUID
        var loggedAt: Date
        var name: String
        var calories: Double
        var proteinGrams: Double
        var carbohydrateGrams: Double
        var fatGrams: Double
        init() {
            id = UUID(); loggedAt = Date(timeIntervalSince1970: 1_700_000_000)
            name = "Legacy food"; calories = 123; proteinGrams = 10; carbohydrateGrams = 20; fatGrams = 1
        }
    }
}

private enum BeforeMealAttributionSchema: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(2, 0, 0) }
    static var models: [any PersistentModel.Type] {
        [FoodEntry.self, SavedFood.self, SavedMeal.self, ExerciseRecord.self,
         WorkoutRoutine.self, StrengthSession.self, CardioSession.self, ManualWeight.self]
    }
    @Model final class FoodEntry {
        @Attribute(.unique) var id: UUID
        var loggedAt: Date
        var name: String
        var calories: Double
        var proteinGrams: Double
        var carbohydrateGrams: Double
        var fatGrams: Double
        var quantity: Double = 1
        var unitRaw: String = "serving"
        var referenceSnapshot: Data? = nil
        var sourceID: UUID? = nil
        var sourceKind: String? = nil
        init(snapshot: Data, id: UUID) {
            self.id = id; loggedAt = Date(timeIntervalSince1970: 1_700_000_000)
            name = "Before meal tags"; calories = 123; proteinGrams = 10; carbohydrateGrams = 20; fatGrams = 1
            referenceSnapshot = snapshot
        }
    }
}

final class NutritionMigrationTests: XCTestCase {
    @MainActor
    func testPreviousEightEntityStoreMigratesAndMealTagPersistsAfterReopen() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("Previous.sqlite"), id = UUID()
        let snapshot = Data("historical snapshot bytes".utf8)
        try writePreviousStore(url, id: id, snapshot: snapshot)
        try assignMealAfterMigration(url, id: id, snapshot: snapshot)
        let reopened = try AppPersistence.makeContainer(url: url)
        let entry = try XCTUnwrap(reopened.mainContext.fetch(FetchDescriptor<FoodEntry>()).first)
        XCTAssertEqual(entry.mealCategory, .lunch)
        XCTAssertEqual(entry.id, id); XCTAssertEqual(entry.referenceSnapshot, snapshot)
        XCTAssertEqual(try reopened.mainContext.fetchCount(FetchDescriptor<StrengthSession>()), 1)
        XCTAssertEqual(try reopened.mainContext.fetchCount(FetchDescriptor<ManualWeight>()), 1)
    }
    @MainActor
    private func writePreviousStore(_ url: URL, id: UUID, snapshot: Data) throws {
        let schema = Schema(BeforeMealAttributionSchema.models)
        let container = try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, url: url, cloudKitDatabase: .none)])
        container.mainContext.insert(BeforeMealAttributionSchema.FoodEntry(snapshot: snapshot, id: id))
        container.mainContext.insert(try StrengthSession(StrengthDraft()))
        container.mainContext.insert(ManualWeight(id: UUID(), date: .distantPast, kilograms: 75))
        try container.mainContext.save()
    }
    @MainActor
    private func assignMealAfterMigration(_ url: URL, id: UUID, snapshot: Data) throws {
        let container = try AppPersistence.makeContainer(url: url)
        let entry = try XCTUnwrap(container.mainContext.fetch(FetchDescriptor<FoodEntry>()).first)
        XCTAssertNil(entry.mealCategoryRaw); XCTAssertEqual(entry.mealCategory, .unassigned)
        XCTAssertEqual(entry.id, id); XCTAssertEqual(entry.calories, 123)
        XCTAssertEqual(entry.referenceSnapshot, snapshot)
        entry.mealCategoryRaw = DiaryMeal.lunch.rawValue
        try container.mainContext.save()
    }

    @MainActor
    private func writeOriginalStore(_ url: URL) throws {
        let schema = Schema(OriginalDiarySchema.models)
        let container = try ModelContainer(for: schema, configurations: [
            ModelConfiguration(schema: schema, url: url, cloudKitDatabase: .none)])
        container.mainContext.insert(OriginalDiarySchema.FoodEntry())
        try container.mainContext.save()
    }

    @MainActor
    func testExistingDiaryMigratesWithoutLosingHistoricalNutrition() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("Legacy.sqlite")
        try writeOriginalStore(url)
        let container = try AppPersistence.makeContainer(url: url)
        let entry = try XCTUnwrap(container.mainContext.fetch(FetchDescriptor<FoodEntry>()).first)
        XCTAssertEqual(entry.name, "Legacy food")
        XCTAssertEqual(entry.calories, 123)
        XCTAssertEqual(entry.proteinGrams, 10)
        XCTAssertEqual(entry.quantity, 1)
        XCTAssertEqual(entry.unit, .servings)
        XCTAssertNil(entry.referenceSnapshot)
        XCTAssertEqual(try entry.definitionSnapshot().scaled(quantity: 2, unit: .servings).calories, 246)
    }
}
