import SwiftUI
import SwiftData

struct WorkoutDaySummary: View {
    let health: HealthReading<[HealthWorkout]>
    @Query private var strength: [StrengthSession]
    @Query private var cardio: [CardioSession]
    init(day: Date, calendar: Calendar, health: HealthReading<[HealthWorkout]>) {
        self.health = health
        let interval = calendar.dateInterval(of: .day, for: day)!
        let start = interval.start, end = interval.end
        _strength = Query(filter: #Predicate<StrengthSession> { $0.start >= start && $0.start < end }, sort: \StrengthSession.start)
        _cardio = Query(filter: #Predicate<CardioSession> { $0.start >= start && $0.start < end }, sort: \CardioSession.start)
    }
    private var manualRecords: [WorkoutRecordSummary] {
        strength.compactMap { session in
            guard let draft = try? session.draft(), draft.status == .completed, let end = draft.end else { return nil }
            return WorkoutRecordSummary(id: draft.id, activity: .strength, start: draft.start, end: end)
        } + cardio.compactMap { session in
            guard let draft = try? session.draft() else { return nil }
            return WorkoutRecordSummary(id: draft.id, activity: draft.activity, start: draft.start, end: draft.end)
        }
    }
    private var imported: [HealthWorkout] {
        HealthWorkout.uniqueRecords(health.value ?? [])
    }
    private var importedRecords: [WorkoutRecordSummary] {
        imported.map(\.recordSummary)
    }
    var body: some View {
        SectionHeading(title: "Manual workout logs", subtitle: "Assigned to the local day they started")
        if strength.isEmpty && cardio.isEmpty {
            EmptyState(title: "No manual workout logs", message: "Use Workouts to start strength training or log cardio. Manual calories are never added to active energy.", symbol: "dumbbell")
        }
        ForEach(strength) { session in
            EmptyState(title: session.name,
                       message: "\(session.statusRaw.capitalized) · \(session.start.formatted(date: .omitted, time: .shortened))" + matchNote(session.id), symbol: "dumbbell")
        }
        ForEach(cardio) { session in
            VStack(alignment: .leading, spacing: 8) {
                Text(session.activityRaw).font(.headline)
                if let draft = try? session.draft() { CardioSummary(draft: draft) }
                else { Text("Saved details unavailable") }
                if !matchNote(session.id).isEmpty { Text(matchNote(session.id)).font(.footnote) }
            }.padding().background(.background, in: RoundedRectangle(cornerRadius: 16))
        }
        SectionHeading(title: "Apple Health workout records", subtitle: "Read-only; separate from manual logs")
        switch health {
        case .value:
            ForEach(imported) { workout in
                let record = WorkoutRecordSummary(id: workout.id, activity: workout.activity, start: workout.start, end: workout.end)
                let manualMatch = !WorkoutReconciliation.possibleMatches(for: record, in: manualRecords).isEmpty
                let similar = !WorkoutReconciliation.possibleMatches(for: record, in: importedRecords).isEmpty
                EmptyState(title: workout.title,
                           message: "Started \(workout.start.formatted(date: .abbreviated, time: .shortened)) · \(workout.durationSeconds.map { NutritionNumber.text($0 / 60) + " min" } ?? "Duration unavailable")" +
                            (manualMatch ? " · Possible manual-log match" : "") + (similar ? " · Similar Health record; kept separate" : ""), symbol: "heart")
            }
        case .unavailable:
            EmptyState(title: "No readable workout records", message: "There may be no records for this day, or read access may be off. This does not confirm that you did not exercise.", symbol: "dumbbell")
        case .failed(let issue): ErrorMessage(title: "Workout query failed", message: issue.rawValue)
        }
        Text("Possible matches overlap, share a known activity, and have start/end times within five minutes. They are hints, not confirmed duplicates. Distinct Health IDs and all manual logs remain separate; no combined workout count or calorie sum is produced.")
            .font(.footnote).foregroundStyle(.secondary)
    }
    private func matchNote(_ id: UUID) -> String {
        guard let record = manualRecords.first(where: { $0.id == id }),
              !WorkoutReconciliation.possibleMatches(for: record, in: importedRecords).isEmpty else { return "" }
        return " · Possible Apple Health match"
    }
}
