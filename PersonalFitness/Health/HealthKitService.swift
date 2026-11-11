import Foundation
import HealthKit

/// Read-only Apple Health adapter. Authorization is a separate user action;
/// refreshing a day never presents a permission sheet. Query results remain
/// in memory and are not imported into the manual workout or nutrition store.
@MainActor
final class HealthKitService: HealthHistoryReading, SleepDataReading {
    let store: HKHealthStore
    let defaults: UserDefaults
    private static let requestKey = "health.readRequestCompleted.v1"

    init(store: HKHealthStore = HKHealthStore(), defaults: UserDefaults = .standard) {
        self.store = store
        self.defaults = defaults
    }

    var isAvailable: Bool { HealthAvailability.isSupported }
    /// Records completion of the permission flow, not permission to read.
    /// HealthKit intentionally hides whether a missing reading was denied.
    var hasCompletedRequest: Bool { defaults.bool(forKey: Self.requestKey) }

    static var readTypes: Set<HKObjectType> {
        Set([HKObjectType.quantityType(forIdentifier: .basalEnergyBurned)!,
             HKObjectType.quantityType(forIdentifier: .activeEnergyBurned)!,
             HKObjectType.quantityType(forIdentifier: .stepCount)!,
             HKObjectType.quantityType(forIdentifier: .bodyMass)!,
             HKObjectType.workoutType()])
    }

    func requestReadAccess() async throws {
        guard isAvailable else { throw HealthServiceError.unavailable }
        try await store.requestAuthorization(toShare: [], read: Self.readTypes)
        // Completion means the request flow finished, even if every read was refused.
        defaults.set(true, forKey: Self.requestKey)
    }

    static var sleepReadTypes: Set<HKObjectType> { [HKCategoryType(.sleepAnalysis)] }

    var hasCompletedSleepRequest: Bool { defaults.bool(forKey: "health.sleepReadRequestCompleted.v1") }

    func requestSleepAccess() async throws {
        guard isAvailable else { throw HealthServiceError.unavailable }
        try await store.requestAuthorization(toShare: [], read: Self.sleepReadTypes)
        defaults.set(true, forKey: "health.sleepReadRequestCompleted.v1")
    }

    static func sleepDescriptor(start: Date, end: Date) -> HKSampleQueryDescriptor<HKCategorySample> {
        // Overlap predicate includes sessions beginning before the requested window.
        HKSampleQueryDescriptor(predicates: [.categorySample(type: HKCategoryType(.sleepAnalysis),
            predicate: HKQuery.predicateForSamples(withStart: start, end: end, options: []))],
            sortDescriptors: [SortDescriptor(\HKCategorySample.startDate)])
    }

    static func sleepRecord(_ sample: HKCategorySample) -> SleepRecord? {
        let kind: SleepRecord.Kind
        switch HKCategoryValueSleepAnalysis(rawValue: sample.value) {
        case .asleepUnspecified, .asleepCore, .asleepDeep, .asleepREM: kind = .asleep
        case .inBed: kind = .inBed
        case .awake: kind = .awake
        default: return nil
        }
        return SleepRecord(id: sample.uuid, start: sample.startDate, end: sample.endDate, kind: kind, sourceName: sample.sourceRevision.source.name)
    }

    func readSleep(start: Date, end: Date) async -> HealthReading<[SleepRecord]> {
        guard isAvailable, hasCompletedSleepRequest, end > start else { return .unavailable }
        do {
            let samples = try await Self.sleepDescriptor(start: start, end: end).result(for: store)
            let records = samples.compactMap(Self.sleepRecord)
            return records.isEmpty ? .unavailable : .value(records)
        } catch { return Self.queryFailure(error) }
    }

    func readDay(_ window: HealthDayWindow) async -> HealthDaySnapshot {
        guard isAvailable, hasCompletedRequest, window.end > window.start else {
            return HealthDaySnapshot(window: window, refreshedAt: .now,
                                     resting: .unavailable, active: .unavailable, steps: .unavailable,
                                     workouts: .unavailable, weight: .unavailable)
        }
        async let resting = cumulative(.basalEnergyBurned, unit: .kilocalorie(), window: window)
        async let active = cumulative(.activeEnergyBurned, unit: .kilocalorie(), window: window)
        async let steps = cumulative(.stepCount, unit: .count(), window: window)
        async let workouts = readWorkouts(window)
        async let weight = readWeight(window)
        return await HealthDaySnapshot(window: window, refreshedAt: .now,
                                       resting: resting, active: active, steps: steps,
                                       workouts: workouts, weight: weight)
    }

    /// One aggregate over the precise shared day/cutoff predicate. HealthKit
    /// supplies the statistic; we never sum source subtotals or workouts. This
    /// cannot certify the absence of duplicate records written by other apps;
    /// source priority and sample provenance remain HealthKit/Health concerns.
    static func cumulativeDescriptor(_ identifier: HKQuantityTypeIdentifier,
                                     window: HealthDayWindow) throws -> HKStatisticsQueryDescriptor {
        guard window.end > window.start else { throw LocalDayWindow.WindowError.invalidDay }
        let type = HKObjectType.quantityType(forIdentifier: identifier)!
        let predicate = HKQuery.predicateForSamples(withStart: window.start, end: window.end, options: [])
        return HKStatisticsQueryDescriptor(
            predicate: .quantitySample(type: type, predicate: predicate), options: .cumulativeSum
        )
    }

