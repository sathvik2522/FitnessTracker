import SwiftUI
import Charts

struct TrainingReportView: View {
    let report: ProgressReport
    private var completed: [StrengthDraft] { report.local.strength.filter { $0.status == .completed } }
    private var exercises: [ExerciseSnapshot] {
        var seen = Set<UUID>()
        return completed.sorted { $0.start > $1.start }.flatMap(\.exercises).filter { $0.sets.contains(where: \.completed) }.map(\.exercise)
            .filter { seen.insert($0.id).inserted }.sorted { $0.name < $1.name }
    }
    private var manual: [WorkoutRecordSummary] {
        completed.compactMap { session in session.end.map { WorkoutRecordSummary(id: session.id, activity: .strength, start: session.start, end: $0) } }
        + report.local.cardio.map { WorkoutRecordSummary(id: $0.id, activity: $0.activity, start: $0.start, end: $0.end) }
    }
    var body: some View {
        List {
            Section("Manual workout frequency") {
                Text("\(completed.count) completed strength sessions · \(report.local.cardio.count) cardio sessions").font(.headline)
                Chart(report.days) { day in
                    BarMark(x: .value("Day", day.id, unit: .day), y: .value("Manual strength", completed.filter { report.calendar.isDate($0.start, inSameDayAs: day.id) }.count))
                        .foregroundStyle(by: .value("Type", "Strength"))
                    BarMark(x: .value("Day", day.id, unit: .day), y: .value("Manual cardio", report.local.cardio.filter { report.calendar.isDate($0.start, inSameDayAs: day.id) }.count))
                        .foregroundStyle(by: .value("Type", "Cardio"))
                }.frame(height: 220).accessibilityLabel("Daily manual completed workout count")
                Text("Counts are manual logs only. Zero means no completed manual records, not that you did not exercise. Active and cancelled sessions are excluded from frequency and progression.").font(.footnote).foregroundStyle(.secondary)
            }
            Section("Exercise progression in this range") {
                if exercises.isEmpty { Text("No completed strength sets in this range.").foregroundStyle(.secondary) }
                ForEach(exercises) { exercise in
                    NavigationLink(exercise.name) {
                        ExerciseRangeReport(exercise: exercise, history: WorkoutProgression.history(exerciseID: exercise.id, sessions: completed))
                    }
                }
            }
            Section("Manual strength history · all states") {
                if report.local.strength.isEmpty { Text("No strength sessions recorded.") }
                ForEach(report.local.strength.sorted { $0.start > $1.start }) { session in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(session.name).font(.headline)
                        Text("\(session.status.rawValue.capitalized) · \(session.start.formatted(date: .abbreviated, time: .shortened))")
                        Text("\(session.exercises.count) exercises · \(session.exercises.flatMap(\.sets).filter(\.completed).count) checked sets").foregroundStyle(.secondary)
                    }
                }
            }
            Section("Manual cardio & stair climber history") {
                if report.local.cardio.isEmpty { Text("No cardio sessions recorded.") }
                ForEach(report.local.cardio.sorted { $0.start > $1.start }) { session in
                    VStack(alignment: .leading, spacing: 6) { Text(session.activity.rawValue).font(.headline); CardioSummary(draft: session) }
                }
            }
            Section("Apple Health records · separate count") {
                Text("\(report.healthWorkouts.count) readable unique records on \(report.readableWorkoutDays) of \(report.days.count) queried days.")
                Text("Other days may have no samples or hidden/failed reads. These are not added to manual workout counts.").font(.footnote).foregroundStyle(.secondary)
                ForEach(report.healthWorkouts.sorted { $0.start > $1.start }) { workout in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(workout.title).font(.headline)
                        Text(workout.start.formatted(date: .abbreviated, time: .shortened))
                        if !WorkoutReconciliation.possibleMatches(for: workout.recordSummary, in: manual).isEmpty {
                            Text("Possible manual-log match · records kept separate").font(.caption)
                        }
                    }
                }
                if report.healthDays.contains(where: { $0.workouts.issue != nil }) { Text("Some workout queries failed. Refresh to retry.").foregroundStyle(.red) }
            }
        }.fitnessScreen().navigationBarTitleDisplayMode(.inline).navigationTitle("Training report")
    }
}

private struct ExerciseRangeReport: View {
    let exercise: ExerciseSnapshot
    let history: [ExercisePerformance]
    var body: some View {
        List {
            Section("Completed-session charts") { ExerciseProgressCharts(history: history) }
            Section("Recorded performance") {
                ForEach(history) { point in
                    VStack(alignment: .leading, spacing: 8) {
                        Text(point.date.formatted(date: .abbreviated, time: .shortened)).font(.headline)
                        Text("\(point.totalReps) reps · best external load \(point.bestWeightKg.formatted()) kg")
                        Text("External volume: \(point.externalVolumeKg.formatted()) kg·reps")
                        Text(point.sets.map { "\($0.reps) × \(NutritionNumber.text($0.weightKg)) kg" }.joined(separator: " · "))
                    }
                }
            }
            Text("External load only, including for bodyweight exercises. Charts connect recorded completed sessions; no performance is inferred for other days.").font(.footnote).foregroundStyle(.secondary)
        }.fitnessScreen().navigationBarTitleDisplayMode(.inline).navigationTitle(exercise.name)
    }
}
