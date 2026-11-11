import Foundation

/// Round only at presentation, consistently to the nearest whole kcal, ties away
/// from zero. Normalize negative zero; calculations retain their full precision.
enum EnergyDisplay {
    static func roundedKilocalories(_ value: Double) -> Double {
        let rounded = value.rounded(.toNearestOrAwayFromZero)
        return rounded == 0 ? 0 : rounded
    }

    static func kilocalories(_ value: Double?, locale: Locale = .current) -> String {
        guard let value, value.isFinite else { return "Unavailable" }
        return roundedKilocalories(value).formatted(.number.precision(.fractionLength(0)).locale(locale))
    }

    static func balanceTitle(_ value: Double?) -> String {
        guard let value, value.isFinite else { return "Estimated deficit / surplus" }
        if value == 0 { return "Estimated balance" }
        if roundedKilocalories(value) == 0 { return "Approximately balanced" }
        return value < 0 ? "Estimated deficit" : "Estimated surplus"
    }
}
