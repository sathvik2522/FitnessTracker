import Foundation
import SwiftData

@Model
final class ExerciseRecord {
    @Attribute(.unique) var id: UUID
    var name: String
    var snapshotData: Data
    init(_ exercise: ExerciseSnapshot) throws {
        let exercise = try exercise.validated()
        id = exercise.id
        name = exercise.name
        snapshotData = try JSONEncoder().encode(exercise)
    }
    func snapshot() throws -> ExerciseSnapshot { try JSONDecoder().decode(ExerciseSnapshot.self, from: snapshotData).validated() }
}

@Model
final class WorkoutRoutine {
    @Attribute(.unique) var id: UUID
    var name: String
    var exercisesData: Data
    init(id: UUID, name: String, exercises: [SessionExercise]) throws {
        self.id = id
        self.name = name
        exercisesData = try JSONEncoder().encode(exercises)
    }
    func exercises() throws -> [SessionExercise] { try JSONDecoder().decode([SessionExercise].self, from: exercisesData) }
}

/// Indexed columns support queries; draftData is the authoritative session
/// snapshot, including exercise names, set IDs, load and completion status.
/// Changes to its Codable format need compatibility tests as well as SwiftData
/// migration checks, because lightweight migration cannot rewrite JSON blobs.
@Model
final class StrengthSession {
    @Attribute(.unique) var id: UUID
    var name: String
    var start: Date
    var statusRaw: String
    var draftData: Data
    init(_ draft: StrengthDraft) throws {
        id = draft.id
        name = draft.name
        start = draft.start
        statusRaw = draft.status.rawValue
        draftData = try JSONEncoder().encode(draft)
    }
    func draft() throws -> StrengthDraft { try JSONDecoder().decode(StrengthDraft.self, from: draftData) }
}

@Model
final class CardioSession {
    @Attribute(.unique) var id: UUID
    var start: Date
    var activityRaw: String
    var draftData: Data
    init(_ draft: CardioDraft) throws {
        id = draft.id
        start = draft.start
        activityRaw = draft.activity.rawValue
        draftData = try JSONEncoder().encode(draft)
    }
    func draft() throws -> CardioDraft { try JSONDecoder().decode(CardioDraft.self, from: draftData) }
}
