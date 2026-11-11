import XCTest
#if SWIFT_PACKAGE
@testable import PersonalFitnessCore
#else
@testable import PersonalFitness
#endif

final class WorkoutLogicTests: XCTestCase {
    func testOldExerciseSnapshotsDecodeWithoutNewOptionalMetadata() throws {
        let old = ExerciseSnapshot(name: "Existing custom exercise")
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(old)) as? [String: Any])
        for key in ["equipment", "movementType", "builtInKey"] { json.removeValue(forKey: key) }
        let decoded = try JSONDecoder().decode(ExerciseSnapshot.self, from: JSONSerialization.data(withJSONObject: json))
        XCTAssertEqual(decoded.id, old.id); XCTAssertEqual(decoded.name, old.name)
        XCTAssertNil(decoded.equipment); XCTAssertNil(decoded.builtInKey)
    }

    func testTrainingFrequencyUsesLocalDayRangesAndExcludesFutureLogs() {
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let today = calendar.startOfDay(for: now)
        let frequency = TrainingFrequency(dates: [today,
            calendar.date(byAdding: .day, value: -6, to: today)!,
            calendar.date(byAdding: .day, value: -7, to: today)!,
            calendar.date(byAdding: .day, value: 1, to: today)!], day: now, calendar: calendar)
        XCTAssertEqual(frequency.recent, 2); XCTAssertEqual(frequency.previous, 1)
    }

    private let past = Date(timeIntervalSince1970: 1_700_000_000)
    private var exercise: ExerciseSnapshot { ExerciseSnapshot(name: "Squat", muscleGroup: "Legs") }

    func testCompletionRequiresCompletedSetAndValidTimes() throws {
        var draft = StrengthDraft(start: past)
        XCTAssertThrowsError(try draft.finished(at: past.addingTimeInterval(600)))
        draft.exercises = [SessionExercise(exercise: exercise)]
        XCTAssertThrowsError(try draft.finished(at: past.addingTimeInterval(600)))
        draft.exercises[0].sets[0].completed = true
        let finished = try draft.finished(at: past.addingTimeInterval(600))
        XCTAssertEqual(finished.status, .completed)
        XCTAssertNil(finished.restEndsAt)
        XCTAssertEqual(finished.start, past)
        XCTAssertThrowsError(try draft.finished(at: past.addingTimeInterval(-1)))
    }

    func testSetValidationAndBodyweightExternalLoad() throws {
        try TrainingSet(reps: 10, weightKg: 0, completed: true).validate()
        try TrainingSet(reps: 0, weightKg: 0, completed: false).validate()
        for set in [TrainingSet(reps: -1), TrainingSet(reps: 0, completed: true), TrainingSet(weightKg: -1),
                    TrainingSet(weightKg: .nan), TrainingSet(weightKg: .infinity), TrainingSet(reps: 9999, weightKg: .greatestFiniteMagnitude)] {
            XCTAssertThrowsError(try set.validate())
        }
    }

    func testProgressionCountsOnlyCompletedSetsAndSessions() throws {
        let definition = exercise
        let sets = [TrainingSet(reps: 10, weightKg: 20, completed: true), TrainingSet(reps: 8, weightKg: 25, completed: true),
                    TrainingSet(reps: 99, weightKg: 100, completed: false)]
        let draft = StrengthDraft(start: past, exercises: [SessionExercise(exercise: definition, sets: sets)])
        let completed = try draft.finished(at: past.addingTimeInterval(100))
        var cancelled = completed; cancelled.id = UUID(); cancelled.status = .cancelled
        let history = WorkoutProgression.history(exerciseID: definition.id, sessions: [draft, cancelled, completed])
        XCTAssertEqual(history.count, 1)
        XCTAssertEqual(history[0].externalVolumeKg, 400)
        XCTAssertEqual(history[0].totalReps, 18)
        XCTAssertEqual(history[0].bestWeightKg, 25)
        XCTAssertTrue(WorkoutProgression.history(exerciseID: UUID(), sessions: [completed]).isEmpty)
        XCTAssertTrue(WorkoutProgression.history(exerciseID: definition.id, sessions: [completed], before: past).isEmpty)
    }

    func testRoutineStartRegeneratesSessionAndSetIDsWithoutCompletion() throws {
        let original = SessionExercise(exercise: exercise, sets: [TrainingSet(reps: 12, weightKg: 30, completed: true)])
        let first = StrengthDraft.fromRoutine(name: "Routine", exercises: [original], now: past)
        let second = StrengthDraft.fromRoutine(name: "Routine", exercises: [original], now: past)
        XCTAssertNotEqual(first.id, second.id)
        XCTAssertNotEqual(first.exercises[0].id, original.id)
        XCTAssertNotEqual(first.exercises[0].sets[0].id, original.sets[0].id)
        XCTAssertEqual(first.exercises[0].exercise.id, original.exercise.id)
        XCTAssertEqual(first.exercises[0].sets[0].reps, 12)
        XCTAssertFalse(first.exercises[0].sets[0].completed)
        var duplicate = first
        duplicate.exercises.append(first.exercises[0])
        XCTAssertThrowsError(try duplicate.validated())
    }

    func testRestTimerUsesDeadlineAcrossRelaunchAndExpiry() {
        XCTAssertEqual(WorkoutProgression.restRemaining(until: nil, now: past), 0)
        XCTAssertEqual(WorkoutProgression.restRemaining(until: past.addingTimeInterval(60), now: past.addingTimeInterval(20)), 40)
        XCTAssertEqual(WorkoutProgression.restRemaining(until: past, now: past.addingTimeInterval(1)), 0)
    }

    func testCardioOptionalMetricsAndValidation() throws {
        var cardio = CardioDraft(activity: .stairs, start: past, durationSeconds: 600, resistance: 5, floors: 30, reportedCalories: 100)
        XCTAssertEqual(try cardio.validated().end, past.addingTimeInterval(600))
        XCTAssertNil(cardio.distanceKm)
        cardio.durationSeconds = 0; XCTAssertThrowsError(try cardio.validated())
        cardio.durationSeconds = 600; cardio.reportedCalories = -1; XCTAssertThrowsError(try cardio.validated())
        cardio.reportedCalories = nil; cardio.distanceKm = .infinity; XCTAssertThrowsError(try cardio.validated())
        cardio.distanceKm = nil; cardio.inclinePercent = 10; XCTAssertThrowsError(try cardio.validated())
        cardio.inclinePercent = nil; cardio.start = .now; XCTAssertThrowsError(try cardio.validated())
    }

    func testReconciliationDeduplicatesOnlyExactIDsAndKeepsAmbiguousRecords() {
        let id = UUID()
        let record = WorkoutRecordSummary(id: id, activity: .stairs, start: past, end: past.addingTimeInterval(600))
        let similar = WorkoutRecordSummary(id: UUID(), activity: .stairs, start: past.addingTimeInterval(60), end: past.addingTimeInterval(660))
        let different = WorkoutRecordSummary(id: UUID(), activity: .running, start: past, end: past.addingTimeInterval(600))
        let distant = WorkoutRecordSummary(id: UUID(), activity: .stairs, start: past.addingTimeInterval(1000), end: past.addingTimeInterval(1600))
        XCTAssertEqual(WorkoutReconciliation.unique([record, record, similar]).count, 2)
        XCTAssertEqual(WorkoutReconciliation.possibleMatches(for: record, in: [record, similar, different, distant]), [similar.id])
        // Reconciliation has no calorie input or output: manual machine values cannot enter expenditure.
    }

    func testSnapshotsRoundTripAndHistoricalLocalDay() throws {
        let draft = StrengthDraft(start: past, exercises: [SessionExercise(exercise: exercise)])
        let copy = try JSONDecoder().decode(StrengthDraft.self, from: JSONEncoder().encode(draft))
        XCTAssertEqual(copy, draft)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/New_York")!
        let day = calendar.date(from: DateComponents(year: 2026, month: 11, day: 1))!
        let window = try LocalDayWindow.interval(for: day, calendar: calendar)
        XCTAssertEqual(window.duration, 25 * 3600)
        let session = StrengthDraft(start: day.addingTimeInterval(3600))
        XCTAssertTrue(calendar.isDate(session.start, inSameDayAs: day))
    }
    func testDisjointShortSessionsAndUnknownActivitiesAreNotPossibleMatches() {
        let record = WorkoutRecordSummary(id: UUID(), activity: .stairs, start: past, end: past.addingTimeInterval(60))
        let next = WorkoutRecordSummary(id: UUID(), activity: .stairs, start: past.addingTimeInterval(120), end: past.addingTimeInterval(180))
        let touching = WorkoutRecordSummary(id: UUID(), activity: .stairs, start: record.end, end: past.addingTimeInterval(120))
        XCTAssertTrue(WorkoutReconciliation.possibleMatches(for: record, in: [next, touching]).isEmpty)
        let unknown = WorkoutRecordSummary(id: UUID(), activity: .other, start: past, end: record.end)
        let other = WorkoutRecordSummary(id: UUID(), activity: .other, start: past, end: record.end)
        XCTAssertTrue(WorkoutReconciliation.possibleMatches(for: unknown, in: [other]).isEmpty)
    }

}
