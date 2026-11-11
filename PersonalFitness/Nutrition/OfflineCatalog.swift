import Foundation
import CryptoKit

/// Optional JSON metadata, never an extra SwiftData schema/table. Baseline excludes
/// this metadata to avoid recursion and enables a field-by-field three-way merge.
struct CatalogOrigin: Codable, Equatable {
    var source: String
    var recordID: String
    var release: String
    var license: String
    var url: String
    var attribution: String
    var quality: String
    var baseline: Data?
    var archived = false
    var userModified = false
}

struct CatalogServing: Codable, Equatable {
    var amount: Double
    var unitDescription: String
    var gramWeight: Double
    var label: String { "\(NutritionNumber.text(amount)) \(unitDescription) (\(NutritionNumber.text(gramWeight)) g)" }
}

struct CatalogSource: Codable, Equatable {
    var id: String
    var name: String
    var url: String
    var license: String
    var licenseURL: String
    var attribution: String
    var downloadURL: String
    var sha256: String
}
struct CatalogFood: Codable {
    var id: UUID
    var recordID: String
    var quality: String
    var definition: FoodDefinition
}
struct CatalogExercise: Codable {
    var id: UUID
    var recordID: String
    var quality: String
    var exercise: ExerciseSnapshot
}
struct OfflineCatalog: Codable {
    var schemaVersion: Int
    var release: String
    var source: CatalogSource
    var foods: [CatalogFood]
    var exercises: [CatalogExercise]

