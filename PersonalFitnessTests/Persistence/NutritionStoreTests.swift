import XCTest
import SwiftData
@testable import PersonalFitness

final class NutritionStoreTests: XCTestCase {
    @MainActor
    func testRepeatPreservesOriginalSnapshotAndPortionAndIsIdempotent() throws {
        let container = try AppPersistence.makeContainer(inMemory: true)
        let store = NutritionStore(context: container.mainContext)
        let foodID = UUID(), sourceID = UUID(), copyID = UUID()
        let originalDay = Date(timeIntervalSince1970: 1_700_000_000)
        let targetDay = originalDay.addingTimeInterval(86_400)
        try store.saveFood(id: foodID, definition: food())
        try store.saveEntry(id: sourceID, definition: food(), quantity: 37.5, unit: .grams,
                            loggedAt: originalDay, sourceID: foodID, sourceKind: "food", meal: .lunch)
        let source = try XCTUnwrap(container.mainContext.fetch(FetchDescriptor<FoodEntry>()).first)
        let originalSnapshot = source.referenceSnapshot
        try store.saveFood(id: foodID, definition: food(400))
        let savedFood = try XCTUnwrap(container.mainContext.fetch(FetchDescriptor<SavedFood>()).first)
        try store.delete(savedFood)
        try store.repeatEntry(source, id: copyID, loggedAt: targetDay, meal: .dinner)
        try store.repeatEntry(source, id: copyID, loggedAt: targetDay, meal: .dinner)
        let entries = try container.mainContext.fetch(FetchDescriptor<FoodEntry>())
        XCTAssertEqual(entries.count, 2)
        let copy = try XCTUnwrap(entries.first { $0.id == copyID })
        XCTAssertEqual(copy.loggedAt, targetDay); XCTAssertEqual(copy.mealCategory, .dinner)
        XCTAssertEqual(copy.quantity, 37.5); XCTAssertEqual(copy.unit, .grams)
        XCTAssertEqual(copy.calories, 75); XCTAssertEqual(copy.proteinGrams, 3.75)
        XCTAssertEqual(copy.referenceSnapshot, originalSnapshot)
        XCTAssertEqual(copy.sourceID, foodID); XCTAssertEqual(copy.sourceKind, "food")
        XCTAssertEqual(try copy.definitionSnapshot().nutrients.calories, 200)
        XCTAssertEqual(source.mealCategory, .lunch)
    }
    @MainActor
    func testMealAttributionAndCRUDTotalsPreserveHistoricalDate() throws {
        let container = try AppPersistence.makeContainer(inMemory: true)
        let store = NutritionStore(context: container.mainContext)
        let past = Date(timeIntervalSince1970: 1_700_000_000), id = UUID()
        for meal in DiaryMeal.allCases {
            try store.saveEntry(id: id, definition: food(), quantity: 50, unit: .grams,
                                loggedAt: past, sourceID: nil, sourceKind: nil, meal: meal)
            let entries = try container.mainContext.fetch(FetchDescriptor<FoodEntry>())
            XCTAssertEqual(entries.count, 1)
            XCTAssertEqual(entries[0].mealCategory, meal)
            XCTAssertEqual(entries[0].loggedAt, past)
        }
        try store.saveEntry(id: id, definition: food(), quantity: 100, unit: .grams,
                            loggedAt: past, sourceID: nil, sourceKind: nil, meal: .dinner)
        try store.saveEntry(id: id, definition: food(), quantity: 25, unit: .grams,
                            loggedAt: past, sourceID: nil, sourceKind: nil)
        let entry = try XCTUnwrap(container.mainContext.fetch(FetchDescriptor<FoodEntry>()).first)
        XCTAssertEqual(entry.mealCategory, .dinner)
        XCTAssertEqual(entry.calories, 50); XCTAssertEqual(entry.proteinGrams, 2.5)
        XCTAssertEqual(entry.carbohydrateGrams, 7.5); XCTAssertEqual(entry.fatGrams, 1.25)
        try store.deleteEntry(id: id)
        XCTAssertEqual(try container.mainContext.fetchCount(FetchDescriptor<FoodEntry>()), 0)
    }

    private func food(_ calories: Double = 200) -> FoodDefinition {
        FoodDefinition(name: "Test food", preparation: .cooked,
            nutrients: FoodNutrients(calories: calories, protein: 10, carbohydrates: 30, fat: 5),
            referenceQuantity: 100, referenceUnit: .grams, equivalents: [:])
    }

    @MainActor
    func testStableIDsAndHistoricalSnapshotAfterFoodEditAndDeletion() throws {
        let container = try AppPersistence.makeContainer(inMemory: true)
        let store = NutritionStore(context: container.mainContext)
        let foodID = UUID(), entryID = UUID()
        let past = Date(timeIntervalSince1970: 1_700_000_000)
        try store.saveFood(id: foodID, definition: food())
        try store.saveEntry(id: entryID, definition: food(), quantity: 50, unit: .grams,
                            loggedAt: past, sourceID: foodID, sourceKind: "food")
        try store.saveFood(id: foodID, definition: food(400))
        let saved = try XCTUnwrap(container.mainContext.fetch(FetchDescriptor<SavedFood>()).first)
        XCTAssertEqual(try container.mainContext.fetchCount(FetchDescriptor<SavedFood>()), 1)
        XCTAssertEqual(saved.useCount, 1)
        try store.delete(saved)
        let entry = try XCTUnwrap(container.mainContext.fetch(FetchDescriptor<FoodEntry>()).first)
        XCTAssertEqual(entry.calories, 100)
        XCTAssertEqual(try entry.definitionSnapshot().nutrients.calories, 200)
        try store.saveEntry(id: entryID, definition: entry.definitionSnapshot(), quantity: 25, unit: .grams,
                            loggedAt: entry.loggedAt, sourceID: foodID, sourceKind: "food")
        XCTAssertEqual(entry.id, entryID)
        XCTAssertEqual(entry.calories, 50)
        XCTAssertEqual(entry.loggedAt, past)
        XCTAssertEqual(try container.mainContext.fetchCount(FetchDescriptor<FoodEntry>()), 1)
        try store.delete(entry)
        XCTAssertEqual(try container.mainContext.fetchCount(FetchDescriptor<FoodEntry>()), 0)
    }

