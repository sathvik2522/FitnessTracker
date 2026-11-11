import SwiftUI
import SwiftData

struct CardioEditor: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var id: UUID
    private let stairsOnly: Bool
    @State private var activity: WorkoutActivity
    @State private var start: Date
    @State private var duration: String
    @State private var distance: String
    @State private var incline: String
    @State private var resistance: String
    @State private var floors: String
    @State private var calories: String
    @State private var source: CalorieEstimateSource
    @State private var notes: String
    @State private var sessionRPE: Double?
    @State private var error: String?
    @State private var original: String?
    @State private var cancelling = false
    private var fingerprint: String { [activity.rawValue, String(start.timeIntervalSince1970), duration, distance, incline, resistance, floors, calories, source.rawValue, notes, sessionRPE.map(NutritionNumber.text) ?? ""].joined(separator: "|") }
    private var dirty: Bool { original != nil && original != fingerprint }

    init(draft: CardioDraft? = nil, stairsOnly: Bool = false) {
        let draft = draft ?? CardioDraft(activity: stairsOnly ? .stairs : .running)
        _id = State(initialValue: draft.id)
        self.stairsOnly = stairsOnly || draft.activity == .stairs
        _activity = State(initialValue: draft.activity)
        _start = State(initialValue: draft.start)
        _duration = State(initialValue: NutritionNumber.text(draft.durationSeconds / 60))
        _distance = State(initialValue: draft.distanceKm.map(NutritionNumber.text) ?? "")
        _incline = State(initialValue: draft.inclinePercent.map(NutritionNumber.text) ?? "")
        _resistance = State(initialValue: draft.resistance.map(NutritionNumber.text) ?? "")
        _floors = State(initialValue: draft.floors.map(NutritionNumber.text) ?? "")
        _calories = State(initialValue: draft.reportedCalories.map(NutritionNumber.text) ?? "")
        _source = State(initialValue: draft.calorieSource)
        _notes = State(initialValue: draft.notes)
        _sessionRPE = State(initialValue: draft.sessionRPE)
    }
    var body: some View {
        NavigationStack {
            Form {
                Section("Manual session") {
                    if !stairsOnly {
                        Picker("Activity", selection: $activity) { ForEach(WorkoutActivity.cardio) { Text($0.rawValue).tag($0) } }
                    } else { Text("Stair climber") }
                    DatePicker("Started at", selection: $start, in: ...Date.now)
                    NutritionNumericField(title: "Duration (minutes)", text: $duration)
                    NutritionNumericField(title: "Distance (km)", text: $distance, required: false)
                    if activity.supportsIncline { NutritionNumericField(title: "Incline (%)", text: $incline, required: false) }
                    if activity.supportsResistance { NutritionNumericField(title: activity == .stairs ? "Level / resistance" : "Resistance", text: $resistance, required: false) }
                    if activity == .stairs { NutritionNumericField(title: "Floors climbed", text: $floors, required: false) }
                }
                Section("Optional reported calories") {
                    NutritionNumericField(title: "Reported calories (kcal)", text: $calories, required: false)
                    Picker("Estimate source", selection: $source) { ForEach(CalorieEstimateSource.allCases) { Text($0.rawValue).tag($0) } }
                    Text("User-entered estimates only. These calories never increase dashboard active energy or expenditure and are not written to Apple Health.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                Section("Notes") { TextField("Notes (optional)", text: $notes, axis: .vertical) }
                Section("Optional session effort") { SessionRPEField(value: $sessionRPE) }
                Text("Log completed cardio. Start plus duration must not be in the future. Blank optional fields mean unavailable, not zero.").font(.footnote).foregroundStyle(.secondary)
            }
            .scrollDismissesKeyboard(.interactively)
            .fitnessScreen().navigationBarTitleDisplayMode(.inline).navigationTitle(stairsOnly ? "Stair climber" : "Log cardio")
            .workoutKeyboardToolbar()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { if dirty { cancelling = true } else { dismiss() } } }
                ToolbarItem(placement: .confirmationAction) { Button("Save") { save() } }
            }
            .onAppear { if original == nil { original = fingerprint } }
            .confirmDiscardChanges(dirty: dirty, requested: $cancelling) { dismiss() }
            .nutritionError($error)
        }
    }
    private func optional(_ text: String) throws -> Double? {
        text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : try NutritionNumber.parse(text)
    }
    private func save() {
        do {
            let draft = try CardioDraft(id: id, activity: activity, start: start,
                durationSeconds: NutritionNumber.parse(duration) * 60, distanceKm: optional(distance),
                inclinePercent: activity.supportsIncline ? optional(incline) : nil,
                resistance: activity.supportsResistance ? optional(resistance) : nil,
                floors: activity == .stairs ? optional(floors) : nil,
                reportedCalories: optional(calories), calorieSource: source, notes: notes, sessionRPE: sessionRPE)
            try WorkoutStore(context: context).saveCardio(draft)
            dismiss()
        } catch { self.error = error.localizedDescription }
    }
}
