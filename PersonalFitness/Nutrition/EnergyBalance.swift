import Foundation

/// All values are kilocalories for the same local day and observation window.
/// Today's balance is provisional; it is not a forecast of the complete day.
public struct EnergyBalance: Equatable {
    public let consumed: Double?
    public let resting: Double?
    public let active: Double?

    public init(consumed: Double?, resting: Double?, active: Double?) {
        self.consumed = Self.validEnergy(consumed)
        self.resting = Self.validEnergy(resting)
        self.active = Self.validEnergy(active)
    }

    public var expenditure: Double? {
        guard let resting, let active else { return nil }
        let total = resting + active
        return total.isFinite ? total : nil
    }

    /// Positive means surplus; negative means deficit. Missing inputs stay missing.
    public var net: Double? {
        guard let consumed, let expenditure else { return nil }
        return consumed - expenditure
    }

    private static func validEnergy(_ value: Double?) -> Double? {
        guard let value, value.isFinite, value >= 0 else { return nil }
        return value
    }
}
