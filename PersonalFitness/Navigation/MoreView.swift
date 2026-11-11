import SwiftUI

struct DashboardCustomizationView: View {
    @Environment(GoalPreferences.self) private var preferences
    @State private var configuration = DashboardConfiguration()
    @State private var error: String?
    var body: some View {
        List {
            Section("Metric density") {
                Toggle("Use compact score rings", isOn: $configuration.compactMetrics)
            }
            Section("Dashboard sections") {
                ForEach(configuration.order) { section in
                    HStack {
                        Toggle(section.title, isOn: Binding(get: { !configuration.hidden.contains(section) }, set: { shown in
                            if shown { configuration.hidden.remove(section) } else { configuration.hidden.insert(section) }
                        }))
                        Spacer()
                        Button { move(section, -1) } label: { Image(systemName: "chevron.up") }.disabled(configuration.order.first == section)
                        Button { move(section, 1) } label: { Image(systemName: "chevron.down") }.disabled(configuration.order.last == section)
                    }.frame(minHeight: 44)
                }
            }
            Section { Button("Restore default dashboard") { configuration = DashboardConfiguration() } }
            Text("These display preferences do not change Health data, scores, goals, food, workouts, or historical records.").font(.footnote).foregroundStyle(.secondary)
        }
        .navigationTitle("Customize Today").fitnessScreen()
        .onAppear { configuration = preferences.dashboard }
        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Save") { do { try preferences.saveDashboard(configuration) } catch { self.error = error.localizedDescription } } } }
        .alert("Dashboard not saved", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) { Button("OK", role: .cancel) {} } message: { Text(error ?? "") }
    }
    private func move(_ section: DashboardSection, _ delta: Int) {
        guard let old = configuration.order.firstIndex(of: section) else { return }
        let new = old + delta; guard configuration.order.indices.contains(new) else { return }
        configuration.order.move(fromOffsets: IndexSet(integer: old), toOffset: delta > 0 ? new + 1 : new)
    }
}

struct MoreView: View {
    @Environment(GoalPreferences.self) private var preferences
    @State private var error: String?
    var body: some View {
        NavigationStack {
            List {
                Section("PersonalFitness") {
                    Label("Private. Local. Yours.", systemImage: "leaf.fill").font(.headline)
                    Text("Your diary and training records stay in this app. No account, subscription or backend.").font(.footnote)
                }
                Section("Preferences") {
                    NavigationLink("Nutrition & activity goals") { GoalsEditor() }
                    NavigationLink("Scoring & expenditure settings") { ScoringSettingsView() }
                    NavigationLink("Customize Today dashboard") { DashboardCustomizationView() }
                    Picker("Appearance", selection: Binding(get: { preferences.appearance }, set: {
                        do { try preferences.setAppearance($0) } catch { self.error = error.localizedDescription }
                    })) {
                        Text("System").tag("system")
                        Text("Dark").tag("dark")
                        Text("Light").tag("light")
                        Text("True black").tag("black")
                    }.accessibilityIdentifier("settings.appearance")
                    Picker("Accent", selection: Binding(get: { preferences.accent }, set: { try? preferences.setAccent($0) })) {
                        Text("Blue").tag("blue"); Text("Mint").tag("mint"); Text("Violet").tag("violet"); Text("Orange").tag("orange")
                    }
                    Toggle("Show health insights on Today", isOn: Binding(get: { preferences.insightsVisible }, set: { try? preferences.setInsightsVisible($0) }))
                    Toggle("Show values in widgets", isOn: Binding(get: { preferences.widgetValuesVisible }, set: { try? preferences.setWidgetValuesVisible($0) }))
                    Text("Widget values are hidden by default. iOS may also redact sensitive widgets according to your Lock Screen privacy settings.").font(.footnote).foregroundStyle(.secondary)
                    Picker("Preferred rest timer", selection: Binding(get: { preferences.restDurationSeconds }, set: {
                        do { try preferences.setRestDuration($0) } catch { self.error = error.localizedDescription }
                    })) {
                        ForEach(GoalPreferences.allowedRestDurations, id: \.self) { seconds in
                            Text("\(seconds) seconds").tag(seconds)
                        }
                    }.accessibilityIdentifier("settings.restDuration")
                    Text("Insights are local, use only available scored inputs, and do not send notifications. System notifications remain off.").font(.footnote).foregroundStyle(.secondary)
                }
                Section("Your records") {
                    NavigationLink("Export local data") { DataExportView() }
                    Text("Export preserves all eight local tables and personal goal settings. In-app restore is not available. Keep the app installed when renewing signing.").font(.footnote)
                }
                Section("About the estimates") {
                    Text("Preferred expenditure = Apple Health resting + active energy. An explicit configured fallback may be used in Today/Food when Health energy is incomplete. Balance = recorded intake − expenditure. Manual workout calories are never added again.")
                    Text("Strain is a normalized activity-load estimate; recovery is a weighted wellness heuristic using only eligible signals. Inspect formulas, sources and missing-data states by tapping each ring. Neither is a clinical or readiness measurement.")
                    Text("Manage Health reads from Today. Sleep and HRV/resting heart rate each have separate opt-ins. No write permissions are requested.")
                }.font(.footnote)
                if let error { Section { ErrorMessage(title: "Preference not saved", message: error) } }
            }.navigationTitle("More").fitnessScreen()
        }
    }
}

