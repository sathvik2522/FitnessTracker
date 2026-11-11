import Foundation

enum TrainingError: String, LocalizedError {
    case rpe = "Session RPE must be a finite number from 0 to 10, or left blank."
    case name = "Enter a name."
    case sets = "Reps must be between 0 and 9999, and completed sets need at least one rep. Weight must be finite and nonnegative."
    case date = "Check the workout dates. End must follow start and cannot be in the future."
    case exercises = "Add at least one exercise and complete at least one set before finishing."
    case active = "Resume or cancel the active workout before starting another."
    case missing = "This workout is no longer available."
    case cardio = "Duration must be positive. Optional metrics must be finite and nonnegative."
    case duplicate = "Exercise and set identifiers must be unique within a session."
    var errorDescription: String? { rawValue }
}

enum WorkoutActivity: String, Codable, CaseIterable, Identifiable, Sendable {
    case strength = "Strength training", running = "Running", walking = "Walking", cycling = "Cycling"
    case stairs = "Stair climbing", elliptical = "Elliptical", swimming = "Swimming", other = "Other cardio"
    var id: String { rawValue }
    static var cardio: [Self] { allCases.filter { $0 != .strength } }
    var supportsIncline: Bool { self == .walking || self == .running }
    var supportsResistance: Bool { self == .stairs || self == .cycling || self == .elliptical || self == .other }
}

enum SessionEffort {
    static func isValid(_ rpe: Double?) -> Bool { rpe.map { $0.isFinite && (0...10).contains($0) } ?? true }
}

enum SessionStatus: String, Codable { case active, completed, cancelled }

struct ExerciseSnapshot: Codable, Equatable, Identifiable {
    var id: UUID = UUID()
    var name: String
    var notes: String = ""
    var category: String = ""
    var muscleGroup: String = ""
    var bodyweight: Bool = false
    // Optional additions decode older snapshots without requiring a store migration.
    var equipment: String? = nil
    var movementType: String? = nil
    var builtInKey: String? = nil
    var aliases: [String]? = nil
    var primaryMuscles: [String]? = nil
    var secondaryMuscles: [String]? = nil
    var instructions: [String]? = nil
    var catalog: CatalogOrigin? = nil
    func validated() throws -> Self {
        var result = self
        result.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !result.name.isEmpty else { throw TrainingError.name }
        return result
    }
}

struct TrainingSet: Codable, Equatable, Identifiable {
    var id = UUID()
    var reps: Int = 8
    /// External load only, including for bodyweight exercises. Kilograms throughout.
    var weightKg: Double = 0
    var completed = false
    func validate() throws {
        guard (0...9999).contains(reps), (!completed || reps > 0), weightKg.isFinite, weightKg >= 0, (weightKg * Double(reps)).isFinite else {
            throw TrainingError.sets
        }
    }
}

struct SessionExercise: Codable, Equatable, Identifiable {
    var id = UUID()
    var exercise: ExerciseSnapshot
    var sets: [TrainingSet] = [TrainingSet()]
}

struct StrengthDraft: Codable, Equatable, Identifiable {
    var id = UUID()
    var name = "Strength workout"
    var start = Date.now
    var end: Date?
    var status: SessionStatus = .active
    var exercises: [SessionExercise] = []
    var restEndsAt: Date?
    var sessionRPE: Double? = nil

    func validated(now: Date = .now) throws -> Self {
        guard SessionEffort.isValid(sessionRPE) else { throw TrainingError.rpe }
        var draft = self
        draft.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !draft.name.isEmpty else { throw TrainingError.name }
        guard start.timeIntervalSince1970.isFinite, start <= now else { throw TrainingError.date }
        if status == .active {
            guard end == nil else { throw TrainingError.date }
        } else {
            guard let end, end.timeIntervalSince1970.isFinite, end >= start, end <= now else { throw TrainingError.date }
        }
        if let restEndsAt, !restEndsAt.timeIntervalSince1970.isFinite { throw TrainingError.date }
        guard Set(exercises.map(\.id)).count == exercises.count else { throw TrainingError.duplicate }
        let sets = exercises.flatMap(\.sets)
        guard Set(sets.map(\.id)).count == sets.count else { throw TrainingError.duplicate }
        guard sets.reduce(0.0, { $0 + Double($1.reps) * $1.weightKg }).isFinite else { throw TrainingError.sets }
        for item in exercises {
            _ = try item.exercise.validated()
            for set in item.sets { try set.validate() }
        }
        if status == .completed {
            guard !exercises.isEmpty, sets.contains(where: \.completed) else { throw TrainingError.exercises }
        }
        return draft
    }

    func finished(at date: Date = .now) throws -> Self {
        var copy = self
        copy.end = date
        copy.status = .completed
        copy.restEndsAt = nil
        return try copy.validated(now: date)
    }

    static func fromRoutine(name: String, exercises: [SessionExercise], now: Date = .now) -> Self {
        Self(name: name, start: now, exercises: exercises.map { item in
            SessionExercise(exercise: item.exercise, sets: item.sets.map {
                TrainingSet(reps: $0.reps, weightKg: $0.weightKg, completed: false)
            })
        })
    }
}

