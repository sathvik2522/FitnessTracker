import XCTest
import HealthKit
@testable import PersonalFitness

final class HealthKitConversionTests: XCTestCase {
    @MainActor
    func testReadTypesAreExactlyTheFiveSupportedTypes() {
        XCTAssertEqual(Set(HealthKitService.readTypes.map(\.identifier)), Set([
            HKQuantityTypeIdentifier.basalEnergyBurned.rawValue,
            HKQuantityTypeIdentifier.activeEnergyBurned.rawValue,
            HKQuantityTypeIdentifier.stepCount.rawValue,
            HKQuantityTypeIdentifier.bodyMass.rawValue,
            HKObjectType.workoutType().identifier
        ]))
    }

    @MainActor
    func testMissingIsNotZeroButMeasuredZeroIsPreserved() {
        XCTAssertNil(HealthKitService.measurement(nil, unit: .kilocalorie()).value)
        XCTAssertEqual(HealthKitService.measurement(HKQuantity(unit: .kilocalorie(), doubleValue: 0), unit: .kilocalorie()).value, 0)
        XCTAssertEqual(HealthKitService.measurement(HKQuantity(unit: .gramUnit(with: .kilo), doubleValue: 0),
                                                  unit: .gramUnit(with: .kilo), strictlyPositive: true).issue, .invalidValue)
    }

    @MainActor
    func testUnitConversionsAndIncompatibleUnits() throws {
        let energy = HKQuantity(unit: .jouleUnit(with: .kilo), doubleValue: 418.4)
        XCTAssertEqual(try XCTUnwrap(HealthKitService.measurement(energy, unit: .kilocalorie()).value), 100, accuracy: 0.001)
        let pounds = HKQuantity(unit: .pound(), doubleValue: 220.4622622)
        XCTAssertEqual(try XCTUnwrap(HealthKitService.measurement(pounds, unit: .gramUnit(with: .kilo)).value), 100, accuracy: 0.001)
        XCTAssertEqual(HealthKitService.measurement(energy, unit: .count()).issue, .invalidValue)
        XCTAssertEqual(HealthKitService.measurement(HKQuantity(unit: .count(), doubleValue: -1), unit: .count()).issue, .invalidValue)
    }

    @MainActor
    func testQueryErrorClassificationDoesNotInventReadDenialFromNoData() {
        let missing: HealthReading<Double> = HealthKitService.queryFailure(NSError(domain: HKErrorDomain, code: HKError.Code.errorNoData.rawValue))
        XCTAssertNil(missing.value)
        XCTAssertNil(missing.issue)
        let locked: HealthReading<Double> = HealthKitService.queryFailure(NSError(domain: HKErrorDomain, code: HKError.Code.errorDatabaseInaccessible.rawValue))
        XCTAssertEqual(locked.issue, .deviceLocked)
        let failed: HealthReading<Double> = HealthKitService.queryFailure(NSError(domain: HKErrorDomain, code: HKError.Code.errorAuthorizationDenied.rawValue))
        XCTAssertEqual(failed.issue, .queryFailed)
    }

    @MainActor
    func testCumulativeQueryUsesHealthKitAggregationWithoutPerSourceSums() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        let date = calendar.date(from: DateComponents(year: 2026, month: 3, day: 8))!
        let window = try HealthDayWindow(day: date, now: date.addingTimeInterval(86400 * 2), calendar: calendar)
        let query = try HealthKitService.cumulativeDescriptor(.stepCount, window: window)
        XCTAssertEqual(window.end.timeIntervalSince(window.start), 23 * 3600)
        XCTAssertEqual(query.options, .cumulativeSum)
        XCTAssertFalse(query.options.contains(.separateBySource))
    }
    @MainActor
    func testDiscreteSampleBoundariesAndLatestWeightOrdering() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let start = calendar.startOfDay(for: .now).addingTimeInterval(-86400)
        let window = try HealthDayWindow(day: start, now: .now, calendar: calendar)
        let predicate = HealthKitService.samplePredicate(window)
        let type = HKObjectType.quantityType(forIdentifier: .bodyMass)!
        func sample(_ date: Date) -> HKQuantitySample {
            HKQuantitySample(type: type, quantity: HKQuantity(unit: .gramUnit(with: .kilo), doubleValue: 70),
                             start: date, end: date)
        }
        XCTAssertFalse(predicate.evaluate(with: sample(window.start.addingTimeInterval(-1))))
        XCTAssertTrue(predicate.evaluate(with: sample(window.start)))
        XCTAssertTrue(predicate.evaluate(with: sample(window.end.addingTimeInterval(-1))))
        XCTAssertFalse(predicate.evaluate(with: sample(window.end)))
        let weight = HealthKitService.weightDescriptor(window)
        XCTAssertEqual(weight.limit, 1)
        XCTAssertEqual(weight.sortDescriptors.first?.order, .reverse)
    }

    @MainActor
    func testMidnightNeverBuildsAZeroDurationStatisticsQuery() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let midnight = calendar.startOfDay(for: .now)
        let window = try LocalDayWindow(day: midnight, now: midnight, calendar: calendar)
        XCTAssertThrowsError(try HealthKitService.cumulativeDescriptor(.activeEnergyBurned, window: window))
    }

    @MainActor
    func testCumulativePredicateUsesPreciseCutoffEvenInFirstSecondOfDay() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let start = calendar.startOfDay(for: .now), cutoff = start.addingTimeInterval(0.75)
        let window = try LocalDayWindow(day: start, now: cutoff, calendar: calendar)
        let query = try HealthKitService.cumulativeDescriptor(.activeEnergyBurned, window: window)
        let predicate = try XCTUnwrap(query.predicate.nsPredicate)
        let type = HKObjectType.quantityType(forIdentifier: .activeEnergyBurned)!
        func sample(_ first: Double, _ last: Double) -> HKQuantitySample {
            HKQuantitySample(type: type, quantity: HKQuantity(unit: .kilocalorie(), doubleValue: 1),
                             start: start.addingTimeInterval(first), end: start.addingTimeInterval(last))
        }
        XCTAssertEqual(window.end, cutoff)
        XCTAssertTrue(predicate.evaluate(with: sample(0.25, 0.5)))
        XCTAssertFalse(predicate.evaluate(with: sample(0.8, 1)))
        XCTAssertFalse(predicate.evaluate(with: sample(-2, -1)))
        XCTAssertEqual(query.options, .cumulativeSum)
    }

}
