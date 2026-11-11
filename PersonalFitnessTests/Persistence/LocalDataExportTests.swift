import XCTest
import SwiftData
@testable import PersonalFitness

final class LocalDataExportTests: XCTestCase {
    @MainActor
    func testAllTablesExportToFileAndRoundTripWithoutMutatingStore() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("ExportFixture.sqlite")
        try writeFixture(url)
        let container = try AppPersistence.makeContainer(url: url)
        let before = try LocalDataExport.capture(context: container.mainContext, now: .distantPast,
                                                timeZone: TimeZone(identifier: "America/Phoenix")!, appVersion: "Test")
        XCTAssertEqual(before.recordCount, 8)
        let destination = directory.appendingPathComponent("PersonalFitness.json")
        try before.encoded().write(to: destination, options: .atomic)
        XCTAssertTrue(FileManager.default.fileExists(atPath: destination.path))
        let read = try LocalDataExport.decode(Data(contentsOf: destination))
        XCTAssertEqual(read.timeZoneIdentifier, "America/Phoenix")
        XCTAssertEqual(read.recordCount, 8)
        XCTAssertEqual(read.foodEntries[0].loggedAt, before.foodEntries[0].loggedAt)
        XCTAssertEqual(read.foodEntries[0].loggedAt.timeIntervalSince1970, 1_700_000_000.125)
        XCTAssertEqual(read.foodEntries[0].mealCategoryRaw, DiaryMeal.breakfast.rawValue)
        XCTAssertEqual(read.foodEntries[0].calories, 100)
        XCTAssertEqual(read.foodEntries[0].proteinGrams, 5)
        XCTAssertEqual(read.foodEntries[0].quantity, 50)
        XCTAssertEqual(read.foodEntries[0].sourceID, before.savedFoods[0].id)
        XCTAssertEqual(read.foodEntries[0].referenceSnapshot, before.foodEntries[0].referenceSnapshot)
        XCTAssertEqual(read.savedFoods[0].definitionData, before.savedFoods[0].definitionData)
        XCTAssertEqual(read.savedFoods[0].useCount, 1)
        XCTAssertEqual(read.savedMeals[0].ingredientsData, before.savedMeals[0].ingredientsData)
        XCTAssertEqual(read.savedMeals[0].servings, 2)
        XCTAssertEqual(read.exercises[0].snapshotData, before.exercises[0].snapshotData)
        XCTAssertEqual(read.routines[0].exercisesData, before.routines[0].exercisesData)
        XCTAssertEqual(read.strengthSessions[0].draftData, before.strengthSessions[0].draftData)
        XCTAssertEqual(read.strengthSessions[0].statusRaw, "active")
        let draft = try JSONDecoder().decode(StrengthDraft.self, from: read.strengthSessions[0].draftData)
        XCTAssertEqual(draft.exercises[0].sets[0].reps, 12)
        XCTAssertEqual(draft.exercises[0].sets[0].weightKg, 20)
        XCTAssertEqual(read.cardioSessions[0].draftData, before.cardioSessions[0].draftData)
        XCTAssertEqual(read.manualWeights[0].kilograms, 72.5)
        XCTAssertEqual(read.manualWeights[0].id, before.manualWeights[0].id)
        let after = try LocalDataExport.capture(context: container.mainContext, now: .distantPast,
                                               timeZone: TimeZone(identifier: "America/Phoenix")!, appVersion: "Test")
        XCTAssertEqual(try before.encoded(), try after.encoded(), "Export must not mutate any personal records")
        XCTAssertFalse(container.mainContext.hasChanges)
    }

    @MainActor
    private func writeFixture(_ url: URL) throws {
        let container = try AppPersistence.makeContainer(url: url), context = container.mainContext
        let definition = FoodDefinition(name: "My oats", preparation: .raw,
            nutrients: FoodNutrients(calories: 200, protein: 10, carbohydrates: 30, fat: 5),
            referenceQuantity: 100, referenceUnit: .grams, equivalents: [:])
        let nutrition = NutritionStore(context: context), foodID = UUID()
        try nutrition.saveFood(id: foodID, definition: definition)
        try nutrition.saveEntry(id: UUID(), definition: definition, quantity: 50, unit: .grams,
            loggedAt: Date(timeIntervalSince1970: 1_700_000_000.125), sourceID: foodID, sourceKind: "food", meal: .breakfast)
        try nutrition.saveMeal(id: UUID(), name: "My recipe", kind: .recipe, servings: 2,
            ingredients: [RecipeIngredient(foodID: foodID, food: definition, quantity: 100, unit: .grams)])
        let workouts = WorkoutStore(context: context), exercise = ExerciseSnapshot(name: "My row", notes: "Private note")
        try workouts.saveExercise(exercise)
        let items = [SessionExercise(exercise: exercise, sets: [TrainingSet(reps: 12, weightKg: 20, completed: true)])]
        try workouts.saveRoutine(id: UUID(), name: "My routine", exercises: items)
        var active = try workouts.start(); active.exercises = items
        try workouts.saveSession(active)
        try workouts.saveCardio(CardioDraft(activity: .stairs, start: Date.now.addingTimeInterval(-3600),
            durationSeconds: 1200, resistance: 6, floors: 30, reportedCalories: 150))
        try ProgressStore(context: context).saveWeight(WeightObservation(id: UUID(), date: .distantPast, kilograms: 72.5, origin: .manual))
    }

    @MainActor
    func testEmptyExportAndUnsupportedOrCorruptFile() throws {
        let container = try AppPersistence.makeContainer(inMemory: true)
        let empty = try LocalDataExport.capture(context: container.mainContext)
        XCTAssertEqual(try LocalDataExport.decode(empty.encoded()).recordCount, 0)
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: empty.encoded()) as? [String: Any])
        object["formatVersion"] = 99
        XCTAssertThrowsError(try LocalDataExport.decode(JSONSerialization.data(withJSONObject: object)))
        XCTAssertThrowsError(try LocalDataExport.decode(Data("invalid JSON".utf8)))
        XCTAssertFalse(container.mainContext.hasChanges)
    }
}