struct ExercisePerformance: Identifiable, Equatable {
    let id: UUID
    let date: Date
    let sets: [TrainingSet]
    var totalReps: Int { sets.reduce(0) { $0 + $1.reps } }
    var bestWeightKg: Double { sets.map(\.weightKg).max() ?? 0 }
    var externalVolumeKg: Double { sets.reduce(0) { $0 + Double($1.reps) * $1.weightKg } }
}

enum WorkoutProgression {
    static func history(exerciseID: UUID, sessions: [StrengthDraft], before: Date = .distantFuture) -> [ExercisePerformance] {
        sessions.filter { $0.status == .completed && $0.start < before }.compactMap { session in
            let sets = session.exercises.filter { $0.exercise.id == exerciseID }.flatMap(\.sets).filter(\.completed)
            guard !sets.isEmpty else { return nil }
            return ExercisePerformance(id: session.id, date: session.start, sets: sets)
        }.sorted { $0.date > $1.date }
    }
    static func restRemaining(until deadline: Date?, now: Date) -> Int {
        guard let deadline else { return 0 }
        let seconds = deadline.timeIntervalSince(now)
        guard seconds.isFinite else { return 0 }
        return Int(min(Double(Int.max / 2), max(0, ceil(seconds))))
    }
}

enum CalorieEstimateSource: String, Codable, CaseIterable, Identifiable {
    case machine = "Machine estimate", user = "User estimate"
    var id: String { rawValue }
}

struct CardioDraft: Codable, Equatable, Identifiable {
    var id = UUID()
    var activity: WorkoutActivity = .running
    var start = Date.now.addingTimeInterval(-1800)
    var durationSeconds: Double = 1800
    var distanceKm: Double?
    var inclinePercent: Double?
    var resistance: Double?
    var floors: Double?
    var reportedCalories: Double?
    var calorieSource: CalorieEstimateSource = .machine
    var notes = ""
    var sessionRPE: Double? = nil
    var end: Date { start.addingTimeInterval(durationSeconds) }
    func validated(now: Date = .now) throws -> Self {
        guard SessionEffort.isValid(sessionRPE) else { throw TrainingError.rpe }
        guard activity != .strength, durationSeconds.isFinite, durationSeconds > 0,
              [distanceKm, inclinePercent, resistance, floors, reportedCalories].compactMap({ $0 })
                .allSatisfy({ $0.isFinite && $0 >= 0 }) else { throw TrainingError.cardio }
        guard (inclinePercent == nil || activity.supportsIncline),
              (resistance == nil || activity.supportsResistance),
              (floors == nil || activity == .stairs) else { throw TrainingError.cardio }
        guard start.timeIntervalSince1970.isFinite, end.timeIntervalSince1970.isFinite,
              start <= now, end <= now, end > start else { throw TrainingError.date }
        return self
    }
}

/// Display metadata only: never an energy input and never a persisted import.
struct WorkoutRecordSummary: Identifiable, Equatable {
    let id: UUID
    let activity: WorkoutActivity
    let start: Date
    let end: Date
}

enum WorkoutReconciliation {
    /// Exact UUID repetitions are the same Health record. Distinct UUIDs are preserved.
    static func unique(_ records: [WorkoutRecordSummary]) -> [WorkoutRecordSummary] {
        var seen = Set<UUID>()
        return records.filter { seen.insert($0.id).inserted }
    }
    static func possibleMatches(for record: WorkoutRecordSummary, in candidates: [WorkoutRecordSummary]) -> [UUID] {
        candidates.filter {
            record.activity != .other && $0.id != record.id && $0.activity == record.activity &&
            record.end > record.start && $0.end > $0.start &&
            max(record.start, $0.start) < min(record.end, $0.end) &&
            abs($0.start.timeIntervalSince(record.start)) <= 300 && abs($0.end.timeIntervalSince(record.end)) <= 300
        }.map(\.id)
    }
}

/// Explicitly installed starter definitions, persisted like custom exercises.
/// Stable IDs make repeated installation idempotent and preserve edited records.
enum StarterExercises {
    static var all: [ExerciseSnapshot] {
        let names = ["Barbell squat", "Bench press", "Deadlift", "Overhead press", "Dumbbell row", "Lat pulldown", "Pull-up", "Push-up", "Lunge", "Crunch"]
        let muscles = ["Legs", "Chest", "Posterior chain", "Shoulders", "Back", "Back", "Back", "Chest", "Legs", "Core"]
        return names.enumerated().map { index, name in
            ExerciseSnapshot(id: UUID(uuidString: String(format: "B38D5260-0000-4000-8000-%012d", index + 1))!,
                name: name, category: "Strength", muscleGroup: muscles[index], bodyweight: index >= 6,
                equipment: index < 4 ? "Barbell" : index == 4 ? "Dumbbell" : index == 5 ? "Cable" : index == 6 ? "Pull-up bar" : "Bodyweight",
                movementType: "Repetitions", builtInKey: "starter.\(index + 1)")
        }
    }
}

struct TrainingFrequency {
    let recent: Int
    let previous: Int
    init(dates: [Date], day: Date, calendar: Calendar) {
        let end = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: day))!
        let start = calendar.date(byAdding: .day, value: -7, to: end)!
        let prior = calendar.date(byAdding: .day, value: -7, to: start)!
        recent = dates.filter { $0 >= start && $0 < end }.count
        previous = dates.filter { $0 >= prior && $0 < start }.count
    }
}