    func validated() throws -> Self {
        guard schemaVersion == 1, !release.isEmpty, !source.id.isEmpty,
              !source.name.isEmpty, !source.attribution.isEmpty,
              ["CC0-1.0", "Unlicense"].contains(source.license),
              [source.url, source.licenseURL, source.downloadURL].allSatisfy({ URL(string: $0)?.scheme == "https" }),
              source.sha256.count == 64, source.sha256.allSatisfy({ $0.isHexDigit }),
              !foods.isEmpty || !exercises.isEmpty else { throw CatalogError.invalid }
        let ids = foods.map(\.id) + exercises.map(\.id)
        guard Set(ids).count == ids.count else { throw CatalogError.invalid }
        for item in foods {
            _ = try item.definition.validated()
            guard item.id == CatalogIdentity.id(source: source.id, record: item.recordID),
                  !item.recordID.isEmpty, !item.quality.isEmpty, item.definition.catalog == nil,
                  item.definition.referenceQuantity == 100, item.definition.referenceUnit == .grams,
                  item.definition.sourceServings?.allSatisfy({ $0.amount.isFinite && $0.amount > 0 && $0.gramWeight.isFinite && $0.gramWeight > 0 && !$0.unitDescription.isEmpty }) ?? true else { throw CatalogError.invalid }
        }
        for item in exercises {
            _ = try item.exercise.validated()
            guard item.id == item.exercise.id, item.id == CatalogIdentity.id(source: source.id, record: item.recordID),
                  !item.recordID.isEmpty, !item.quality.isEmpty, item.exercise.catalog == nil,
                  !(item.exercise.instructions ?? []).contains(where: { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) else { throw CatalogError.invalid }
        }
        return self
    }
    func origin(record: String, quality: String, baseline: Data) -> CatalogOrigin {
        CatalogOrigin(source: source.id, recordID: record, release: release, license: source.license,
            url: source.url, attribution: source.attribution, quality: quality, baseline: baseline)
    }
}

enum CatalogError: LocalizedError {
    case invalid, missingResource, collision
    var errorDescription: String? {
        switch self {
        case .invalid: return "The bundled library failed validation. Your existing records were not reset."
        case .missingResource: return "The offline library resource is missing. Reinstall the update over this app, without deleting it."
        case .collision: return "A catalog identifier conflicts with an existing record. Existing records were preserved."
        }
    }
}

enum CatalogIdentity {
    /// RFC 4122 UUIDv5, matching Python's uuid.uuid5 in the reproducible generator.
    static func id(source: String, record: String) -> UUID {
        var namespace = UUID(uuidString: "655a7fd8-53dc-5b1e-95c1-dd6d769dce49")!.uuid
        let data = withUnsafeBytes(of: &namespace) { Data($0) } + Data((source + "|" + record).utf8)
        var bytes = Array(Insecure.SHA1.hash(data: data).prefix(16))
        bytes[6] = (bytes[6] & 0x0f) | 0x50; bytes[8] = (bytes[8] & 0x3f) | 0x80
        return UUID(uuid: (bytes[0],bytes[1],bytes[2],bytes[3],bytes[4],bytes[5],bytes[6],bytes[7],bytes[8],bytes[9],bytes[10],bytes[11],bytes[12],bytes[13],bytes[14],bytes[15]))
    }
}

enum CatalogSearch {
    static func matches(_ query: String, name: String, aliases: [String] = []) -> Bool {
        let tokens = query.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .components(separatedBy: .alphanumerics.inverted).filter { !$0.isEmpty }
        let text = ([name] + aliases).joined(separator: " ").folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
        return tokens.allSatisfy { text.contains($0) }
    }
}

/// Refresh catalog-owned fields only when they still equal the last shipped value.
/// User-modified fields and archive tombstones always win; historical snapshots
/// aren't passed to this function and can never be rewritten by a catalog update.
enum CatalogMerge {
    static func food(current: FoodDefinition, incoming: FoodDefinition, origin: CatalogOrigin) throws -> FoodDefinition {
        guard let oldOrigin = current.catalog, let data = oldOrigin.baseline else { return current }
        let old = try JSONDecoder().decode(FoodDefinition.self, from: data)
        var result = current
        func adopt<T: Equatable>(_ path: WritableKeyPath<FoodDefinition,T>) {
            if current[keyPath: path] == old[keyPath: path] { result[keyPath: path] = incoming[keyPath: path] }
        }
        adopt(\.name); adopt(\.preparation)
        // Treat the complete nutrition/serving basis as one unit: never apply new
        // per-100g macros to a user's edited reference portion, or vice versa.
        if current.nutrients == old.nutrients && current.referenceQuantity == old.referenceQuantity && current.referenceUnit == old.referenceUnit && current.equivalents == old.equivalents && current.sourceServings == old.sourceServings {
            result.nutrients = incoming.nutrients; result.referenceQuantity = incoming.referenceQuantity
            result.referenceUnit = incoming.referenceUnit; result.equivalents = incoming.equivalents; result.sourceServings = incoming.sourceServings
        }
        adopt(\.aliases)
        result.catalog = origin; result.catalog?.archived = oldOrigin.archived
        let modified = stripped(result) != stripped(incoming)
        result.catalog?.userModified = modified
        return try result.validated()
    }
    static func exercise(current: ExerciseSnapshot, incoming: ExerciseSnapshot, origin: CatalogOrigin) throws -> ExerciseSnapshot {
        guard let data = current.catalog?.baseline else { return current }
        let old = try JSONDecoder().decode(ExerciseSnapshot.self, from: data)
        var result = current
        func adopt<T: Equatable>(_ path: WritableKeyPath<ExerciseSnapshot,T>) {
            if current[keyPath: path] == old[keyPath: path] { result[keyPath: path] = incoming[keyPath: path] }
        }
        adopt(\.name); adopt(\.notes); adopt(\.category); adopt(\.muscleGroup); adopt(\.bodyweight)
        adopt(\.equipment); adopt(\.movementType); adopt(\.aliases); adopt(\.primaryMuscles); adopt(\.secondaryMuscles); adopt(\.instructions)
        result.catalog = origin; result.catalog?.archived = current.catalog?.archived ?? false
        let modified = stripped(result) != stripped(incoming)
        result.catalog?.userModified = modified
        return try result.validated()
    }
    static func stripped(_ definition: FoodDefinition) -> FoodDefinition { var copy = definition; copy.catalog = nil; return copy }
    static func stripped(_ exercise: ExerciseSnapshot) -> ExerciseSnapshot { var copy = exercise; copy.catalog = nil; return copy }
}
