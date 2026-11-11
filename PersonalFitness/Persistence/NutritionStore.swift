import Foundation
import SwiftData

extension Notification.Name {
    static let nutritionDidChange = Notification.Name("PersonalFitness.nutritionDidChange")
}

/// Editors hold value drafts. Only validated saves mutate the shared context.
@MainActor
struct NutritionStore {
    let context: ModelContext

    private func commit(_ change: () throws -> Void) throws {
        do {
            try change()
            try context.save()
            NotificationCenter.default.post(name: .nutritionDidChange, object: nil)
        } catch {
            context.rollback()
            throw error
        }
    }

    func deleteEntry(id: UUID) throws {
        if let item = try context.fetch(FetchDescriptor<FoodEntry>(predicate: #Predicate { $0.id == id })).first {
            try delete(item)
        }
    }

    func moveEntry(id: UUID, meal: DiaryMeal) throws {
        guard let entry = try context.fetch(FetchDescriptor<FoodEntry>(predicate: #Predicate { $0.id == id })).first else {
            throw CocoaError(.fileNoSuchFile)
        }
        // Moving a meal never rescales or rewrites the historical snapshot/date.
        try commit { entry.mealCategoryRaw = meal == .unassigned ? nil : meal.rawValue }
    }

    /// Repeat the recorded portion itself, including legacy snapshots and provenance.
    /// A stable destination ID makes repeated delivery of the same action idempotent.
    func repeatEntry(_ source: FoodEntry, id: UUID, loggedAt: Date, meal: DiaryMeal) throws {
        try DiaryDate.validate(loggedAt)
        guard try context.fetch(FetchDescriptor<FoodEntry>(predicate: #Predicate { $0.id == id })).isEmpty else { return }
        try commit {
            let copy = FoodEntry(name: source.name, calories: source.calories, proteinGrams: source.proteinGrams,
                                 carbohydrateGrams: source.carbohydrateGrams, fatGrams: source.fatGrams, loggedAt: loggedAt)
            copy.id = id
            copy.quantity = source.quantity; copy.unitRaw = source.unitRaw
            copy.referenceSnapshot = source.referenceSnapshot
            copy.sourceID = source.sourceID; copy.sourceKind = source.sourceKind
            copy.mealCategoryRaw = meal == .unassigned ? nil : meal.rawValue
            context.insert(copy)
        }
    }

    func saveFood(id: UUID, definition: FoodDefinition) throws {
        var definition = try definition.validated()
        let existing = try context.fetch(FetchDescriptor<SavedFood>(predicate: #Predicate { $0.id == id })).first
        if let previous = try existing?.definition(), let origin = previous.catalog {
            definition.catalog = origin
            definition.aliases = definition.aliases ?? previous.aliases
            definition.sourceServings = definition.sourceServings ?? previous.sourceServings
            if let baseline = origin.baseline {
                let old = try JSONDecoder().decode(FoodDefinition.self, from: baseline)
                let modified = CatalogMerge.stripped(definition) != old
                definition.catalog?.userModified = modified
            }
        }
        let data = try JSONEncoder().encode(definition)
        try commit {
            if let existing {
                existing.name = definition.name
                existing.definitionData = data
            } else { context.insert(try SavedFood(id: id, definition: definition)) }
        }
    }

    func saveMeal(id: UUID, name: String, kind: MealKind, servings: Double,
                  ingredients: [RecipeIngredient]) throws {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { throw NutritionError.name }
        _ = try RecipeCalculation.perServing(ingredients, servings: servings)
        let data = try JSONEncoder().encode(ingredients)
        let existing = try context.fetch(FetchDescriptor<SavedMeal>(predicate: #Predicate { $0.id == id })).first
        try commit {
            if let existing {
                existing.name = name
                existing.kindRaw = kind.rawValue
                existing.servings = servings
                existing.ingredientsData = data
            } else {
                context.insert(try SavedMeal(id: id, name: name, kind: kind, servings: servings, ingredients: ingredients))
            }
        }
    }

    func saveEntry(id: UUID, definition: FoodDefinition, quantity: Double, unit: FoodUnit,
                   loggedAt: Date, sourceID: UUID?, sourceKind: String?, meal: DiaryMeal? = nil) throws {
        let definition = try definition.validated()
        let nutrients = try definition.scaled(quantity: quantity, unit: unit)
        try DiaryDate.validate(loggedAt)
        let data = try JSONEncoder().encode(definition)
        let existing = try context.fetch(FetchDescriptor<FoodEntry>(predicate: #Predicate { $0.id == id })).first
        let recordUse = existing == nil || existing?.sourceID != sourceID || existing?.sourceKind != sourceKind
        try commit {
            let entry: FoodEntry
            if let existing { entry = existing }
            else {
                entry = FoodEntry(name: definition.displayName, calories: nutrients.calories, loggedAt: loggedAt)
                entry.id = id
                context.insert(entry)
            }
            if recordUse, let sourceID {
                if sourceKind == "food",
                   let food = try context.fetch(FetchDescriptor<SavedFood>(predicate: #Predicate { $0.id == sourceID })).first {
                    food.useCount += 1
                    food.lastUsedAt = .now
                } else if sourceKind == MealKind.meal.rawValue || sourceKind == MealKind.recipe.rawValue,
                          let meal = try context.fetch(FetchDescriptor<SavedMeal>(predicate: #Predicate { $0.id == sourceID })).first {
                    meal.useCount += 1
                    meal.lastUsedAt = .now
                }
            }
            entry.name = definition.displayName
            entry.loggedAt = loggedAt
            entry.calories = nutrients.calories
            entry.proteinGrams = nutrients.protein
            entry.carbohydrateGrams = nutrients.carbohydrates
            entry.fatGrams = nutrients.fat
            entry.quantity = quantity
            entry.unitRaw = unit.rawValue
            entry.referenceSnapshot = data
            entry.sourceID = sourceID
            entry.sourceKind = sourceKind
            // Existing callers (including quick-add) preserve attribution on edits.
            if let meal { entry.mealCategoryRaw = meal == .unassigned ? nil : meal.rawValue }
        }
    }

    func delete<T: PersistentModel>(_ item: T) throws {
        try commit {
            if let food = item as? SavedFood, var definition = try? food.definition(), definition.catalog != nil {
                definition.catalog?.archived = true
                food.definitionData = try JSONEncoder().encode(definition)
            } else { context.delete(item) }
        }
    }
}
