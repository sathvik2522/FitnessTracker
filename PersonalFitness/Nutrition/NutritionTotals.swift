import Foundation

struct NutritionPortion {
    let calories: Double
    let protein: Double
    let carbohydrates: Double
    let fat: Double
}

struct NutritionTotals {
    let entryCount: Int
    let calories: Double?
    let protein: Double?
    let carbohydrates: Double?
    let fat: Double?

    init(portions: [NutritionPortion]) {
        entryCount = portions.count
        calories = Self.sum(portions.map(\.calories))
        protein = Self.sum(portions.map(\.protein))
        carbohydrates = Self.sum(portions.map(\.carbohydrates))
        fat = Self.sum(portions.map(\.fat))
    }

    private static func sum(_ values: [Double]) -> Double? {
        guard values.allSatisfy({ $0.isFinite && $0 >= 0 }) else { return nil }
        let total = values.reduce(0, +)
        return total.isFinite ? total : nil
    }
}
