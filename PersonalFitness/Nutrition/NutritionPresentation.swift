import Foundation

/// Explicit personal preferences. No recommended targets or inferred defaults.
struct NutritionGoals: Codable, Equatable, Sendable {
    var calories: Double? = nil
    var protein: Double? = nil
    var carbohydrates: Double? = nil
    var fat: Double? = nil
    var steps: Double? = nil

    func validated() throws -> Self {
        guard [calories, protein, carbohydrates, fat, steps].compactMap({ $0 }).allSatisfy({ $0.isFinite && $0 > 0 }) else {
            throw GoalError.invalid
        }
        return self
    }
    enum GoalError: String, LocalizedError {
        case invalid = "Goals must be positive, finite numbers. Leave a field blank to remove its goal."
        var errorDescription: String? { rawValue }
    }
}

struct GoalProgress: Equatable {
    let amount: Double?
    let goal: Double?
    let fraction: Double?
    let remaining: Double?
    init(amount: Double?, goal: Double?) {
        self.amount = amount.flatMap { $0.isFinite && $0 >= 0 ? $0 : nil }
        self.goal = goal.flatMap { $0.isFinite && $0 > 0 ? $0 : nil }
        if let amount = self.amount, let goal = self.goal {
            // Divide only valid positive values; clamp infinity from extreme input
            // before it can enter any drawing geometry. Arithmetic stays unrounded.
            fraction = min(1, max(0, amount / goal))
            remaining = goal - amount
        } else { fraction = nil; remaining = nil }
    }
}

enum DashboardRingKind: String, CaseIterable, Identifiable {
    case strain = "Strain", recovery = "Recovery", balance = "Estimated Deficit"
    var id: String { rawValue }
}
struct DashboardRingState: Equatable {
    let value: String
    let unit: String
    let title: String
    let status: String
    static func make(_ kind: DashboardRingKind, balance: Double?, partial: Bool) -> Self {
        switch kind {
        case .strain: return Self(value: "Start", unit: "", title: "Strain", status: "Log activity")
        case .recovery: return Self(value: "Build", unit: "", title: "Recovery", status: "Build baseline")
        case .balance:
            guard let balance, balance.isFinite else {
                return Self(value: "—", unit: "kcal", title: "Est. balance", status: "Unavailable")
            }
            let text = EnergyDisplay.kilocalories(balance)
            return Self(value: balance > 0 && EnergyDisplay.roundedKilocalories(balance) != 0 ? "+" + text : text,
                        unit: "kcal", title: EnergyDisplay.balanceTitle(balance).replacingOccurrences(of: "Estimated", with: "Est."),
                        status: partial ? "Provisional" : "Coverage unverified")
        }
    }
}

enum FoodSearchRanking {
    /// Exact names, then name prefixes, then all-token partial/alias matches.
    /// Callers still filter archive visibility; recency is a tie-breaker only.
    static func score(name: String, aliases: [String], query: String) -> Int? {
        func folded(_ text: String) -> String {
            text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
                .components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty }.joined(separator: " ")
        }
        let q = folded(query), n = folded(name)
        if q.isEmpty { return 0 }
        if n == q { return 0 }
        if n.hasPrefix(q) { return 1 }
        if aliases.contains(where: { folded($0) == q }) { return 2 }
        return CatalogSearch.matches(query, name: name, aliases: aliases) ? 3 : nil
    }
}
