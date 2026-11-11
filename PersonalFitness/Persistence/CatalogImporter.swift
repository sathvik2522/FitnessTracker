import Foundation
import SwiftData

struct CatalogImportResult: Sendable {
    var inserted = 0
    var updated = 0
    var unchanged = 0
}

/// Created off the main actor. Each batch is durable and a failed/interrupted
/// import can be retried: IDs, baselines and archive flags live in the same rows.
/// It never opens a different store or mutates diary/meal/routine/session models.
@ModelActor
actor CatalogImporter {
    func run(urls: [URL]) async throws -> CatalogImportResult {
        let catalogs = try urls.map { try JSONDecoder().decode(OfflineCatalog.self, from: Data(contentsOf: $0)).validated() }
        return try await run(catalogs: catalogs)
    }
    func run(catalogs: [OfflineCatalog]) async throws -> CatalogImportResult {
        let catalogs = try catalogs.map { try $0.validated() }
        let ids = catalogs.flatMap { $0.foods.map(\.id) + $0.exercises.map(\.id) }
        guard Set(ids).count == ids.count else { throw CatalogError.invalid }
        modelContext.autosaveEnabled = false
        let foods = Dictionary(uniqueKeysWithValues: try modelContext.fetch(FetchDescriptor<SavedFood>()).map { ($0.id,$0) })
        let exercises = Dictionary(uniqueKeysWithValues: try modelContext.fetch(FetchDescriptor<ExerciseRecord>()).map { ($0.id,$0) })
        // Preflight every collision before any save. A custom record sharing an
        // ID is never silently adopted as catalog-owned or overwritten.
        for catalog in catalogs {
            for item in catalog.foods {
                if let existing = foods[item.id] {
                    let origin = try existing.definition().catalog
                    guard origin?.source == catalog.source.id, origin?.recordID == item.recordID else { throw CatalogError.collision }
                }
            }
            for item in catalog.exercises {
                if let existing = exercises[item.id] {
                    let origin = try existing.snapshot().catalog
                    guard origin?.source == catalog.source.id, origin?.recordID == item.recordID else { throw CatalogError.collision }
                }
            }
        }
        var result = CatalogImportResult(), pending = 0
        do {
            for catalog in catalogs {
                for item in catalog.foods {
                    try Task.checkCancellation()
                    let baseline = try JSONEncoder().encode(item.definition)
                    let origin = catalog.origin(record: item.recordID, quality: item.quality, baseline: baseline)
                    if let existing = foods[item.id] {
                        let current = try existing.definition()
                        if current.catalog?.release == catalog.release { result.unchanged += 1; continue }
                        let merged = try CatalogMerge.food(current: current, incoming: item.definition, origin: origin)
                        existing.name = merged.name; existing.definitionData = try JSONEncoder().encode(merged)
                        result.updated += 1
                    } else {
                        var definition = item.definition; definition.catalog = origin
                        modelContext.insert(try SavedFood(id: item.id, definition: definition)); result.inserted += 1
                    }
                    pending += 1
                    if pending == 100 { try modelContext.save(); pending = 0; await Task.yield() }
                }
                for item in catalog.exercises {
                    try Task.checkCancellation()
                    let baseline = try JSONEncoder().encode(item.exercise)
                    let origin = catalog.origin(record: item.recordID, quality: item.quality, baseline: baseline)
                    if let existing = exercises[item.id] {
                        let current = try existing.snapshot()
                        if current.catalog?.release == catalog.release { result.unchanged += 1; continue }
                        let merged = try CatalogMerge.exercise(current: current, incoming: item.exercise, origin: origin)
                        existing.name = merged.name; existing.snapshotData = try JSONEncoder().encode(merged)
                        result.updated += 1
                    } else {
                        var exercise = item.exercise; exercise.catalog = origin
                        modelContext.insert(try ExerciseRecord(exercise)); result.inserted += 1
                    }
                    pending += 1
                    if pending == 100 { try modelContext.save(); pending = 0; await Task.yield() }
                }
            }
            try modelContext.save()
            return result
        } catch { modelContext.rollback(); throw error }
    }
}

/// Search/archive helpers keep bundled and personal records in existing pickers.
/// Deleted catalog items remain hidden tombstones, including after app relaunch.
extension SavedFood {
    var libraryVisible: Bool { (try? definition().catalog?.archived) != true }
    func matchesLibrary(_ query: String) -> Bool {
        guard let definition = try? definition() else { return CatalogSearch.matches(query, name: name) }
        guard definition.catalog?.archived != true else { return false }
        return query.isEmpty || CatalogSearch.matches(query, name: name, aliases: definition.aliases ?? [])
    }
}
extension ExerciseRecord {
    var libraryVisible: Bool { (try? snapshot().catalog?.archived) != true }
    func matchesLibrary(_ query: String) -> Bool {
        guard let exercise = try? snapshot() else { return CatalogSearch.matches(query, name: name) }
        guard exercise.catalog?.archived != true else { return false }
        return query.isEmpty || CatalogSearch.matches(query, name: name, aliases: exercise.aliases ?? [])
    }
    var librarySourceLabel: String {
        guard let exercise = try? snapshot() else { return "Definition unavailable" }
        if let origin = exercise.catalog { return origin.userModified ? "Catalog · personally edited" : "Free Exercise DB · offline" }
        return exercise.builtInKey != nil ? "Starter exercise" : "Custom exercise"
    }
}
