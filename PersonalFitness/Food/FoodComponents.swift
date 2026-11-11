import SwiftUI

struct NutritionLine: View {
    let nutrients: FoodNutrients
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("\(EnergyDisplay.kilocalories(nutrients.calories)) kcal").font(.headline)
            Text("Protein \(nutrients.protein.formatted(.number.precision(.fractionLength(0...1)))) g · Carbs \(nutrients.carbohydrates.formatted(.number.precision(.fractionLength(0...1)))) g · Fat \(nutrients.fat.formatted(.number.precision(.fractionLength(0...1)))) g")
                .font(.subheadline).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }
}

struct NutritionNumericField: View {
    let title: String
    @Binding var text: String
    var required = true
    @Environment(\.dynamicTypeSize) private var dynamicType
    @FocusState private var focused: Bool

    var body: some View {
        if dynamicType.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 8) {
                Text(title).accessibilityHidden(true)
                field
            }
        } else {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text(title).fixedSize(horizontal: false, vertical: true).accessibilityHidden(true)
                Spacer(minLength: 0)
                field.multilineTextAlignment(.trailing).frame(minWidth: 60, maxWidth: 160)
            }
        }
    }

    private var field: some View {
        TextField(title, text: $text, prompt: Text(required ? "Required" : "Optional"))
            .keyboardType(.decimalPad)
            .frame(minHeight: 44)
            .contentShape(Rectangle())
            .focused($focused)
            .onTapGesture { focused = true }
            .accessibilityLabel(title)
    }
}

struct PortionFields: View {
    let definition: FoodDefinition
    @Binding var quantity: String
    @Binding var unit: FoodUnit
    var body: some View {
        Section("Portion") {
            NutritionNumericField(title: "Quantity", text: $quantity)
            Picker("Unit", selection: $unit) {
                ForEach(definition.supportedUnits) { unit in Text(unit.title).tag(unit) }
            }
        }
        Section("Nutrition for this portion") {
            if let nutrients = try? definition.scaled(quantity: NutritionNumber.parse(quantity), unit: unit) {
                NutritionLine(nutrients: nutrients)
            } else {
                Text("Enter a positive quantity in a supported unit to preview nutrition.")
                    .foregroundStyle(.secondary)
            }
        }
    }
}

struct FoodChoice: Identifiable, Hashable {
    let id: UUID
    let definition: FoodDefinition
    let sourceKind: String
    static func == (lhs: Self, rhs: Self) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

extension View {
    func nutritionError(_ error: Binding<String?>) -> some View {
        alert("Unable to save", isPresented: Binding(
            get: { error.wrappedValue != nil }, set: { if !$0 { error.wrappedValue = nil } })) {
            Button("OK", role: .cancel) { error.wrappedValue = nil }
        } message: { Text(error.wrappedValue ?? "") }
    }
}
