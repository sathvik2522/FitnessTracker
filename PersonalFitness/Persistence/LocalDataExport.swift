import Foundation
import SwiftData

/// Versioned, non-destructive export of all eight local tables, including archived
/// catalog items and active workouts. JSON snapshots remain byte-for-byte intact
/// as Base64 data; stable IDs and absolute dates retain their original values.
/// This is an export format, not an implemented in-app restore protocol.
struct LocalDataExport: Codable, Sendable {
    let formatVersion: Int
    let exportedAt: Date
    let timeZoneIdentifier: String
    let appVersion: String
    let preferences: Preferences?
    struct Preferences: Codable, Sendable {
        let goals: NutritionGoals?
        let appearance: String
        var scoring: ScoringConfiguration? = nil
        var energyHistory: [EnergyExpenditureRecord]? = nil
    }
    let foodEntries: [Entry]
    let savedFoods: [Food]
    let savedMeals: [Meal]
    let exercises: [Exercise]
    let routines: [Routine]
    let strengthSessions: [Strength]
    let cardioSessions: [Cardio]
    let manualWeights: [Weight]

    struct Entry: Codable, Sendable {
        let id: UUID
        let loggedAt: Date
        let name: String
        let calories, proteinGrams, carbohydrateGrams, fatGrams, quantity: Double
        let unitRaw: String
        let referenceSnapshot: Data?
        let sourceID: UUID?
        let sourceKind: String?
        let mealCategoryRaw: String?
    }
    struct Food: Codable, Sendable {
        let id: UUID
        let name: String
        let definitionData: Data
        let useCount: Int
        let lastUsedAt: Date?
    }
    struct Meal: Codable, Sendable {
        let id: UUID
        let name, kindRaw: String
        let servings: Double
        let ingredientsData: Data
        let useCount: Int
        let lastUsedAt: Date?
    }
    struct Exercise: Codable, Sendable { let id: UUID; let name: String; let snapshotData: Data }
    struct Routine: Codable, Sendable { let id: UUID; let name: String; let exercisesData: Data }
    struct Strength: Codable, Sendable {
        let id: UUID
        let name: String
        let start: Date
        let statusRaw: String
        let draftData: Data
    }
    struct Cardio: Codable, Sendable { let id: UUID; let start: Date; let activityRaw: String; let draftData: Data }
    struct Weight: Codable, Sendable { let id: UUID; let date: Date; let kilograms: Double }

    var recordCount: Int {
        foodEntries.count + savedFoods.count + savedMeals.count + exercises.count + routines.count
            + strengthSessions.count + cardioSessions.count + manualWeights.count
    }

    /// Capture synchronously on the context's actor; encoding and file selection
    /// happen afterward. No deletes, saves, migrations, Health reads or network.
    @MainActor
    static func capture(context: ModelContext, now: Date = .now,
                        timeZone: TimeZone = .current, appVersion: String? = nil,
                        preferencesDefaults: UserDefaults? = nil) throws -> Self {
        Self(formatVersion: 3, exportedAt: now, timeZoneIdentifier: timeZone.identifier,
             appVersion: appVersion ?? Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "Unknown",
             preferences: try exportPreferences(defaults: preferencesDefaults ?? GoalPreferences.currentDefaults),
             foodEntries: try context.fetch(FetchDescriptor<FoodEntry>()).map {
                 Entry(id: $0.id, loggedAt: $0.loggedAt, name: $0.name, calories: $0.calories,
                       proteinGrams: $0.proteinGrams, carbohydrateGrams: $0.carbohydrateGrams,
                       fatGrams: $0.fatGrams, quantity: $0.quantity, unitRaw: $0.unitRaw,
                       referenceSnapshot: $0.referenceSnapshot, sourceID: $0.sourceID,
                       sourceKind: $0.sourceKind, mealCategoryRaw: $0.mealCategoryRaw)
             },
             savedFoods: try context.fetch(FetchDescriptor<SavedFood>()).map {
                 Food(id: $0.id, name: $0.name, definitionData: $0.definitionData, useCount: $0.useCount, lastUsedAt: $0.lastUsedAt)
             },
             savedMeals: try context.fetch(FetchDescriptor<SavedMeal>()).map {
                 Meal(id: $0.id, name: $0.name, kindRaw: $0.kindRaw, servings: $0.servings,
                      ingredientsData: $0.ingredientsData, useCount: $0.useCount, lastUsedAt: $0.lastUsedAt)
             },
             exercises: try context.fetch(FetchDescriptor<ExerciseRecord>()).map {
                 Exercise(id: $0.id, name: $0.name, snapshotData: $0.snapshotData)
             },
             routines: try context.fetch(FetchDescriptor<WorkoutRoutine>()).map {
                 Routine(id: $0.id, name: $0.name, exercisesData: $0.exercisesData)
             },
             strengthSessions: try context.fetch(FetchDescriptor<StrengthSession>()).map {
                 Strength(id: $0.id, name: $0.name, start: $0.start, statusRaw: $0.statusRaw, draftData: $0.draftData)
             },
             cardioSessions: try context.fetch(FetchDescriptor<CardioSession>()).map {
                 Cardio(id: $0.id, start: $0.start, activityRaw: $0.activityRaw, draftData: $0.draftData)
             },
             manualWeights: try context.fetch(FetchDescriptor<ManualWeight>()).map {
                 Weight(id: $0.id, date: $0.date, kilograms: $0.kilograms)
             })
    }

    @MainActor
    private static func exportPreferences(defaults: UserDefaults?) throws -> Preferences {
        let goals = try GoalPreferences.saved(defaults: defaults)
        let appearance = defaults?.string(forKey: GoalPreferences.appearanceKey) ?? "dark"
        guard ["dark", "light", "system"].contains(appearance) else { throw CocoaError(.coderReadCorrupt) }
        return Preferences(goals: goals, appearance: appearance, scoring: try ScoringPreferences.saved(defaults: defaults), energyHistory: try ScoringPreferences.savedHistory(defaults: defaults))
    }

    func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .secondsSince1970
        return try encoder.encode(self)
    }

    /// Used to verify exported files, never to import into the current database.
    static func decode(_ data: Data) throws -> Self {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        let export = try decoder.decode(Self.self, from: data)
        guard [1, 2, 3].contains(export.formatVersion) else {
            throw CocoaError(.coderReadCorrupt, userInfo: [NSLocalizedDescriptionKey: "Unsupported export format version."])
        }
        if export.formatVersion >= 2 && export.preferences == nil { throw CocoaError(.coderReadCorrupt) }
        if let preferences = export.preferences {
            _ = try preferences.goals?.validated()
            _ = try preferences.scoring?.validated()
            _ = try preferences.energyHistory?.map { try $0.validated() }
            guard ["dark", "light", "system"].contains(preferences.appearance) else { throw CocoaError(.coderReadCorrupt) }
        }
        return export
    }
}
