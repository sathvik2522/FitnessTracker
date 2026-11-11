import Foundation
import SwiftData

/// Nutrients describe this entire logged portion, not a per-100g reference.
/// Library changes never rewrite this historical nutrition snapshot.
@Model
final class FoodEntry {
    @Attribute(.unique) var id: UUID
    var loggedAt: Date
    var name: String
    var calories: Double
    var proteinGrams: Double
    var carbohydrateGrams: Double
    var fatGrams: Double
    // Defaults/optional fields permit lightweight migration of existing entries.
    var quantity: Double = 1
    var unitRaw: String = "serving"
    var referenceSnapshot: Data? = nil
    var sourceID: UUID? = nil
    var sourceKind: String? = nil
    // Optional addition supports lightweight migration; older entries stay unassigned.
    var mealCategoryRaw: String? = nil

    var mealCategory: DiaryMeal { DiaryMeal(rawValue: mealCategoryRaw ?? "") ?? .unassigned }

    var unit: FoodUnit { FoodUnit(rawValue: unitRaw) ?? .servings }

    func definitionSnapshot() throws -> FoodDefinition {
        if let referenceSnapshot {
            return try JSONDecoder().decode(FoodDefinition.self, from: referenceSnapshot).validated()
        }
        // Old entries have totals only, not recoverable original serving sizes.
        return try FoodDefinition(name: name, preparation: .unspecified,
                                  nutrients: FoodNutrients(calories: calories, protein: proteinGrams,
                                                          carbohydrates: carbohydrateGrams, fat: fatGrams),
                                  referenceQuantity: 1, referenceUnit: .servings, equivalents: [:]).validated()
    }

    init(name: String, calories: Double, proteinGrams: Double = 0,
         carbohydrateGrams: Double = 0, fatGrams: Double = 0,
         loggedAt: Date = .now) {
        self.id = UUID()
        self.name = name
        self.calories = calories
        self.proteinGrams = proteinGrams
        self.carbohydrateGrams = carbohydrateGrams
        self.fatGrams = fatGrams
        self.loggedAt = loggedAt
    }
}
