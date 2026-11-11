import Foundation
import SwiftData

/// Ingredient snapshots deliberately outlive edits/deletions in the food library.
@Model
final class SavedMeal {
    @Attribute(.unique) var id: UUID
    var name: String
    var kindRaw: String
    var servings: Double
    var ingredientsData: Data
    var useCount: Int = 0
    var lastUsedAt: Date? = nil

    init(id: UUID, name: String, kind: MealKind, servings: Double, ingredients: [RecipeIngredient]) throws {
        self.id = id
        self.name = name
        self.kindRaw = kind.rawValue
        self.servings = servings
        self.ingredientsData = try JSONEncoder().encode(ingredients)
    }

    var kind: MealKind { MealKind(rawValue: kindRaw) ?? .meal }
    func ingredients() throws -> [RecipeIngredient] {
        try JSONDecoder().decode([RecipeIngredient].self, from: ingredientsData)
    }
    func definition() throws -> FoodDefinition {
        try FoodDefinition(name: name, preparation: .unspecified,
                           nutrients: RecipeCalculation.perServing(ingredients(), servings: servings),
                           referenceQuantity: 1, referenceUnit: .servings, equivalents: [:]).validated()
    }
}
