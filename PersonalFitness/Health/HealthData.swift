import Foundation

// The Health adapter shares the pure calculation engine's day-window type.
typealias HealthDayWindow = LocalDayWindow

enum HealthServiceError: Error { case unavailable }
enum HealthReadIssue: String, Equatable, Sendable {
    case queryFailed = "Could not read this data. Check Apple Health access and try again."
    case deviceLocked = "Health data is temporarily inaccessible. Unlock your iPhone and refresh."
    case invalidValue = "Apple Health returned an unusable measurement."
}

enum HealthReading<Value: Sendable>: Sendable {
    case value(Value)
    case unavailable
    case failed(HealthReadIssue)

    var value: Value? {
        if case .value(let value) = self { return value }
        return nil
    }

    var issue: HealthReadIssue? {
        if case .failed(let issue) = self { return issue }
        return nil
    }
}

struct HealthWorkout: Identifiable, Sendable {
    let id: UUID
    let title: String
    let start: Date
    let end: Date
    let durationSeconds: Double?
    var activity: WorkoutActivity = .other
    // Workout energy is intentionally absent from expenditure calculations.
}

struct HealthDaySnapshot: Sendable {
    let window: HealthDayWindow
    let refreshedAt: Date
    let resting: HealthReading<Double>
    let active: HealthReading<Double>
    let steps: HealthReading<Double>
    let workouts: HealthReading<[HealthWorkout]>
    let weight: HealthReading<Double>

    var issues: [HealthReadIssue] {
        [resting.issue, active.issue, steps.issue, workouts.issue, weight.issue].compactMap { $0 }
    }
}

@MainActor
protocol HealthDataReading {
    var isAvailable: Bool { get }
    /// Local request-flow bookkeeping, never an assertion about read permissions.
    var hasCompletedRequest: Bool { get }
    func requestReadAccess() async throws
    func readDay(_ window: HealthDayWindow) async -> HealthDaySnapshot
}

// Adapter only: the reconciliation engine has no HealthKit dependency.
extension HealthReading where Value == Double {
    var calorieReading: CalorieReading {
        switch self {
        case .value(let value): return .value(value)
        case .unavailable: return .missing
        case .failed: return .failed
        }
    }
}

extension HealthDaySnapshot {
    var energyAggregates: [EnergyAggregate] {
        [EnergyAggregate(kind: .resting, reading: resting.calorieReading, window: window),
         EnergyAggregate(kind: .active, reading: active.calorieReading, window: window)]
    }
}

extension HealthWorkout {
    var recordSummary: WorkoutRecordSummary {
        WorkoutRecordSummary(id: id, activity: activity, start: start, end: end)
    }
    static func uniqueRecords(_ records: [Self]) -> [Self] {
        var byID = [UUID: Self]()
        for record in records where byID[record.id] == nil { byID[record.id] = record }
        return WorkoutReconciliation.unique(records.map(\.recordSummary)).compactMap { byID[$0.id] }
    }
}

@MainActor
protocol HealthHistoryReading: HealthDataReading {
    func readWeights(start: Date, end: Date) async -> HealthReading<[WeightObservation]>
}

/// Separate opt-in so an existing Health connection never silently adds sleep.
@MainActor
protocol SleepDataReading {
    var isAvailable: Bool { get }
    var hasCompletedSleepRequest: Bool { get }
    func requestSleepAccess() async throws
    func readSleep(start: Date, end: Date) async -> HealthReading<[SleepRecord]>
}
