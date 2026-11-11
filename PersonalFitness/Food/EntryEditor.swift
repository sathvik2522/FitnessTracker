import SwiftUI
import SwiftData

struct EntryEditor: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var id: UUID
    @State private var definition: FoodDefinition?
    @State private var sourceID: UUID?
    @State private var sourceKind: String?
    @State private var legacy: Bool
    @State private var replacing = false
    private let onSaved: (() -> Void)?
    @State private var quantity: String
    @State private var unit: FoodUnit
    @State private var date: Date
    @State private var meal: DiaryMeal = .unassigned
    @State private var error: String?
    @State private var saved = false
    @State private var cancelling = false
    @State private var deleting = false
    @State private var original: String?
    private var fingerprint: String { draftFingerprint([sourceID?.uuidString ?? "", sourceKind ?? "", quantity, unit.rawValue, meal.rawValue, String(date.timeIntervalSince1970), draftFingerprint(definition)]) }
    private var dirty: Bool { original != nil && original != fingerprint && !saved }
    private var existingEntry: Bool { onSaved == nil }

    init(choice: FoodChoice, day: Date, meal: DiaryMeal = .unassigned, onSaved: @escaping () -> Void) {
        _id = State(initialValue: UUID())
        _meal = State(initialValue: meal)
        _definition = State(initialValue: choice.definition)
        _sourceID = State(initialValue: choice.id)
        _sourceKind = State(initialValue: choice.sourceKind)
        _legacy = State(initialValue: false)
        self.onSaved = onSaved
        _quantity = State(initialValue: NutritionNumber.text(choice.definition.referenceQuantity))
        _unit = State(initialValue: choice.definition.referenceUnit)
        _date = State(initialValue: (try? DiaryDate.timestamp(for: day)) ?? Calendar.current.startOfDay(for: day))
    }

    init(entry: FoodEntry) {
        _id = State(initialValue: entry.id)
        _definition = State(initialValue: try? entry.definitionSnapshot())
        _sourceID = State(initialValue: entry.sourceID)
        _sourceKind = State(initialValue: entry.sourceKind)
        _legacy = State(initialValue: entry.referenceSnapshot == nil)
        onSaved = nil
        _quantity = State(initialValue: NutritionNumber.text(entry.quantity))
        _unit = State(initialValue: entry.unit)
        _date = State(initialValue: entry.loggedAt)
        _meal = State(initialValue: entry.mealCategory)
    }

    init(copying entry: FoodEntry, onSaved: @escaping () -> Void) {
        _id = State(initialValue: UUID())
        _definition = State(initialValue: try? entry.definitionSnapshot())
        _sourceID = State(initialValue: entry.sourceID)
        _sourceKind = State(initialValue: entry.sourceKind)
        _legacy = State(initialValue: entry.referenceSnapshot == nil)
        self.onSaved = onSaved
        _quantity = State(initialValue: NutritionNumber.text(entry.quantity))
        _unit = State(initialValue: entry.unit)
        _date = State(initialValue: entry.loggedAt)
        _meal = State(initialValue: entry.mealCategory)
    }

    var body: some View {
        Form {
            Section { Text("Diary: \(date.formatted(date: .abbreviated, time: .omitted))").font(.headline) }
            Section {
                Picker("Meal", selection: $meal) {
                    ForEach(DiaryMeal.allCases) { Text($0.rawValue).tag($0) }
                }.accessibilityIdentifier("diary.meal")
            }
            Section { Button("Change food or meal") { replacing = true } }
            if let definition {
                Section {
                    Label(definition.displayName, systemImage: "fork.knife.circle.fill").font(.title3.bold())
                    Text(definition.catalog.map { "\($0.attribution) · \($0.userModified ? "Personal edits" : "Catalog reference")" } ?? "Personally entered nutrition")
                        .font(.caption).foregroundStyle(.secondary)
                    Text("Reference: \(EnergyDisplay.kilocalories(definition.nutrients.calories)) kcal per \(NutritionNumber.text(definition.referenceQuantity)) \(definition.referenceUnit.rawValue). Preparation: \(definition.preparation.rawValue).")
                        .font(.caption)
                }
                PortionFields(definition: definition, quantity: $quantity, unit: $unit)
                if definition.supportedUnits.contains(.grams), let servings = definition.sourceServings, !servings.isEmpty {
                    Section("Verified source portions") {
                        ScrollView(.horizontal) {
                            HStack {
                                ForEach(Array(servings.prefix(6).enumerated()), id: \.offset) { _, serving in
                                    Button(serving.label) {
                                        unit = .grams; quantity = NutritionNumber.text(serving.gramWeight)
                                    }.buttonStyle(.bordered).frame(minHeight: 44)
                                }
                            }
                        }
                        Text("Buttons use the source's explicit gram weight; no piece size or ml density is inferred.").font(.caption)
                    }
                }
                Section("Diary date") {
                    DatePicker("Logged at", selection: $date, in: ...Date.now, displayedComponents: [.date, .hourAndMinute])
                    Text("Editing a portion preserves this date unless you explicitly change it.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                Section {
                    Text(legacy ? "This older entry has no serving definition. Its original total is treated as one serving; only servings are supported." : "This entry uses its saved nutrition snapshot. Later library edits or deletions do not change it.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            } else {
                ErrorMessage(title: "Entry unavailable", message: "The saved snapshot could not be read. The entry has not been changed.")
            }
            if existingEntry { Section { Button("Delete diary entry", role: .destructive) { deleting = true } } }
        }
        .fitnessScreen()
        .safeAreaInset(edge: .bottom) {
            Button { save() } label: {
                Text(existingEntry ? "Save changes" : "Add to Diary")
                    .frame(maxWidth: .infinity, minHeight: 44).contentShape(Rectangle())
            }
                .buttonStyle(.borderedProminent).tint(FitnessTheme.action).foregroundStyle(.white)
                .disabled(saved || definition == nil).padding(.horizontal).padding(.vertical, 8)
                .background(FitnessTheme.background)
        }
        .scrollDismissesKeyboard(.interactively)
        .navigationTitle("Log portion")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Cancel") { if dirty { cancelling = true } else { dismiss() } } }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") { save() }.disabled(saved || definition == nil)
            }
        }
        .sheet(isPresented: $replacing) {
            NavigationStack {
                FoodPicker { choice in
                    definition = choice.definition
                    sourceID = choice.id
                    sourceKind = choice.sourceKind
                    quantity = NutritionNumber.text(choice.definition.referenceQuantity)
                    unit = choice.definition.referenceUnit
                    legacy = false
                    replacing = false
                }
                .navigationTitle("Replace logged food")
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { replacing = false } } }
            }
        }
        .navigationBarBackButtonHidden(true)
        .workoutKeyboardToolbar()
        .onAppear { if original == nil { original = fingerprint } }
        .confirmDiscardChanges(dirty: dirty, requested: $cancelling) { dismiss() }
        .confirmationDialog("Delete this diary entry?", isPresented: $deleting, titleVisibility: .visible) {
            Button("Delete entry", role: .destructive) {
                do { try NutritionStore(context: context).deleteEntry(id: id); dismiss() }
                catch { self.error = error.localizedDescription }
            }
        }
        .nutritionError($error)
    }

    private func save() {
        guard !saved, let definition else { return }
        do {
            try NutritionStore(context: context).saveEntry(id: id, definition: definition,
                quantity: NutritionNumber.parse(quantity), unit: unit, loggedAt: date,
                sourceID: sourceID, sourceKind: sourceKind, meal: meal)
            saved = true
            if let onSaved { onSaved() } else { dismiss() }
        } catch { self.error = error.localizedDescription }
    }
}