struct GoalsEditor: View {
    @Environment(GoalPreferences.self) private var preferences
    @Environment(\.dismiss) private var dismiss
    @State private var calories = ""
    @State private var protein = ""
    @State private var carbs = ""
    @State private var fat = ""
    @State private var steps = ""
    @State private var original: [String]?
    @State private var cancelling = false
    @State private var saved = false
    @State private var error: String?
    private var fields: [String] { [calories, protein, carbs, fat, steps] }
    private var dirty: Bool { original != nil && original != fields && !saved }
    var body: some View {
        Form {
            Section {
                Text("Set your own targets. PersonalFitness does not prescribe calorie, macro or step goals. Blank means no goal; zero and negative targets are invalid.")
                NutritionNumericField(title: "Calorie goal (kcal)", text: $calories, required: false)
                NutritionNumericField(title: "Protein goal (g)", text: $protein, required: false)
                NutritionNumericField(title: "Carbohydrate goal (g)", text: $carbs, required: false)
                NutritionNumericField(title: "Fat goal (g)", text: $fat, required: false)
                NutritionNumericField(title: "Step goal", text: $steps, required: false)
            }
            Text("These preferences apply to the dates you view; they are not historical target snapshots and do not alter expenditure or recorded nutrition.").font(.footnote)
            if let error { ErrorMessage(title: "Goals not saved", message: error) }
        }
        .navigationTitle("Personal goals").navigationBarBackButtonHidden(true)
        .fitnessScreen().workoutKeyboardToolbar()
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Cancel") { if dirty { cancelling = true } else { dismiss() } } }
            ToolbarItem(placement: .confirmationAction) { Button("Save goals") { save() } }
        }
        .onAppear {
            guard original == nil else { return }
            let goal = preferences.goals
            calories = goal.calories.map(NutritionNumber.text) ?? ""
            protein = goal.protein.map(NutritionNumber.text) ?? ""
            carbs = goal.carbohydrates.map(NutritionNumber.text) ?? ""
            fat = goal.fat.map(NutritionNumber.text) ?? ""
            steps = goal.steps.map(NutritionNumber.text) ?? ""
            original = fields
        }
        .nutritionError($error)
        .confirmDiscardChanges(dirty: dirty, requested: $cancelling) { dismiss() }
    }
    private func save() {
        func optional(_ text: String) throws -> Double? {
            text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : try NutritionNumber.parse(text)
        }
        do {
            try preferences.save(NutritionGoals(calories: optional(calories), protein: optional(protein),
                carbohydrates: optional(carbs), fat: optional(fat), steps: optional(steps)))
            saved = true; dismiss()
        } catch { self.error = error.localizedDescription }
    }
}
