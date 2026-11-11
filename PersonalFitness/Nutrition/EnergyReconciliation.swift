import Foundation

/// Value presence is distinct from known incomplete collection and query failure.
enum CalorieReading: Equatable {
    case value(Double), missing, failed, incomplete(Double?)
}

enum InputCoverage { case unverified, complete }
enum EnergyKind { case resting, active }
enum EnergyRepresentation { case healthKitAggregate, sourceSubtotal, workout }

struct EnergyAggregate {
    let kind: EnergyKind
    let reading: CalorieReading
    let window: LocalDayWindow
    var representation: EnergyRepresentation = .healthKitAggregate
    var coverage: InputCoverage = .unverified
}

struct FoodEnergy {
    let reading: CalorieReading
    let window: LocalDayWindow
    var coverage: InputCoverage = .unverified
}

enum EnergyReason: String, Equatable {
    case dayInProgress = "This day is still in progress; values are not a full-day forecast."
    case foodMissing = "No intake is recorded; zero logged calories does not establish zero intake."
    case foodFailed = "Food calories are unavailable or invalid."
    case foodIncomplete = "Food intake is known to be incomplete."
    case foodUnverified = "The diary may not include every meal. Balance compares logged intake only."
    case restingMissing = "Resting energy is unavailable."
    case activeMissing = "Active energy is unavailable."
    case energyFailed = "A required energy reading failed or is invalid."
    case energyIncomplete = "A required energy reading is known to be incomplete."
    case coverageUnverified = "HealthKit does not establish complete energy coverage, even for a closed day."
    case mismatchedWindow = "Required inputs cover different days, cutoffs, or time zones."
    case conflictingAggregates = "Conflicting aggregate results cannot be combined safely."
    case arithmeticInvalid = "The combined calorie estimate is outside the supported numeric range."
}

enum EstimateQuality: Equatable { case unavailable, partial, available }

struct EnergyAssessment {
    let window: LocalDayWindow
    let balance: EnergyBalance
    let expenditureQuality: EstimateQuality
    let balanceQuality: EstimateQuality
    let expenditureReasons: [EnergyReason]
    let balanceReasons: [EnergyReason]

    var scopeTitle: String { window.isPartial ? "Day in progress" : "Closed historical-day window" }
}

/// Pure policy. This accepts merged HealthKit aggregates, not raw energy samples.
/// Workouts and source subtotals cannot become additional expenditure inputs.
enum EnergyReconciliation {
    static func assess(window: LocalDayWindow, food: FoodEnergy,
                       aggregates: [EnergyAggregate]) -> EnergyAssessment {
        let resting = reconcile(.resting, window: window, aggregates: aggregates)
        let active = reconcile(.active, window: window, aggregates: aggregates)
        var foodReasons: [EnergyReason] = []
        var consumed: Double?
        if food.window != window {
            foodReasons.append(.mismatchedWindow)
        } else {
            switch food.reading {
            case .value(let value):
                if valid(value) {
                    consumed = value
                    if food.coverage == .unverified { foodReasons.append(.foodUnverified) }
                } else { foodReasons.append(.foodFailed) }
            case .missing: foodReasons.append(.foodMissing)
            case .failed: foodReasons.append(.foodFailed)
            case .incomplete: foodReasons.append(.foodIncomplete)
            }
        }
        let balance = EnergyBalance(consumed: consumed, resting: resting.value, active: active.value)
        var energyReasons = resting.reasons + active.reasons
        if window.isPartial { energyReasons.append(.dayInProgress) }
        if resting.value != nil, active.value != nil, balance.expenditure == nil {
            energyReasons.append(.arithmeticInvalid)
        }
        energyReasons = unique(energyReasons)
        let balanceReasons = unique(energyReasons + foodReasons)
        return EnergyAssessment(window: window, balance: balance,
                                expenditureQuality: quality(balance.expenditure, reasons: energyReasons),
                                balanceQuality: quality(balance.net, reasons: balanceReasons),
                                expenditureReasons: energyReasons, balanceReasons: balanceReasons)
    }

    private static func reconcile(_ kind: EnergyKind, window: LocalDayWindow,
                                  aggregates: [EnergyAggregate]) -> (value: Double?, reasons: [EnergyReason]) {
        let candidates = aggregates.filter { $0.kind == kind && $0.representation == .healthKitAggregate }
        let exact = candidates.filter { $0.window == window }
        guard let first = exact.first else {
            return (nil, [candidates.isEmpty ? (kind == .resting ? .restingMissing : .activeMissing) : .mismatchedWindow])
        }
        // Identical aggregate copies are one measurement. Conflicting copies are
        // neither summed nor resolved using a guessed source or larger value.
        guard exact.allSatisfy({ $0.reading == first.reading }) else {
            return (nil, [.conflictingAggregates])
        }
        switch first.reading {
        case .value(let value):
            guard valid(value) else { return (nil, [.energyFailed]) }
            return (value, exact.allSatisfy { $0.coverage == .complete } ? [] : [.coverageUnverified])
        case .missing: return (nil, [kind == .resting ? .restingMissing : .activeMissing])
        case .failed: return (nil, [.energyFailed])
        case .incomplete: return (nil, [.energyIncomplete])
        }
    }

    private static func valid(_ value: Double) -> Bool { value.isFinite && value >= 0 }
    private static func quality(_ value: Double?, reasons: [EnergyReason]) -> EstimateQuality {
        guard value != nil else { return .unavailable }
        return reasons.isEmpty ? .available : .partial
    }
    private static func unique(_ values: [EnergyReason]) -> [EnergyReason] {
        values.reduce(into: []) { if !$0.contains($1) { $0.append($1) } }
    }
}
