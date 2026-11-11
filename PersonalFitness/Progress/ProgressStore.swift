import Foundation
import SwiftData

extension Notification.Name { static let manualWeightDidChange = Notification.Name("PersonalFitness.manualWeightDidChange") }

struct LocalProgressData {
    let food: [ReportFood]
    let strength: [StrengthDraft]
    let cardio: [CardioDraft]
    let weights: [WeightObservation]
}

@MainActor
struct ProgressStore {
    let context: ModelContext
    func read(_ range: ReportRange, now: Date, calendar: Calendar = .current) throws -> LocalProgressData {
        let start = range.start, end = min(range.end, now)
        let foods = try context.fetch(FetchDescriptor<FoodEntry>(predicate: #Predicate { $0.loggedAt >= start && $0.loggedAt < end }))
        let strength = try context.fetch(FetchDescriptor<StrengthSession>(predicate: #Predicate { $0.start >= start && $0.start < end }))
        let cardio = try context.fetch(FetchDescriptor<CardioSession>(predicate: #Predicate { $0.start >= start && $0.start < end }))
        let weightStart = calendar.date(byAdding: .day, value: -6, to: start)!
        let weights = try context.fetch(FetchDescriptor<ManualWeight>(predicate: #Predicate { $0.date >= weightStart && $0.date < end }))
        // Decode errors fail explicitly; corrupt sessions are not silently dropped from counts.
        return try LocalProgressData(food: foods.map { ReportFood(id: $0.id, date: $0.loggedAt, name: $0.name,
            portion: NutritionPortion(calories: $0.calories, protein: $0.proteinGrams, carbohydrates: $0.carbohydrateGrams, fat: $0.fatGrams)) },
            strength: strength.map { try $0.draft() }, cardio: cardio.map { try $0.draft() },
            weights: weights.map { try $0.observation.validated(now: now) })
    }
    func saveWeight(_ value: WeightObservation) throws {
        let value = try value.validated()
        guard value.origin == .manual else { throw ReportError.weight }
        let id = value.id
        let existing = try context.fetch(FetchDescriptor<ManualWeight>(predicate: #Predicate { $0.id == id })).first
        do {
            if let existing { existing.date = value.date; existing.kilograms = value.kilograms }
            else { context.insert(ManualWeight(id: id, date: value.date, kilograms: value.kilograms)) }
            try context.save()
            NotificationCenter.default.post(name: .manualWeightDidChange, object: nil)
        } catch { context.rollback(); throw error }
    }
    func deleteWeight(id: UUID) throws {
        guard let weight = try context.fetch(FetchDescriptor<ManualWeight>(predicate: #Predicate { $0.id == id })).first else { return }
        do {
            context.delete(weight); try context.save()
            NotificationCenter.default.post(name: .manualWeightDidChange, object: nil)
        } catch { context.rollback(); throw error }
    }
}
