import Foundation

enum NutritionError: String, Error, LocalizedError {
    case name = "Enter a food or meal name."
    case number = "Enter valid finite numbers for all required nutrition fields."
    case quantity = "Quantities and serving counts must be greater than zero."
    case nutrients = "Calories and macros must be finite and zero or greater."
    case unit = "This unit has no defined equivalent for this food. Add an explicit equivalent in the food editor."
    case ingredients = "Add at least one ingredient."
    case futureDate = "Choose a logging date and time that is not in the future."
    case missing = "This item is no longer available. Close the editor and try again."
    var errorDescription: String? { rawValue }
}

enum FoodUnit: String, Codable, CaseIterable, Identifiable {
    case grams = "g", milliliters = "ml", servings = "serving", pieces = "piece"
    var id: String { rawValue }
    var title: String {
        switch self {
        case .grams: return "Grams"
        case .milliliters: return "Milliliters"
        case .servings: return "Servings"
        case .pieces: return "Pieces"
        }
    }
}

enum FoodPreparation: String, Codable, CaseIterable, Identifiable {
    case unspecified = "Not specified", raw = "Raw", cooked = "Cooked"
    var id: String { rawValue }
}

enum MealKind: String, Codable, CaseIterable, Identifiable {
    case meal = "Meal", recipe = "Recipe"
    var id: String { rawValue }
}

struct FoodNutrients: Codable, Equatable {
    var calories: Double
    var protein: Double
    var carbohydrates: Double
    var fat: Double

    func validated() throws -> Self {
        guard [calories, protein, carbohydrates, fat].allSatisfy({ $0.isFinite && $0 >= 0 }) else {
            throw NutritionError.nutrients
        }
        return self
    }

    func scaled(by factor: Double) throws -> Self {
        _ = try validated()
        guard factor.isFinite, factor > 0 else { throw NutritionError.quantity }
        return try Self(calories: calories * factor, protein: protein * factor,
                        carbohydrates: carbohydrates * factor, fat: fat * factor).validated()
    }

    var portion: NutritionPortion {
        NutritionPortion(calories: calories, protein: protein, carbohydrates: carbohydrates, fat: fat)
    }
}

/// Nutrition and all equivalents describe the SAME reference portion.
/// No density or piece-size conversion is inferred.
struct FoodDefinition: Codable, Equatable {
    var name: String
    var preparation: FoodPreparation
    var nutrients: FoodNutrients
    var referenceQuantity: Double
    var referenceUnit: FoodUnit
    var equivalents: [FoodUnit: Double]
    var aliases: [String]? = nil
    var sourceServings: [CatalogServing]? = nil
    var catalog: CatalogOrigin? = nil

    func validated() throws -> Self {
        var definition = self
        definition.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !definition.name.isEmpty else { throw NutritionError.name }
        _ = try nutrients.validated()
        guard referenceQuantity.isFinite, referenceQuantity > 0,
              equivalents.values.allSatisfy({ $0.isFinite && $0 > 0 }) else { throw NutritionError.quantity }
        if let duplicate = equivalents[referenceUnit], duplicate != referenceQuantity { throw NutritionError.unit }
        return definition
    }

    var supportedUnits: [FoodUnit] {
        FoodUnit.allCases.filter { $0 == referenceUnit || equivalents[$0] != nil }
    }

    func scaled(quantity: Double, unit: FoodUnit) throws -> FoodNutrients {
        _ = try validated()
        guard quantity.isFinite, quantity > 0 else { throw NutritionError.quantity }
        guard let reference = unit == referenceUnit ? referenceQuantity : equivalents[unit] else {
            throw NutritionError.unit
        }
        return try nutrients.scaled(by: quantity / reference)
    }

    var displayName: String {
        preparation == .unspecified ? name : "\(name) (\(preparation.rawValue.lowercased()))"
    }
}

struct RecipeIngredient: Codable, Identifiable, Equatable {
    var id = UUID()
    var foodID: UUID?
    var food: FoodDefinition
    var quantity: Double
    var unit: FoodUnit
    func nutrients() throws -> FoodNutrients { try food.scaled(quantity: quantity, unit: unit) }
}

enum RecipeCalculation {
    static func total(_ ingredients: [RecipeIngredient]) throws -> FoodNutrients {
        guard !ingredients.isEmpty else { throw NutritionError.ingredients }
        let totals = NutritionTotals(portions: try ingredients.map { try $0.nutrients().portion })
        guard let calories = totals.calories, let protein = totals.protein,
              let carbohydrates = totals.carbohydrates, let fat = totals.fat else { throw NutritionError.nutrients }
        return try FoodNutrients(calories: calories, protein: protein, carbohydrates: carbohydrates, fat: fat).validated()
    }

    static func perServing(_ ingredients: [RecipeIngredient], servings: Double) throws -> FoodNutrients {
        guard servings.isFinite, servings > 0 else { throw NutritionError.quantity }
        return try total(ingredients).scaled(by: 1 / servings)
    }
}

enum NutritionNumber {
    static func parse(_ text: String, locale: Locale = .current) throws -> Double {
        let input = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let decimal = NSRegularExpression.escapedPattern(for: locale.decimalSeparator ?? ".")
        let pattern = "^[+-]?(?:[0-9]+(?:\(decimal)[0-9]*)?|\(decimal)[0-9]+)(?:[eE][+-]?[0-9]+)?$"
        guard input.range(of: pattern, options: .regularExpression) != nil,
              let value = try? Double(input, format: .number.locale(locale), lenient: false), value.isFinite else {
            throw NutritionError.number
        }
        return value
    }
    static func text(_ value: Double) -> String {
        value.formatted(.number.grouping(.never).precision(.significantDigits(1...17)))
    }
}

enum DiaryDate {
    static func timestamp(for day: Date, now: Date = .now, calendar: Calendar = .current) throws -> Date {
        let interval = try LocalDayWindow.interval(for: day, calendar: calendar)
        guard interval.start <= now else { throw NutritionError.futureDate }
        if calendar.isDate(day, inSameDayAs: now) { return now }
        return calendar.date(bySettingHour: 12, minute: 0, second: 0, of: interval.start) ?? interval.start
    }

    static func validate(_ date: Date, now: Date = .now) throws {
        guard date.timeIntervalSince1970.isFinite, date <= now else { throw NutritionError.futureDate }
    }
}
