import Foundation
import SwiftData

@Model
final class SavedFood {
    @Attribute(.unique) var id: UUID
    var name: String
    var definitionData: Data
    var useCount: Int = 0
    var lastUsedAt: Date? = nil

    init(id: UUID, definition: FoodDefinition) throws {
        self.id = id
        self.name = definition.name
        self.definitionData = try JSONEncoder().encode(definition)
    }

    func definition() throws -> FoodDefinition {
        try JSONDecoder().decode(FoodDefinition.self, from: definitionData).validated()
    }
}
