import SwiftUI
import SwiftData

private struct FoodDraft: Equatable {
    var name = ""
    var preparation = FoodPreparation.unspecified
    var calories = ""
    var protein = ""
    var carbohydrates = ""
    var fat = ""
    var quantity = "100"
    var unit = FoodUnit.grams
    var equivalents: [FoodUnit: String] = [:]

    init(_ definition: FoodDefinition? = nil) {
        guard let definition else { return }
        name = definition.name
        preparation = definition.preparation
        calories = NutritionNumber.text(definition.nutrients.calories)
        protein = NutritionNumber.text(definition.nutrients.protein)
        carbohydrates = NutritionNumber.text(definition.nutrients.carbohydrates)
        fat = NutritionNumber.text(definition.nutrients.fat)
        quantity = NutritionNumber.text(definition.referenceQuantity)
        unit = definition.referenceUnit
        equivalents = definition.equivalents.mapValues(NutritionNumber.text)
    }

    func definition() throws -> FoodDefinition {
        var converted: [FoodUnit: Double] = [:]
        for (key, value) in equivalents where key != unit && !value.trimmingCharacters(in: .whitespaces).isEmpty {
            converted[key] = try NutritionNumber.parse(value)
        }
        return try FoodDefinition(name: name, preparation: preparation,
            nutrients: FoodNutrients(calories: NutritionNumber.parse(calories), protein: NutritionNumber.parse(protein),
                                    carbohydrates: NutritionNumber.parse(carbohydrates), fat: NutritionNumber.parse(fat)),
            referenceQuantity: NutritionNumber.parse(quantity), referenceUnit: unit, equivalents: converted).validated()
    }
}

struct FoodEditor: View {
    @Environment(\.dynamicTypeSize) private var dynamicType
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @FocusState private var nameFocused: Bool
    @State private var id: UUID
    private let editing: Bool
    private let sourceDefinition: FoodDefinition?
    private let loadError: String?
    @State private var draft: FoodDraft
    @State private var error: String?
    @State private var saved = false
    @State private var cancelling = false
    private let original: FoodDraft
    private let onSaved: ((FoodChoice, Bool) -> Void)?
    private let continuationTitle: String

    init(food: SavedFood? = nil, continuationTitle: String = "Save & log",
         onSaved: ((FoodChoice, Bool) -> Void)? = nil) {
        _id = State(initialValue: food?.id ?? UUID())
        self.onSaved = onSaved
        self.continuationTitle = continuationTitle
        editing = food != nil
        let definition = try? food?.definition()
        sourceDefinition = definition
        loadError = food != nil && definition == nil ? "This saved definition cannot be read. Close the editor; it has not been changed." : nil
        original = FoodDraft(definition)
        _draft = State(initialValue: original)
    }

    var body: some View {
        NavigationStack {
            Form {
                if let loadError { Text(loadError).foregroundStyle(.red) }
                if onSaved != nil {
                    Section {
                        Button("Save to library only") { save() }.disabled(saved || loadError != nil)
                        Text("\(continuationTitle) continues to portion details.").font(.footnote).foregroundStyle(.secondary)
                    }.listRowBackground(FitnessTheme.card)
                }
                Section("Food") {
                    TextField("Name", text: $draft.name)
                        .focused($nameFocused).frame(minHeight: 44).contentShape(Rectangle())
                        .onTapGesture { nameFocused = true }
                    if dynamicType.isAccessibilitySize {
                        preparationPicker.pickerStyle(.inline)
                    } else { preparationPicker }
                }.listRowBackground(FitnessTheme.card)
                Section("Reference portion") {
                    NutritionNumericField(title: "Reference quantity", text: $draft.quantity)
                    if dynamicType.isAccessibilitySize {
                        unitPicker.pickerStyle(.inline)
                    } else { unitPicker }
                }.listRowBackground(FitnessTheme.card)
                Section {
                    NutritionNumericField(title: "Calories (kcal)", text: $draft.calories)
                    NutritionNumericField(title: "Protein (g)", text: $draft.protein)
                    NutritionNumericField(title: "Carbohydrates (g)", text: $draft.carbohydrates)
                    NutritionNumericField(title: "Fat (g)", text: $draft.fat)
                } header: { Text("Nutrition for the entire reference portion") }
                  footer: { Text("Enter every value, including 0 when a nutrient is known to be zero. Use label or personally sourced nutrition values.") }
                  .listRowBackground(FitnessTheme.card)
                Section {
                    ForEach(FoodUnit.allCases.filter { $0 != draft.unit }) { unit in
                        NutritionNumericField(title: "Equivalent \(unit.title.lowercased())", text: Binding(
                            get: { draft.equivalents[unit] ?? "" }, set: { draft.equivalents[unit] = $0 }), required: false)
                    }
                } header: { Text("Same portion in other units") }
                  footer: { Text("Optional: how many grams, ml, servings or pieces equal this SAME reference portion? Leave unsupported units blank. Grams and ml are never assumed equivalent.") }
                  .listRowBackground(FitnessTheme.card)
                if let source = sourceDefinition, let origin = source.catalog {
                    Section("Catalog source") {
                        Text(origin.attribution)
                        Text("\(origin.license) · FDC \(origin.recordID) · \(origin.release)").font(.caption)
                        Text(origin.quality).font(.caption)
                        if origin.userModified { Text("Personal edits override the catalog reference. Edited nutrition is not verified by USDA.").font(.footnote) }
                        Text("Source portions describe the original data. Personal edits never change past diary entries.").font(.footnote)
                        ForEach(Array((source.sourceServings ?? []).enumerated()), id: \.offset) { _, serving in Text(serving.label).font(.footnote) }
                    }.listRowBackground(FitnessTheme.card)
                }
                // Keep this section's identity stable as validation changes. Adding
                // a section on the first keystroke can replace a focused Form cell.
                Section("Reference nutrition") {
                    if let definition = try? draft.definition() { NutritionLine(nutrients: definition.nutrients) }
                    else { Text("Enter a name, a positive reference quantity, and every calorie/macro value. Known zero values must be entered as 0.").foregroundStyle(.primary) }
                }.listRowBackground(FitnessTheme.card)
            }
            .scrollDismissesKeyboard(.interactively)
            .fitnessScreen().navigationBarTitleDisplayMode(.inline).navigationTitle(editing ? "Edit food" : "New food")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { if draft != original { cancelling = true } else { dismiss() } } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(onSaved == nil ? "Save" : continuationTitle) { save(log: onSaved != nil) }.disabled(saved || loadError != nil)
                }
            }
            .workoutKeyboardToolbar()
            .confirmDiscardChanges(dirty: draft != original && !saved, requested: $cancelling) { dismiss() }
            .nutritionError($error)
        }
    }

    private var preparationPicker: some View {
        Picker("Preparation", selection: $draft.preparation) {
            ForEach(FoodPreparation.allCases) {
                Text($0.rawValue).fixedSize(horizontal: false, vertical: true).tag($0)
            }
        }
    }

    private var unitPicker: some View {
        Picker("Reference unit", selection: $draft.unit) {
            ForEach(FoodUnit.allCases) {
                Text($0.title).fixedSize(horizontal: false, vertical: true).tag($0)
            }
        }
    }

    private func save(log: Bool = false) {
        guard !saved else { return }
        do {
            let definition = try draft.definition()
            try NutritionStore(context: context).saveFood(id: id, definition: definition)
            saved = true
            onSaved?(FoodChoice(id: id, definition: definition, sourceKind: "food"), log)
            dismiss()
        } catch { self.error = error.localizedDescription }
    }
}
