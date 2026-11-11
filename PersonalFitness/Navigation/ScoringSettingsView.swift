import SwiftUI

struct ScoringSettingsView: View {
    @Environment(ScoringPreferences.self) private var preferences
    @Environment(\.dismiss) private var dismiss
    @State private var personalize = true
    @State private var fields: [String: String] = [:]
    @State private var useProfile = false
    @State private var parameter = ""
    @State private var original: String?
    @State private var cancelling = false
    @State private var error: String?
    private var fingerprint: String { "\(personalize)|\(useProfile)|\(parameter)|" + fields.keys.sorted().map { $0 + ":" + (fields[$0] ?? "") }.joined(separator: "|") }
    private var dirty: Bool { original != nil && original != fingerprint }
    private func input(_ name: String, optional: Bool = false) -> some View {
        NutritionNumericField(title: name, text: Binding(get: { fields[name] ?? "" }, set: { fields[name] = $0 }), required: !optional)
    }
    var body: some View {
        Form {
            Section("Activity-load normalization") {
                Text("These targets define a display scale, not recommended exercise levels or injury-risk thresholds. Load modes are alternatives and are never added together.").font(.footnote)
                Toggle("Personalize from recent recorded load", isOn: $personalize)
                ForEach(["Target scale", "Session-RPE target", "Workout minutes target", "Active kcal target", "Step-count target"], id: \.self) { input($0) }
                Text("Personalization uses the median positive daily load from at least 7 distinct eligible days in the prior 28 days, in the same mode. Otherwise the inspected targets above are provisional. Scores saturate at 100.").font(.footnote)
            }
            Section("Recovery components") {
                ForEach(["Sleep target (minutes)", "Sleep weight", "HRV weight", "Resting HR weight", "Training-load weight", "HRV mapping slope", "Resting HR penalty per bpm"], id: \.self) { input($0) }
                Text("The initial 40/30/20/10 weights are product heuristics, not clinical constants. Only eligible signals with positive weights are included; weights are renormalized. Sleep measures duration against target, not quality.").font(.footnote)
            }
            Section("Optional energy fallback") {
                input("Full-day expenditure (kcal)", optional: true)
                Text("Leave blank to use Health only, or the optional equation below. A complete explicit profile fills missing components first; this independent total is used when no profile can do so. It is separate from your calorie-intake goal. Today's fallback is prorated by elapsed time in the actual local day; it is not measured activity.").font(.footnote)
                Toggle("Use an explicit Mifflin–St Jeor profile", isOn: $useProfile)
                if useProfile {
                    ForEach(["Equation age (years)", "Equation height (cm)", "Equation weight (kg)", "Activity multiplier"], id: \.self) { input($0, optional: $0 == "Activity multiplier") }
                    Picker("Equation parameter", selection: $parameter) {
                        Text("Choose explicitly").tag("")
                        Text("Male coefficient (+5)").tag("male")
                        Text("Female coefficient (−161)").tag("female")
                    }
                    Text("Equation parameter is an explicit choice of the rounded equation, not inferred gender. This adult equation may not be appropriate for you; no profile values or multiplier are guessed. Leave multiplier blank to predict resting only and require Health active energy. Predicted resting = 10 × kg + 6.25 × cm − 5 × age + coefficient. Missing active = predicted resting × (multiplier − 1). Valid Health components win individually. Update the explicitly selected weight here when needed; Health weight is not silently substituted. Individual error can be substantial.").font(.footnote)
                }
            }
            Section("Data quality and interpretation") {
                Text("Heart baseline: prior 28 local days excluding the recent 3-day window; at least 14 baseline days from one source. Recent summaries need 2 distinct days (and 3 HRV samples / 2 resting-HR samples). Daily medians, range checks and median absolute deviation filters reject outliers. No missing signal becomes zero or a default reading.")
                Text("Training component: prior 7 vs 28 days, requiring 5/7 and 21/28 observed days in one mode. Unknown days are not rest days. If workout modes differ, a consistent all-days Health active-energy fallback can be used; modes are never mixed. Coverage and sources are shown in ring details. All recovery mappings are wellness estimates, not readiness, illness or injury diagnoses.")
                Text("Settings update current predictions and Strain/Recovery. The first closed-day expenditure prediction is preserved locally with its profile, sources and calculation time; profile edits do not overwrite it. Never-viewed past days use the profile available when first calculated. New complete Health values take priority while the saved prediction remains retained. Configuration is local and included in explicit JSON exports; Health HRV/RHR samples are never persisted or exported.")
            }.font(.footnote)
        }.navigationTitle("Scoring & estimates").navigationBarBackButtonHidden(true).fitnessScreen().workoutKeyboardToolbar()
        .onAppear { populate() }
        .confirmDiscardChanges(dirty: dirty, requested: $cancelling) { dismiss() }
        .nutritionError($error)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Cancel") { if dirty { cancelling = true } else { dismiss() } } }
            ToolbarItem(placement: .confirmationAction) { Button("Save scoring settings") { save() } }
        }
    }
    private func populate() {
        guard original == nil else { return }
        let c = preferences.configuration
        personalize = c.personalizeLoad
        let values = ["Target scale": c.targetScale, "Session-RPE target": c.rpeTarget, "Workout minutes target": c.minutesTarget,
            "Active kcal target": c.activeEnergyTarget, "Step-count target": c.stepsTarget, "Sleep target (minutes)": c.sleepTargetMinutes,
            "Sleep weight": c.sleepWeight, "HRV weight": c.hrvWeight, "Resting HR weight": c.restingHRWeight, "Training-load weight": c.loadWeight,
            "HRV mapping slope": c.hrvSlope, "Resting HR penalty per bpm": c.restingHRPenalty]
        fields = values.mapValues(NutritionNumber.text)
        fields["Full-day expenditure (kcal)"] = c.dailyExpenditure.map(NutritionNumber.text) ?? ""
        useProfile = c.profile != nil
        if let p = c.profile {
            fields["Equation age (years)"] = NutritionNumber.text(p.age); fields["Equation height (cm)"] = NutritionNumber.text(p.heightCM)
            fields["Equation weight (kg)"] = NutritionNumber.text(p.weightKG); fields["Activity multiplier"] = p.multiplier.map(NutritionNumber.text) ?? ""
            parameter = p.parameter.rawValue
        }
        original = fingerprint
    }
    private func save() {
        func number(_ key: String) throws -> Double { try NutritionNumber.parse(fields[key] ?? "") }
        do {
            var c = preferences.configuration
            c.personalizeLoad = personalize; c.targetScale = try number("Target scale")
            c.rpeTarget = try number("Session-RPE target"); c.minutesTarget = try number("Workout minutes target")
            c.activeEnergyTarget = try number("Active kcal target"); c.stepsTarget = try number("Step-count target")
            c.sleepTargetMinutes = try number("Sleep target (minutes)"); c.sleepWeight = try number("Sleep weight")
            c.hrvWeight = try number("HRV weight"); c.restingHRWeight = try number("Resting HR weight"); c.loadWeight = try number("Training-load weight")
            c.hrvSlope = try number("HRV mapping slope"); c.restingHRPenalty = try number("Resting HR penalty per bpm")
            c.dailyExpenditure = (fields["Full-day expenditure (kcal)"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : try number("Full-day expenditure (kcal)")
            c.profile = nil
            if useProfile {
                guard let parameter = ExpenditureProfile.EquationParameter(rawValue: parameter) else { throw ScoringError.profile }
                c.profile = ExpenditureProfile(age: try number("Equation age (years)"), heightCM: try number("Equation height (cm)"),
                    weightKG: try number("Equation weight (kg)"), parameter: parameter, multiplier: (fields["Activity multiplier"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : try number("Activity multiplier"))
            }
            try preferences.save(c); original = fingerprint; dismiss()
        } catch { self.error = error.localizedDescription }
    }
}
