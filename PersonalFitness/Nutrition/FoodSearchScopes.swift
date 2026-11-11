import Foundation

enum FoodSearchScope: String, CaseIterable, Identifiable {
    case all = "All", recent = "Recent", favorites = "Favorites", frequent = "Frequent", custom = "Custom", meals = "Meals"
    var id: String { rawValue }
}
