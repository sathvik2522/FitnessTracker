import XCTest
import SwiftData
@testable import PersonalFitness

final class WorkoutStoreTests: XCTestCase {
    @MainActor
    func testStarterLibraryIsIdempotentAndPreservesCustomEditsAndMetadata() throws {
        let container = try AppPersistence.makeContainer(inMemory: true)
        let store = WorkoutStore(context: container.mainContext)
        try store.addStarterExercises()
        var edited = StarterExercises.all[0]; edited.name = "My squat"; edited.equipment = "Rack"
        try store.saveExercise(edited)
        let custom = ExerciseSnapshot(name: "My custom lift", equipment: "Band", movementType: "Pull")
        try store.saveExercise(custom)
        try store.addStarterExercises()
        let saved = try container.mainContext.fetch(FetchDescriptor<ExerciseRecord>())
        XCTAssertEqual(saved.count, StarterExercises.all.count + 1)
        XCTAssertEqual(try saved.first { $0.id == edited.id }?.snapshot().equipment, "Rack")
        XCTAssertEqual(saved.first { $0.id == edited.id }?.name, "My squat")
        XCTAssertEqual(try saved.first { $0.id == custom.id }?.snapshot().movementType, "Pull")
    }

    private let past = Date(timeIntervalSince1970: 1_700_000_000)
    @MainActor
    func testActiveWorkoutEditsResumeFromDiskAndKeepTimer() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("Workouts.sqlite")
        let id = try writeActive(url)
        let container = try AppPersistence.makeContainer(url: url)
        let sessions = try container.mainContext.fetch(FetchDescriptor<StrengthSession>())
        XCTAssertEqual(sessions.count, 1)
        let draft = try sessions[0].draft()
        XCTAssertEqual(draft.id, id)
        XCTAssertEqual(draft.status, .active)
        XCTAssertEqual(draft.exercises.map { $0.exercise.name }, ["Row", "Squat"])
        XCTAssertEqual(draft.exercises[1].sets[0].reps, 12)
        XCTAssertEqual(draft.exercises[1].sets[0].weightKg, 40)
        XCTAssertEqual(draft.restEndsAt, past.addingTimeInterval(90))
    }
    @MainActor private func writeActive(_ url: URL) throws -> UUID {
        let container = try AppPersistence.makeContainer(url: url)
        let store = WorkoutStore(context: container.mainContext)
        var draft = try store.start()
        draft.start = past
        draft.exercises = [SessionExercise(exercise: ExerciseSnapshot(name: "Squat"))]
        draft.exercises[0].sets[0].reps = 12
        draft.exercises[0].sets[0].weightKg = 40
        draft.exercises.append(SessionExercise(exercise: ExerciseSnapshot(name: "Row")))
        draft.exercises.reverse()
        draft.restEndsAt = past.addingTimeInterval(90)
        try store.saveSession(draft)
        return draft.id
    }
    @MainActor
    func testSingleActiveCompletionCancellationAndHistoricalSetEditing() throws {
        let container = try AppPersistence.makeContainer(inMemory: true)
        let store = WorkoutStore(context: container.mainContext)
        var draft = try store.start()
        XCTAssertThrowsError(try store.start())
        draft.start = past
        draft.exercises = [SessionExercise(exercise: ExerciseSnapshot(name: "Push-up", bodyweight: true), sets: [TrainingSet(reps: 10, completed: true)])]
        try store.saveSession(draft)
        draft = try draft.finished(at: past.addingTimeInterval(600))
        try store.saveSession(draft)
        draft.exercises[0].sets[0].reps = 15
        try store.saveSession(draft)
        let loaded = try XCTUnwrap(container.mainContext.fetch(FetchDescriptor<StrengthSession>()).first).draft()
        XCTAssertEqual(loaded.start, past)
        XCTAssertEqual(loaded.status, .completed)
        XCTAssertEqual(loaded.exercises[0].sets[0].reps, 15)
        XCTAssertEqual(try container.mainContext.fetchCount(FetchDescriptor<StrengthSession>()), 1)
        let active = try store.start()
        let model = WorkoutSessionModel(draft: active)
        XCTAssertTrue(model.cancel(context: container.mainContext))
        XCTAssertEqual(model.draft.status, .cancelled)
        XCTAssertNotNil(model.draft.end)
        XCTAssertEqual(try container.mainContext.fetchCount(FetchDescriptor<StrengthSession>()), 2)
    }
    @MainActor
    func testLibraryAndRoutineChangesDoNotRewriteSessions() throws {
        let container = try AppPersistence.makeContainer(inMemory: true)
        let store = WorkoutStore(context: container.mainContext)
        var definition = ExerciseSnapshot(name: "Original squat", notes: "Original cues")
        try store.saveExercise(definition)
        let routineID = UUID()
        try store.saveRoutine(id: routineID, name: "Leg day", exercises: [SessionExercise(exercise: definition)])
        let routine = try XCTUnwrap(container.mainContext.fetch(FetchDescriptor<WorkoutRoutine>()).first)
        let session = try store.start(routine: routine)
        definition.name = "Edited squat"; definition.notes = "New notes"
        try store.saveExercise(definition)
        try store.saveRoutine(id: routineID, name: "New routine", exercises: [SessionExercise(exercise: definition)])
        try store.delete(routine)
        let exercise = try XCTUnwrap(container.mainContext.fetch(FetchDescriptor<ExerciseRecord>()).first)
        try store.delete(exercise)
        let loaded = try XCTUnwrap(container.mainContext.fetch(FetchDescriptor<StrengthSession>()).first).draft()
        XCTAssertEqual(loaded.id, session.id)
        XCTAssertEqual(loaded.name, "Leg day")
        XCTAssertEqual(loaded.exercises[0].exercise.name, "Original squat")
        XCTAssertEqual(loaded.exercises[0].exercise.notes, "Original cues")
    }
    @MainActor
    func testDuplicateRoutineKeepsOriginalAndUsesNewDraftIdentifiers() throws {
        let container = try AppPersistence.makeContainer(inMemory: true)
        let store = WorkoutStore(context: container.mainContext)
        let originalID = UUID()
        let item = SessionExercise(exercise: ExerciseSnapshot(name: "Squat"),
                                   sets: [TrainingSet(reps: 5, weightKg: 60, completed: false)])
        try store.saveRoutine(id: originalID, name: "Strength", exercises: [item])
        let original = try XCTUnwrap(container.mainContext.fetch(FetchDescriptor<WorkoutRoutine>()).first)
        let copiedID = try store.duplicateRoutine(original)
        let routines = try container.mainContext.fetch(FetchDescriptor<WorkoutRoutine>())
        XCTAssertEqual(routines.count, 2)
        XCTAssertEqual(original.name, "Strength")
        let copy = try XCTUnwrap(routines.first { $0.id == copiedID })
        XCTAssertEqual(copy.name, "Strength Copy")
        let copiedItem = try XCTUnwrap(copy.exercises().first)
        XCTAssertEqual(copiedItem.exercise.id, item.exercise.id)
        XCTAssertNotEqual(copiedItem.id, item.id)
        XCTAssertNotEqual(copiedItem.sets[0].id, item.sets[0].id)
        XCTAssertEqual(copiedItem.sets[0].reps, 5)
        XCTAssertEqual(copiedItem.sets[0].weightKg, 60)
    }
    @MainActor
    func testInvalidEditsLeaveSavedSetsUnchanged() throws {
        let container = try AppPersistence.makeContainer(inMemory: true)
        let store = WorkoutStore(context: container.mainContext)
        var draft = try store.start()
        draft.exercises = [SessionExercise(exercise: ExerciseSnapshot(name: "Bench"))]
        try store.saveSession(draft)
        let model = WorkoutSessionModel(draft: draft)
        XCTAssertFalse(model.update(context: container.mainContext) { $0.exercises[0].sets[0].weightKg = -10 })
        let saved = try XCTUnwrap(container.mainContext.fetch(FetchDescriptor<StrengthSession>()).first).draft()
        XCTAssertEqual(saved.exercises[0].sets[0].weightKg, 0)
        XCTAssertEqual(model.draft, draft)
    }
    @MainActor
    func testCardioUpsertAndNutritionStoreMigration() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("Migration.sqlite")
        try writeNutritionStore(url)
        let container = try AppPersistence.makeContainer(url: url)
        XCTAssertEqual(try container.mainContext.fetch(FetchDescriptor<FoodEntry>()).first?.calories, 123)
        let store = WorkoutStore(context: container.mainContext)
        var cardio = CardioDraft(activity: .stairs, start: past, durationSeconds: 600, reportedCalories: 100)
        try store.saveCardio(cardio)
        cardio.reportedCalories = 250
        try store.saveCardio(cardio)
        XCTAssertEqual(try container.mainContext.fetchCount(FetchDescriptor<CardioSession>()), 1)
        let saved = try XCTUnwrap(container.mainContext.fetch(FetchDescriptor<CardioSession>()).first).draft()
        XCTAssertEqual(saved.start, past)
        XCTAssertEqual(saved.reportedCalories, 250)
        XCTAssertEqual(saved.calorieSource, .machine)
        // Workout persistence never creates or mutates food/energy inputs.
        XCTAssertEqual(try container.mainContext.fetch(FetchDescriptor<FoodEntry>()).first?.calories, 123)
    }
    @MainActor private func writeNutritionStore(_ url: URL) throws {
        let schema = Schema([FoodEntry.self, SavedFood.self, SavedMeal.self])
        let container = try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, url: url, cloudKitDatabase: .none)])
        container.mainContext.insert(FoodEntry(name: "Existing", calories: 123, loggedAt: past))
        try container.mainContext.save()
    }
    @MainActor
    func testRoutineAndSessionEditsAndDeletionsSurviveDiskReopen() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("Lifecycle.sqlite")
        try writeAndEditLifecycle(url)
        try verifyAndDeleteLifecycle(url)
        let reopened = try AppPersistence.makeContainer(url: url)
        XCTAssertEqual(try reopened.mainContext.fetchCount(FetchDescriptor<WorkoutRoutine>()), 0)
        XCTAssertEqual(try reopened.mainContext.fetchCount(FetchDescriptor<StrengthSession>()), 0)
        XCTAssertEqual(try reopened.mainContext.fetchCount(FetchDescriptor<CardioSession>()), 0)
    }
    @MainActor private func writeAndEditLifecycle(_ url: URL) throws {
        let container = try AppPersistence.makeContainer(url: url)
        let store = WorkoutStore(context: container.mainContext)
        let id = UUID(), exercise = ExerciseSnapshot(name: "Original")
        try store.saveRoutine(id: id, name: "Original routine", exercises: [SessionExercise(exercise: exercise)])
        let routine = try XCTUnwrap(container.mainContext.fetch(FetchDescriptor<WorkoutRoutine>()).first)
        var draft = try store.start(routine: routine)
        draft.start = past; draft.exercises[0].sets[0] = TrainingSet(reps: 12, weightKg: 20, completed: true)
        try store.saveSession(try draft.finished(at: past.addingTimeInterval(600)))
        try store.saveRoutine(id: id, name: "Edited routine", exercises: [SessionExercise(exercise: ExerciseSnapshot(name: "New"))])
        var cardio = CardioDraft(activity: .stairs, start: past, durationSeconds: 600, resistance: 4)
        try store.saveCardio(cardio); cardio.resistance = 8; try store.saveCardio(cardio)
    }
    @MainActor private func verifyAndDeleteLifecycle(_ url: URL) throws {
        let container = try AppPersistence.makeContainer(url: url), context = container.mainContext
        let store = WorkoutStore(context: context)
        let routine = try XCTUnwrap(context.fetch(FetchDescriptor<WorkoutRoutine>()).first)
        XCTAssertEqual(routine.name, "Edited routine")
        let session = try XCTUnwrap(context.fetch(FetchDescriptor<StrengthSession>()).first)
        let draft = try session.draft()
        XCTAssertEqual(draft.status, .completed)
        XCTAssertEqual(draft.exercises[0].exercise.name, "Original")
        XCTAssertEqual(draft.exercises[0].sets[0].weightKg, 20)
        XCTAssertEqual(draft.exercises[0].sets[0].reps, 12)
        let cardio = try XCTUnwrap(context.fetch(FetchDescriptor<CardioSession>()).first)
        XCTAssertEqual(try cardio.draft().resistance, 8)
        try store.delete(routine); try store.delete(session); try store.delete(cardio)
    }

}
