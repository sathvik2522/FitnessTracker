import SwiftUI
import SwiftData

struct MealEditor: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var id: UUID
    private let editing: Bool
    private let loadError: Bool
    private let onSaved: ((FoodChoice, Bool) -> Void)?
    @State private var name: String
    @State private var kind: MealKind
    @State private var servings: String
    @State private var ingredients: [RecipeIngredient]
    @State private var adding = false
    @State private var editingIngredient: RecipeIngredient?
    @State private var error: String?
    @State private var original: String?
    @State private var cancelling = false
    private var fingerprint: String { name + kind.rawValue + servings + draftFingerprint(ingredients) }
    private var dirty: Bool { original != nil && original != fingerprint }

    @State private var saved = false

    init(meal: SavedMeal? = nil, kind: MealKind = .meal, onSaved: ((FoodChoice, Bool) -> Void)? = nil) {
        self.onSaved = onSaved
        _id = State(initialValue: meal?.id ?? UUID())
        editing = meal != nil
        let decoded = try? meal?.ingredients()
        loadError = meal != nil && decoded == nil
        _name = State(initialValue: meal?.name ?? "")
        _kind = State(initialValue: meal?.kind ?? kind)
        _servings = State(initialValue: meal.map { NutritionNumber.text($0.servings) } ?? "1")
        _ingredients = State(initialValue: decoded ?? [])
    }

    var body: some View {
        NavigationStack {
            Form {
                if loadError { Text("Ingredients could not be read. This saved item has not been changed.").foregroundStyle(.red) }
                if onSaved != nil { Section { Button("Save to library only") { save() } } }
                Section("Details") {
                    TextField("Name", text: $name)
                    Picker("Type", selection: $kind) { ForEach(MealKind.allCases) { Text($0.rawValue).tag($0) } }
                    NutritionNumericField(title: "Total servings produced", text: $servings)
                }
                Section("Ingredients") {
                    ForEach(ingredients) { ingredient in
                        Button { editingIngredient = ingredient } label: {
                            VStack(alignment: .leading, spacing: 6) {
                                Text(ingredient.food.displayName).foregroundStyle(.primary)
                                Text("\(NutritionNumber.text(ingredient.quantity)) \(ingredient.unit.rawValue)")
                                    .font(.subheadline).foregroundStyle(.secondary)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityHint("Edit this ingredient quantity")
                    }
                    .onDelete { ingredients.remove(atOffsets: $0) }
                    Button("Add ingredient", systemImage: "plus") { adding = true }
                }
                if let total = try? RecipeCalculation.total(ingredients) {
                    Section("Total recipe nutrition") { NutritionLine(nutrients: total) }
                }
                if let yield = try? NutritionNumber.parse(servings),
                   let perServing = try? RecipeCalculation.perServing(ingredients, servings: yield) {
                    Section("Nutrition per serving") { NutritionLine(nutrients: perServing) }
                }
                Section {
                    Text("Ingredients keep the food definition selected when they were added. To adopt new library nutrition, remove and re-add that ingredient. Past diary entries keep their own snapshots.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .fitnessScreen().navigationBarTitleDisplayMode(.inline).navigationTitle(editing ? "Edit \(kind.rawValue.lowercased())" : "New \(kind.rawValue.lowercased())")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { if dirty { cancelling = true } else { dismiss() } } }
                ToolbarItem(placement: .confirmationAction) { Button(onSaved == nil ? "Save" : "Save & log meal") { save(log: onSaved != nil) }.disabled(saved || loadError) }
            }
            .sheet(isPresented: $adding) {
                IngredientSelectionFlow { ingredient in ingredients.append(ingredient) }
            }
            .sheet(item: $editingIngredient) { ingredient in
                NavigationStack {
                    IngredientEditor(ingredient: ingredient) { updated in
                        if let index = ingredients.firstIndex(where: { $0.id == updated.id }) { ingredients[index] = updated }
                        editingIngredient = nil
                    }
                }
            }
            .onAppear { if original == nil { original = fingerprint } }
            .confirmDiscardChanges(dirty: dirty, requested: $cancelling) { dismiss() }
            .nutritionError($error)
        }
    }

    private func save(log: Bool = false) {
        guard !saved else { return }
        do {
            let definition = try FoodDefinition(name: name, preparation: .unspecified,
                nutrients: RecipeCalculation.perServing(ingredients, servings: NutritionNumber.parse(servings)),
                referenceQuantity: 1, referenceUnit: .servings, equivalents: [:]).validated()
            try NutritionStore(context: context).saveMeal(id: id, name: name, kind: kind,
                servings: NutritionNumber.parse(servings), ingredients: ingredients)
            saved = true
            onSaved?(FoodChoice(id: id, definition: definition, sourceKind: kind.rawValue), log)
            dismiss()
        } catch { self.error = error.localizedDescription }
    }
}

private struct IngredientSelectionFlow: View {
    @Environment(\.dismiss) private var dismiss
    let add: (RecipeIngredient) -> Void
    @State private var choice: FoodChoice?
    var body: some View {
        NavigationStack {
            FoodPicker(foodsOnly: true) { choice = $0 }
                .fitnessScreen().navigationBarTitleDisplayMode(.inline).navigationTitle("Choose ingredient")
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
                .navigationDestination(item: $choice) { food in
                    IngredientEditor(ingredient: RecipeIngredient(foodID: food.id, food: food.definition,
                        quantity: food.definition.referenceQuantity, unit: food.definition.referenceUnit)) {
                            add($0)
                            dismiss()
                        }
                }
        }
    }
}

private struct IngredientEditor: View {
    @Environment(\.dismiss) private var dismiss
    let ingredient: RecipeIngredient
    let save: (RecipeIngredient) -> Void
    @State private var quantity: String
    @State private var unit: FoodUnit
    @State private var error: String?
    @State private var saved = false
    @State private var cancelling = false
    private var dirty: Bool { !saved && (quantity != NutritionNumber.text(ingredient.quantity) || unit != ingredient.unit) }
    init(ingredient: RecipeIngredient, save: @escaping (RecipeIngredient) -> Void) {
        self.ingredient = ingredient
        self.save = save
        _quantity = State(initialValue: NutritionNumber.text(ingredient.quantity))
        _unit = State(initialValue: ingredient.unit)
    }
    var body: some View {
        Form {
            Section { Text(ingredient.food.displayName).font(.headline) }
            PortionFields(definition: ingredient.food, quantity: $quantity, unit: $unit)
        }
        .fitnessScreen().navigationBarTitleDisplayMode(.inline).navigationTitle("Ingredient quantity")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Cancel") { if dirty { cancelling = true } else { dismiss() } } }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    do {
                        var updated = ingredient
                        updated.quantity = try NutritionNumber.parse(quantity)
                        updated.unit = unit
                        _ = try updated.nutrients()
                        saved = true
                        save(updated)
                    } catch { self.error = error.localizedDescription }
                }.disabled(saved)
            }
        }
        .navigationBarBackButtonHidden(true)
        .confirmDiscardChanges(dirty: dirty, requested: $cancelling) { dismiss() }
        .nutritionError($error)
    }
}
