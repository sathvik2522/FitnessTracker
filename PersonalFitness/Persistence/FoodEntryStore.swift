import Foundation
import SwiftData

/// The dashboard reads through this boundary; it does not own SwiftData queries.
@MainActor
struct FoodEntryStore {
    let context: ModelContext

    func totals(for day: Date, calendar: Calendar) throws -> NutritionTotals {
        let interval = try LocalDayWindow.interval(for: day, calendar: calendar)
        return try totals(start: interval.start, end: interval.end)
    }

    func snapshot(in window: LocalDayWindow) throws -> DailyNutrition {
        DailyNutrition(totals: try totals(start: window.start, end: window.end), window: window)
    }

    private func totals(start: Date, end: Date) throws -> NutritionTotals {
        let descriptor = FetchDescriptor<FoodEntry>(predicate: #Predicate {
            $0.loggedAt >= start && $0.loggedAt < end
        })
        let entries = try context.fetch(descriptor)
        return NutritionTotals(portions: entries.map {
            NutritionPortion(calories: $0.calories, protein: $0.proteinGrams,
                             carbohydrates: $0.carbohydrateGrams, fat: $0.fatGrams)
        })
    }

}
