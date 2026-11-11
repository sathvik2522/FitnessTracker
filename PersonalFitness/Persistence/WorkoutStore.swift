import Foundation
import SwiftData

extension Notification.Name {
    static let workoutsDidChange = Notification.Name("PersonalFitness.workoutsDidChange")
}

/// Validates value drafts before committing stable-ID updates to SwiftData.
/// Exercise/routine snapshots stay inside each session so library edits cannot
/// rewrite historical sets. Manual sessions never become energy measurements.
@MainActor
struct WorkoutStore {
    let context: ModelContext
    private func commit(_ change: () throws -> Void) throws {
        do {
            try change()
            try context.save()
            NotificationCenter.default.post(name: .workoutsDidChange, object: nil)
        } catch { context.rollback(); throw error }
    }
    func addStarterExercises() throws {
        let existing = Set(try context.fetch(FetchDescriptor<ExerciseRecord>()).map(\.id))
        try commit {
            for exercise in StarterExercises.all where !existing.contains(exercise.id) {
                context.insert(try ExerciseRecord(exercise))
            }
        }
    }

    func saveExercise(_ exercise: ExerciseSnapshot) throws {
        var exercise = try exercise.validated()
        let id = exercise.id
        let existing = try context.fetch(FetchDescriptor<ExerciseRecord>(predicate: #Predicate { $0.id == id })).first
        if let previous = try existing?.snapshot(), let origin = previous.catalog {
            exercise.catalog = origin
            if let baseline = origin.baseline {
                let old = try JSONDecoder().decode(ExerciseSnapshot.self, from: baseline)
                let modified = CatalogMerge.stripped(exercise) != old
                exercise.catalog?.userModified = modified
            }
        }
        let data = try JSONEncoder().encode(exercise)
        try commit {
            if let existing { existing.name = exercise.name; existing.snapshotData = data }
            else { context.insert(try ExerciseRecord(exercise)) }
        }
    }
    func saveRoutine(id: UUID, name: String, exercises: [SessionExercise]) throws {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !exercises.isEmpty else { throw TrainingError.exercises }
        _ = try StrengthDraft(name: name, exercises: exercises).validated()
        let data = try JSONEncoder().encode(exercises)
        let existing = try context.fetch(FetchDescriptor<WorkoutRoutine>(predicate: #Predicate { $0.id == id })).first
        try commit {
            if let existing { existing.name = name; existing.exercisesData = data }
            else { context.insert(try WorkoutRoutine(id: id, name: name, exercises: exercises)) }
        }
    }
    @discardableResult
    func duplicateRoutine(_ routine: WorkoutRoutine) throws -> UUID {
        let exercises = try routine.exercises().map { item in
            SessionExercise(exercise: item.exercise, sets: item.sets.map { set in
                TrainingSet(reps: set.reps, weightKg: set.weightKg, completed: false)
            })
        }
        let id = UUID()
        try saveRoutine(id: id, name: routine.name + " Copy", exercises: exercises)
        return id
    }
    func saveSession(_ input: StrengthDraft) throws {
        let draft = try input.validated()
        let id = draft.id
        let existing = try context.fetch(FetchDescriptor<StrengthSession>(predicate: #Predicate { $0.id == id })).first
        if draft.status == .active {
            let active = try context.fetch(FetchDescriptor<StrengthSession>(predicate: #Predicate { $0.statusRaw == "active" }))
            guard !active.contains(where: { $0.id != id }) else { throw TrainingError.active }
        }
        // Finishing/editing must not accidentally recreate a deleted session.
        if draft.status != .active, existing == nil { throw TrainingError.missing }
        let data = try JSONEncoder().encode(draft)
        try commit {
            if let existing {
                existing.name = draft.name; existing.start = draft.start
                existing.statusRaw = draft.status.rawValue; existing.draftData = data
            } else { context.insert(try StrengthSession(draft)) }
        }
    }
    @discardableResult
    func start(routine: WorkoutRoutine? = nil) throws -> StrengthDraft {
        let draft = try routine.map { try StrengthDraft.fromRoutine(name: $0.name, exercises: $0.exercises()) } ?? StrengthDraft()
        try saveSession(draft)
        return draft
    }
    func saveCardio(_ input: CardioDraft) throws {
        let draft = try input.validated()
        let id = draft.id
        let data = try JSONEncoder().encode(draft)
        let existing = try context.fetch(FetchDescriptor<CardioSession>(predicate: #Predicate { $0.id == id })).first
        try commit {
            if let existing {
                existing.start = draft.start; existing.activityRaw = draft.activity.rawValue; existing.draftData = data
            } else { context.insert(try CardioSession(draft)) }
        }
    }
    func delete<T: PersistentModel>(_ item: T) throws { try commit {
            if let exercise = item as? ExerciseRecord, var snapshot = try? exercise.snapshot(), snapshot.catalog != nil {
                snapshot.catalog?.archived = true
                exercise.snapshotData = try JSONEncoder().encode(snapshot)
            } else { context.delete(item) }
        } }
}
