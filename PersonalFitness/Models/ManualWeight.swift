import Foundation
import SwiftData

@Model
final class ManualWeight {
    @Attribute(.unique) var id: UUID
    var date: Date
    var kilograms: Double
    init(id: UUID, date: Date, kilograms: Double) {
        self.id = id; self.date = date; self.kilograms = kilograms
    }
    var observation: WeightObservation { WeightObservation(id: id, date: date, kilograms: kilograms, origin: .manual) }
}