    @MainActor
    func testRecipeSnapshotsRemainStableAfterLibraryChanges() throws {
        let container = try AppPersistence.makeContainer(inMemory: true)
        let store = NutritionStore(context: container.mainContext)
        let mealID = UUID(), entryID = UUID()
        let ingredients = [RecipeIngredient(food: food(), quantity: 100, unit: .grams)]
        try store.saveMeal(id: mealID, name: "Test recipe", kind: .recipe, servings: 2, ingredients: ingredients)
        let meal = try XCTUnwrap(container.mainContext.fetch(FetchDescriptor<SavedMeal>()).first)
        let definition = try meal.definition()
        try store.saveEntry(id: entryID, definition: definition, quantity: 1, unit: .servings,
                            loggedAt: .distantPast, sourceID: mealID, sourceKind: "Recipe")
        try store.saveMeal(id: mealID, name: "Updated recipe", kind: .recipe, servings: 4, ingredients: ingredients)
        XCTAssertEqual(try meal.definition().nutrients.calories, 50)
        XCTAssertEqual(try container.mainContext.fetchCount(FetchDescriptor<SavedMeal>()), 1)
        try store.delete(meal)
        let entry = try XCTUnwrap(container.mainContext.fetch(FetchDescriptor<FoodEntry>()).first)
        XCTAssertEqual(entry.calories, 100)
        XCTAssertEqual(entry.name, "Test recipe")
        XCTAssertEqual(try entry.definitionSnapshot().scaled(quantity: 2, unit: .servings).calories, 200)
    }

    @MainActor
    func testInvalidSaveDoesNotMutateOrDuplicateExistingEntry() throws {
        let container = try AppPersistence.makeContainer(inMemory: true)
        let store = NutritionStore(context: container.mainContext)
        let id = UUID()
        try store.saveEntry(id: id, definition: food(), quantity: 100, unit: .grams,
                            loggedAt: .distantPast, sourceID: nil, sourceKind: nil)
        XCTAssertThrowsError(try store.saveEntry(id: id, definition: food(), quantity: -1, unit: .grams,
                                                loggedAt: .distantPast, sourceID: nil, sourceKind: nil))
        let entry = try XCTUnwrap(container.mainContext.fetch(FetchDescriptor<FoodEntry>()).first)
        XCTAssertEqual(entry.calories, 200)
        XCTAssertEqual(entry.quantity, 100)
        XCTAssertEqual(try container.mainContext.fetchCount(FetchDescriptor<FoodEntry>()), 1)
    }

    @MainActor
    func testDiskReloadPreservesLibraryRecipeAndEntrySnapshots() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("Nutrition.sqlite")
        try writeDiskFixture(url)
        let container = try AppPersistence.makeContainer(url: url)
        XCTAssertEqual(try container.mainContext.fetchCount(FetchDescriptor<SavedFood>()), 1)
        XCTAssertEqual(try container.mainContext.fetchCount(FetchDescriptor<SavedMeal>()), 1)
        let entry = try XCTUnwrap(container.mainContext.fetch(FetchDescriptor<FoodEntry>()).first)
        XCTAssertEqual(entry.calories, 100)
        XCTAssertEqual(entry.quantity, 50)
        XCTAssertEqual(try entry.definitionSnapshot().referenceUnit, .grams)
    }

    @MainActor
    func testRepeatedEntrySaveDoesNotDuplicateRecordsOrUsage() throws {
        let container = try AppPersistence.makeContainer(inMemory: true)
        let store = NutritionStore(context: container.mainContext)
        let foodID = UUID(), entryID = UUID()
        try store.saveFood(id: foodID, definition: food())
        for _ in 0..<2 {
            try store.saveEntry(id: entryID, definition: food(), quantity: 100, unit: .grams,
                                loggedAt: .distantPast, sourceID: foodID, sourceKind: "food")
        }
        XCTAssertEqual(try container.mainContext.fetchCount(FetchDescriptor<FoodEntry>()), 1)
        let saved = try XCTUnwrap(container.mainContext.fetch(FetchDescriptor<SavedFood>()).first)
        XCTAssertEqual(saved.useCount, 1)
        XCTAssertNotNil(saved.lastUsedAt)
    }

    @MainActor
    private func writeDiskFixture(_ url: URL) throws {
        let container = try AppPersistence.makeContainer(url: url)
        let store = NutritionStore(context: container.mainContext)
        let id = UUID()
        try store.saveFood(id: id, definition: food())
        try store.saveMeal(id: UUID(), name: "Disk meal", kind: .meal, servings: 1,
                           ingredients: [RecipeIngredient(foodID: id, food: food(), quantity: 100, unit: .grams)])
        try store.saveEntry(id: UUID(), definition: food(), quantity: 50, unit: .grams,
                            loggedAt: .distantPast, sourceID: id, sourceKind: "food")
    }
}