    func cumulative(_ identifier: HKQuantityTypeIdentifier, unit: HKUnit,
                            window: HealthDayWindow) async -> HealthReading<Double> {
        do {
            let statistics = try await Self.cumulativeDescriptor(identifier, window: window).result(for: store)
            let quantity = statistics?.sumQuantity()
            return Self.measurement(quantity, unit: unit)
        } catch { return Self.queryFailure(error) }
    }

    private func readWeight(_ window: HealthDayWindow) async -> HealthReading<Double> {
        let query = Self.weightDescriptor(window)
        do {
            let sample = try await query.result(for: store).first
            return Self.measurement(sample?.quantity, unit: .gramUnit(with: .kilo), strictlyPositive: true)
        } catch { return Self.queryFailure(error) }
    }

    func readWorkouts(_ window: HealthDayWindow) async -> HealthReading<[HealthWorkout]> {
        // Attribute a workout to the local day it started, even if it spans midnight.
        let query = HKSampleQueryDescriptor(predicates: [.workout(Self.samplePredicate(window))],
                                            sortDescriptors: [SortDescriptor(\HKWorkout.startDate)])
        do {
            let samples = try await query.result(for: store)
            // An empty read cannot distinguish no workouts from hidden samples.
            guard !samples.isEmpty else { return .unavailable }
            return .value(HealthWorkout.uniqueRecords(samples.map(Self.workout)))
        } catch { return Self.queryFailure(error) }
    }

    func readWeights(start: Date, end: Date) async -> HealthReading<[WeightObservation]> {
        guard isAvailable, hasCompletedRequest, end > start else { return .unavailable }
        let type = HKObjectType.quantityType(forIdentifier: .bodyMass)!
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate)
        let query = HKSampleQueryDescriptor(predicates: [.quantitySample(type: type, predicate: predicate)],
            sortDescriptors: [SortDescriptor(\HKQuantitySample.startDate)])
        do {
            let samples = try await query.result(for: store)
            var seen = Set<UUID>()
            var weights: [WeightObservation] = []
            for sample in samples where sample.startDate >= start && sample.startDate < end && seen.insert(sample.uuid).inserted {
                guard case .value(let kg) = Self.measurement(sample.quantity, unit: .gramUnit(with: .kilo), strictlyPositive: true) else {
                    return .failed(.invalidValue)
                }
                weights.append(WeightObservation(id: sample.uuid, date: sample.startDate, kilograms: kg, origin: .health))
            }
            return weights.isEmpty ? .unavailable : .value(weights)
        } catch { return Self.queryFailure(error) }
    }

    static func samplePredicate(_ window: HealthDayWindow) -> NSPredicate {
        HKQuery.predicateForSamples(withStart: window.start, end: window.end, options: .strictStartDate)
    }

    static func weightDescriptor(_ window: HealthDayWindow) -> HKSampleQueryDescriptor<HKQuantitySample> {
        HKSampleQueryDescriptor(predicates: [.quantitySample(
            type: HKObjectType.quantityType(forIdentifier: .bodyMass)!, predicate: samplePredicate(window))],
            sortDescriptors: [SortDescriptor(\HKQuantitySample.startDate, order: .reverse)], limit: 1)
    }

    static func measurement(_ quantity: HKQuantity?, unit: HKUnit,
                            strictlyPositive: Bool = false) -> HealthReading<Double> {
        guard let quantity else { return .unavailable }
        guard quantity.is(compatibleWith: unit) else { return .failed(.invalidValue) }
        let value = quantity.doubleValue(for: unit)
        guard value.isFinite, strictlyPositive ? value > 0 : value >= 0 else {
            return .failed(.invalidValue)
        }
        return .value(value)
    }

    static func queryFailure<Value>(_ error: Error) -> HealthReading<Value> {
        let error = error as NSError
        if error.domain == HKErrorDomain {
            if error.code == HKError.Code.errorNoData.rawValue { return .unavailable }
            if error.code == HKError.Code.errorDatabaseInaccessible.rawValue { return .failed(.deviceLocked) }
        }
        return .failed(.queryFailed)
    }

    static func workout(_ sample: HKWorkout) -> HealthWorkout {
        let title: String
        switch sample.workoutActivityType {
        case .traditionalStrengthTraining, .functionalStrengthTraining: title = "Strength training"
        case .running: title = "Running"
        case .walking: title = "Walking"
        case .cycling: title = "Cycling"
        case .stairClimbing: title = "Stair climbing"
        case .swimming: title = "Swimming"
        case .elliptical: title = "Elliptical"
        case .yoga: title = "Yoga"
        default: title = "Workout"
        }
        let activity = WorkoutActivity(rawValue: title) ?? .other
        let duration = sample.duration
        return HealthWorkout(id: sample.uuid, title: title, start: sample.startDate, end: sample.endDate,
                             durationSeconds: duration.isFinite && duration >= 0 ? duration : nil, activity: activity)
    }
}
