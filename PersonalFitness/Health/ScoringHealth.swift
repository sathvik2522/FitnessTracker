import Foundation
import HealthKit

struct HealthLoadDay: Sendable {
    let window: LocalDayWindow
    let active: HealthReading<Double>
    let workouts: HealthReading<[HealthWorkout]>
}
struct RecoveryReadings: Sendable {
    let hrv: HealthReading<[RecoverySample]>
    let restingHR: HealthReading<[RecoverySample]>
}
@MainActor protocol ScoringHealthReading {
    var isAvailable: Bool { get }
    var hasCompletedRequest: Bool { get }
    var hasCompletedRecoveryRequest: Bool { get }
    func requestRecoveryAccess() async throws
    func readRecovery(start: Date, end: Date) async -> RecoveryReadings
    func readLoadHistory(windows: [LocalDayWindow]) async -> [HealthLoadDay]
}

extension HealthKitService: ScoringHealthReading {
    static var recoveryReadTypes: Set<HKObjectType> {
        [HKQuantityType(.heartRateVariabilitySDNN), HKQuantityType(.restingHeartRate)]
    }
    var hasCompletedRecoveryRequest: Bool { defaults.bool(forKey: "health.recoveryReadRequestCompleted.v1") }
    func requestRecoveryAccess() async throws {
        guard isAvailable else { throw HealthServiceError.unavailable }
        try await store.requestAuthorization(toShare: [], read: Self.recoveryReadTypes)
        defaults.set(true, forKey: "health.recoveryReadRequestCompleted.v1")
    }
    func readRecovery(start: Date, end: Date) async -> RecoveryReadings {
        guard isAvailable, hasCompletedRecoveryRequest, end > start else {
            return RecoveryReadings(hrv: .unavailable, restingHR: .unavailable)
        }
        async let hrv = recoveryQuantities(.heartRateVariabilitySDNN, unit: .secondUnit(with: .milli), start: start, end: end)
        async let resting = recoveryQuantities(.restingHeartRate, unit: HKUnit.count().unitDivided(by: .minute()), start: start, end: end)
        return await RecoveryReadings(hrv: hrv, restingHR: resting)
    }
    private func recoveryQuantities(_ identifier: HKQuantityTypeIdentifier, unit: HKUnit, start: Date, end: Date) async -> HealthReading<[RecoverySample]> {
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate)
        let query = HKSampleQueryDescriptor(predicates: [.quantitySample(type: HKQuantityType(identifier), predicate: predicate)], sortDescriptors: [SortDescriptor(\HKQuantitySample.startDate)])
        do {
            let samples = try await query.result(for: store)
            let converted = samples.compactMap { sample -> RecoverySample? in
                guard sample.startDate >= start, sample.startDate < end, sample.endDate <= end,
                      case .value(let value) = Self.measurement(sample.quantity, unit: unit, strictlyPositive: true) else { return nil }
                return RecoverySample(id: sample.uuid, date: sample.startDate, value: value,
                    source: sample.sourceRevision.source.bundleIdentifier + " / " + (sample.device?.model ?? "device unspecified") + " / " + (sample.device?.hardwareVersion ?? "hardware unspecified"))
            }
            if !samples.isEmpty && converted.isEmpty { return .failed(.invalidValue) }
            return converted.isEmpty ? .unavailable : .value(converted)
        } catch { return Self.queryFailure(error) }
    }
    func readLoadHistory(windows: [LocalDayWindow]) async -> [HealthLoadDay] {
        guard isAvailable, hasCompletedRequest else { return [] }
        // Exact calendar windows preserve 23/25-hour days. No source subtotals,
        // workout calories or daily averages are added to cumulative energy.
        var days: [HealthLoadDay] = []
        for window in windows {
            guard !Task.isCancelled else { return [] }
            async let active = cumulative(.activeEnergyBurned, unit: .kilocalorie(), window: window)
            async let workouts = readWorkouts(window)
            days.append(await HealthLoadDay(window: window, active: active, workouts: workouts))
        }
        return days
    }
}
