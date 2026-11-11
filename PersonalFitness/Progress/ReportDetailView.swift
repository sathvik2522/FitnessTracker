import SwiftUI

struct ReportDetailView: View {
    let day: ReportDay
    let report: ProgressReport
    private var health: HealthDaySnapshot? { report.healthDays.first { $0.window == day.window } }
    var body: some View {
        List {
            Section("Calculation window") {
                Text(day.assessment.scopeTitle).font(.headline)
                Text("From \(day.window.start.formatted(date: .abbreviated, time: .standard)) through \(day.window.end.formatted(date: .abbreviated, time: .standard)) (exclusive)")
                Text(day.window.timeZoneIdentifier)
                if day.window.isPartial { Text("Today's measurements are incomplete and can change after recording or sync.") }
            }
            Section("Underlying energy values · kcal") {
                LabeledContent("Logged intake", value: kcal(day.consumed))
                LabeledContent("Food portions", value: String(day.food.count))
                LabeledContent("Resting energy", value: reading(health?.resting))
                LabeledContent("Active energy", value: reading(health?.active))
                LabeledContent("Estimated expenditure", value: kcal(day.assessment.balance.expenditure))
                LabeledContent("Estimated balance", value: kcal(day.assessment.balance.net))
                Text("Expenditure = resting + active. Balance = logged intake − expenditure. Negative is an estimated deficit; positive is an estimated surplus. Workouts and machine calories are not added again.").font(.footnote).foregroundStyle(.secondary)
            }
            Section("Availability and accuracy") {
                ForEach(day.assessment.balanceReasons, id: \.rawValue) { reason in Text(reason.rawValue) }
                Text("These estimates do not establish exact fat gain or loss. Closing a calendar day does not prove complete food or Health coverage.").font(.footnote)
            }
            Section("Macros · grams") {
                LabeledContent("Protein", value: number(day.protein))
                LabeledContent("Carbohydrates", value: number(day.carbohydrates))
                LabeledContent("Fat", value: number(day.fat))
            }
            Section("Persisted food portions") {
                if day.food.isEmpty { Text("No food is recorded. Intake is unknown, not confirmed zero.") }
                ForEach(day.food) { entry in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(entry.name).font(.headline)
                        let nutrients = FoodNutrients(calories: entry.portion.calories, protein: entry.portion.protein,
                            carbohydrates: entry.portion.carbohydrates, fat: entry.portion.fat)
                        if (try? nutrients.validated()) != nil { NutritionLine(nutrients: nutrients) }
                        else { Text("Invalid saved nutrition values. Review this entry in Food.").foregroundStyle(.red) }
                        Text(entry.date.formatted(date: .omitted, time: .shortened)).font(.caption)
                    }
                }
            }
            Section("Manual workouts · no extra energy input") {
                let sessions = report.local.strength.filter { report.calendar.isDate($0.start, inSameDayAs: day.id) }
                let cardio = report.local.cardio.filter { report.calendar.isDate($0.start, inSameDayAs: day.id) }
                if sessions.isEmpty && cardio.isEmpty { Text("No manual sessions recorded.") }
                ForEach(sessions) { session in Text("\(session.name) · \(session.status.rawValue.capitalized)") }
                ForEach(cardio) { session in
                    VStack(alignment: .leading, spacing: 6) { Text(session.activity.rawValue).font(.headline); CardioSummary(draft: session) }
                }
            }
            Section("Apple Health workout records · read-only") {
                if let workouts = health?.workouts.value {
                    ForEach(HealthWorkout.uniqueRecords(workouts).filter { $0.start >= day.window.start && $0.start < day.window.end }) { workout in
                        Text("\(workout.title) · \(workout.start.formatted(date: .omitted, time: .shortened))")
                    }
                } else { Text(health?.workouts.issue?.rawValue ?? "No readable records; no samples and hidden data cannot be distinguished.") }
            }
        }.fitnessScreen().navigationBarTitleDisplayMode(.inline).navigationTitle(day.id.formatted(date: .abbreviated, time: .omitted))
            .accessibilityIdentifier("progress.dailyDetail")
    }
    private func reading(_ value: HealthReading<Double>?) -> String {
        switch value ?? .unavailable {
        case .value(let value): return kcal(value)
        case .unavailable: return "Unavailable"
        case .failed: return "Query failed"
        }
    }
    private func kcal(_ value: Double?) -> String { value.map { EnergyDisplay.kilocalories($0) } ?? "Unavailable" }
    private func number(_ value: Double?) -> String { value.map { $0.formatted(.number.precision(.fractionLength(0...1))) } ?? "Unavailable" }
}
