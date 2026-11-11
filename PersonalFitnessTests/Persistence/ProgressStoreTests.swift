import XCTest
import SwiftData
@testable import PersonalFitness

final class ProgressStoreTests: XCTestCase {
    @MainActor func testManualWeightUpsertValidationDeletionAndDiskReopen() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("Progress.sqlite"), id = UUID()
        try writeWeight(url: url, id: id)
        let container = try AppPersistence.makeContainer(url: url)
        let saved = try XCTUnwrap(container.mainContext.fetch(FetchDescriptor<ManualWeight>()).first)
        XCTAssertEqual(saved.id, id); XCTAssertEqual(saved.kilograms, 81)
        XCTAssertEqual(saved.date, Date(timeIntervalSince1970: 1_700_000_000))
        let store = ProgressStore(context: container.mainContext)
        XCTAssertThrowsError(try store.saveWeight(WeightObservation(id: id, date: saved.date, kilograms: -1, origin: .manual)))
        XCTAssertThrowsError(try store.saveWeight(WeightObservation(id: id, date: saved.date, kilograms: 80, origin: .health)))
        XCTAssertEqual(saved.kilograms, 81)
        try store.deleteWeight(id: id)
        XCTAssertEqual(try container.mainContext.fetchCount(FetchDescriptor<ManualWeight>()), 0)
    }
    @MainActor private func writeWeight(url: URL, id: UUID) throws {
        let container = try AppPersistence.makeContainer(url: url)
        let store = ProgressStore(context: container.mainContext)
        for kg in [80.0, 81] {
            try store.saveWeight(WeightObservation(id: id, date: Date(timeIntervalSince1970: 1_700_000_000), kilograms: kg, origin: .manual))
        }
        XCTAssertEqual(try container.mainContext.fetchCount(FetchDescriptor<ManualWeight>()), 1)
    }
    @MainActor func testWorkoutSchemaMigrationPreservesExistingData() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("Migration.sqlite")
        try writeWorkoutSchema(url)
        let container = try AppPersistence.makeContainer(url: url)
        XCTAssertEqual(try container.mainContext.fetch(FetchDescriptor<FoodEntry>()).first?.calories, 123)
        XCTAssertEqual(try container.mainContext.fetchCount(FetchDescriptor<StrengthSession>()), 1)
        XCTAssertEqual(try container.mainContext.fetchCount(FetchDescriptor<ManualWeight>()), 0)
    }
    @MainActor private func writeWorkoutSchema(_ url: URL) throws {
        let schema = Schema([FoodEntry.self, SavedFood.self, SavedMeal.self, ExerciseRecord.self, WorkoutRoutine.self, StrengthSession.self, CardioSession.self])
        let container = try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, url: url, cloudKitDatabase: .none)])
        container.mainContext.insert(FoodEntry(name: "Preserved", calories: 123))
        container.mainContext.insert(try StrengthSession(StrengthDraft()))
        try container.mainContext.save()
    }
}
