import XCTest
import SwiftData
@testable import PersonalFitness

final class CatalogImporterTests: XCTestCase {
    private func catalog(_ name: String) throws -> OfflineCatalog {
        let url = try XCTUnwrap(Bundle.main.url(forResource: name + "-v1", withExtension: "json", subdirectory: "Catalogs"))
        return try JSONDecoder().decode(OfflineCatalog.self, from: Data(contentsOf: url)).validated()
    }
    private func smallCatalogs() throws -> [OfflineCatalog] {
        var food = try catalog("foods"), exercise = try catalog("exercises")
        food.foods = Array(food.foods.prefix(2)); exercise.exercises = Array(exercise.exercises.prefix(2))
        return [food, exercise]
    }
    @MainActor
    func testActualBundledImportIsIdempotentResumesPartialImportAndPreservesCustomRecords() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let container = try AppPersistence.makeContainer(url: folder.appendingPathComponent("full.sqlite"))
        let custom = ExerciseSnapshot(name: "My existing exercise")
        try WorkoutStore(context: container.mainContext).saveExercise(custom)
        let catalogs = try [catalog("foods"), catalog("exercises")]
        var customFood = catalogs[0].foods[0].definition; customFood.name = "My existing food"
        let customFoodID = UUID()
        try NutritionStore(context: container.mainContext).saveFood(id: customFoodID, definition: customFood)
        var partial = catalogs[0]; partial.foods = Array(partial.foods.prefix(100))
        _ = try await CatalogImporter(modelContainer: container).run(catalogs: [partial])
        let clock = Date()
        let first = try await CatalogImporter(modelContainer: container).run(catalogs: catalogs)
        print("Catalog initial remaining import seconds: \(Date().timeIntervalSince(clock)); inserted \(first.inserted)")
        let second = try await CatalogImporter(modelContainer: container).run(catalogs: catalogs)
        XCTAssertEqual(second.inserted, 0); XCTAssertEqual(second.updated, 0)
        XCTAssertEqual(second.unchanged, catalogs[0].foods.count + catalogs[1].exercises.count)
        let context = ModelContext(container)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<SavedFood>()), catalogs[0].foods.count + 1)
        XCTAssertTrue(try context.fetch(FetchDescriptor<SavedFood>()).contains { $0.id == customFoodID && $0.name == customFood.name })
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<ExerciseRecord>()), catalogs[1].exercises.count + 1)
        XCTAssertTrue(try context.fetch(FetchDescriptor<ExerciseRecord>()).contains { $0.id == custom.id && $0.name == custom.name })
    }
    @MainActor
    func testUpdatesAcrossDiskReopenProtectDiaryRecipesRoutinesCompletedSessionsAndPersonalEdits() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appendingPathComponent("test.sqlite")
        let container = try AppPersistence.makeContainer(url: url)
        var catalogs = try smallCatalogs()
        _ = try await CatalogImporter(modelContainer: container).run(catalogs: catalogs)
        let context = ModelContext(container), nutrition = NutritionStore(context: ModelContext(container))
        let food = try XCTUnwrap(context.fetch(FetchDescriptor<SavedFood>()).first)
        let original = try food.definition()
        try nutrition.saveEntry(id: UUID(), definition: original, quantity: 50, unit: .grams, loggedAt: .distantPast, sourceID: food.id, sourceKind: "food")
        try nutrition.saveMeal(id: UUID(), name: "Existing recipe", kind: .recipe, servings: 2, ingredients: [RecipeIngredient(food: original, quantity: 100, unit: .grams)])
        var edited = original; edited.name = "My chosen name"
        try nutrition.saveFood(id: food.id, definition: edited)
        let workoutContext = ModelContext(container), workoutStore = WorkoutStore(context: workoutContext)
        var exercise = try XCTUnwrap(workoutContext.fetch(FetchDescriptor<ExerciseRecord>()).first).snapshot()
        exercise.notes = "My personal note"; try workoutStore.saveExercise(exercise)
        let sets = [SessionExercise(exercise: exercise, sets: [TrainingSet(reps: 10, weightKg: 5, completed: true)])]
        try workoutStore.saveRoutine(id: UUID(), name: "Existing routine", exercises: sets)
        let session = StrengthDraft(name: "Existing completed session", exercises: sets)
        try workoutStore.saveSession(session); try workoutStore.saveSession(session.finished())
        let sessionBefore = try XCTUnwrap(workoutContext.fetch(FetchDescriptor<StrengthSession>()).first).draftData
        let recipeBefore = try XCTUnwrap(nutrition.context.fetch(FetchDescriptor<SavedMeal>()).first).ingredientsData
        let routineBefore = try XCTUnwrap(workoutContext.fetch(FetchDescriptor<WorkoutRoutine>()).first).exercisesData
        for i in catalogs[0].foods.indices { catalogs[0].foods[i].definition.nutrients.calories += 5; catalogs[0].foods[i].definition.aliases = ["release two alias"] }
        for i in catalogs[1].exercises.indices { catalogs[1].exercises[i].exercise.equipment = "Source corrected equipment" }
        catalogs[0].release = "selection-2"; catalogs[1].release = "selection-2"
        let reopened = try AppPersistence.makeContainer(url: url)
        let updated = try await CatalogImporter(modelContainer: reopened).run(catalogs: catalogs)
        XCTAssertEqual(updated.updated, 4)
        let verify = ModelContext(reopened)
        let after = try XCTUnwrap(verify.fetch(FetchDescriptor<SavedFood>()).first { $0.id == food.id })
        XCTAssertEqual(after.name, "My chosen name"); XCTAssertEqual(after.useCount, 1)
        XCTAssertEqual(try after.definition().nutrients.calories, original.nutrients.calories + 5)
        XCTAssertTrue(after.matchesLibrary("release two alias"))
        let snapshot = try XCTUnwrap(verify.fetch(FetchDescriptor<FoodEntry>()).first)
        XCTAssertEqual(snapshot.calories, original.nutrients.calories / 2)
        XCTAssertEqual(try snapshot.definitionSnapshot().name, original.name)
        XCTAssertEqual(try XCTUnwrap(verify.fetch(FetchDescriptor<SavedMeal>()).first).ingredientsData, recipeBefore)
        XCTAssertEqual(try XCTUnwrap(verify.fetch(FetchDescriptor<WorkoutRoutine>()).first).exercisesData, routineBefore)
        XCTAssertEqual(try XCTUnwrap(verify.fetch(FetchDescriptor<StrengthSession>()).first).draftData, sessionBefore)
        let exerciseAfter = try XCTUnwrap(verify.fetch(FetchDescriptor<ExerciseRecord>()).first { $0.id == exercise.id }).snapshot()
        XCTAssertEqual(exerciseAfter.notes, "My personal note"); XCTAssertEqual(exerciseAfter.equipment, "Source corrected equipment")
    }
    @MainActor
    func testArchivesStayHiddenAfterRelaunchAndNewReleaseWhileCustomDeletionRemainsDeletion() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appendingPathComponent("archive.sqlite")
        let container = try AppPersistence.makeContainer(url: url)
        var catalogs = try smallCatalogs()
        _ = try await CatalogImporter(modelContainer: container).run(catalogs: catalogs)
        let context = ModelContext(container)
        let food = try XCTUnwrap(context.fetch(FetchDescriptor<SavedFood>()).first)
        let exercise = try XCTUnwrap(context.fetch(FetchDescriptor<ExerciseRecord>()).first)
        try NutritionStore(context: context).delete(food); try WorkoutStore(context: context).delete(exercise)
        catalogs[0].release = "next"; catalogs[1].release = "next"
        let reopened = try AppPersistence.makeContainer(url: url)
        _ = try await CatalogImporter(modelContainer: reopened).run(catalogs: catalogs)
        let verify = ModelContext(reopened)
        XCTAssertFalse(try XCTUnwrap(verify.fetch(FetchDescriptor<SavedFood>()).first { $0.id == food.id }).libraryVisible)
        XCTAssertFalse(try XCTUnwrap(verify.fetch(FetchDescriptor<ExerciseRecord>()).first { $0.id == exercise.id }).libraryVisible)
        let custom = ExerciseSnapshot(name: "Custom deletable")
        try WorkoutStore(context: verify).saveExercise(custom)
        try WorkoutStore(context: verify).delete(try XCTUnwrap(verify.fetch(FetchDescriptor<ExerciseRecord>()).first { $0.id == custom.id }))
        XCTAssertEqual(try verify.fetchCount(FetchDescriptor<ExerciseRecord>()), 2)
    }
    @MainActor
    func testCollisionAndInvalidReleaseAreRejectedBeforeAnyImportSave() async throws {
        let container = try AppPersistence.makeContainer(inMemory: true)
        let catalogs = try smallCatalogs(), first = catalogs[0].foods[0]
        var custom = first.definition; custom.name = "Must never overwrite me"
        try NutritionStore(context: container.mainContext).saveFood(id: first.id, definition: custom)
        do { _ = try await CatalogImporter(modelContainer: container).run(catalogs: catalogs); XCTFail("Expected collision") }
        catch { XCTAssertTrue(error is CatalogError) }
        XCTAssertEqual(try container.mainContext.fetchCount(FetchDescriptor<SavedFood>()), 1)
        XCTAssertEqual(try container.mainContext.fetch(FetchDescriptor<SavedFood>()).first?.name, "Must never overwrite me")
        XCTAssertEqual(try container.mainContext.fetchCount(FetchDescriptor<ExerciseRecord>()), 0)
        var invalid = catalogs[1]; invalid.source.license = "unverified"
        do { _ = try await CatalogImporter(modelContainer: container).run(catalogs: [invalid]); XCTFail("Expected validation error") } catch { }
        XCTAssertEqual(try container.mainContext.fetchCount(FetchDescriptor<ExerciseRecord>()), 0)
    }
}
