import Foundation

/// Meal attribution is explicit, never inferred from a timestamp or food name.
enum DiaryMeal: String, CaseIterable, Identifiable, Codable {
    case unassigned = "Unassigned"
    case breakfast = "Breakfast"
    case lunch = "Lunch"
    case dinner = "Dinner"
    case snacks = "Snacks"
    var id: String { rawValue }
}
