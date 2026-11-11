import Foundation
import SwiftData

/// Owns the complete local schema. Opening failures propagate to the app's error
/// screen; never replace an unreadable personal store with an empty database.
/// The URL and in-memory options isolate persistence tests from the user's data.
@MainActor
enum AppPersistence {
    static func makeContainer(inMemory: Bool = false, url: URL? = nil) throws -> ModelContainer {
        let schema = Schema([FoodEntry.self, SavedFood.self, SavedMeal.self, ExerciseRecord.self, WorkoutRoutine.self, StrengthSession.self, CardioSession.self, ManualWeight.self])
        if let url {
            return try ModelContainer(for: schema, configurations: [
                ModelConfiguration(schema: schema, url: url, cloudKitDatabase: .none)
            ])
        }
        let configuration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: inMemory,
            cloudKitDatabase: .none
        )
        return try ModelContainer(for: schema, configurations: [configuration])
    }
}
