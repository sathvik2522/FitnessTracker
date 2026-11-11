import XCTest
import HealthKit
@testable import PersonalFitness

@MainActor
private final class SleepStub: SleepDataReading {
    var isAvailable = true
    var hasCompletedSleepRequest = false
    var requests = 0
    var queries = 0
    var suspend = false
    var continuation: CheckedContinuation<HealthReading<[SleepRecord]>, Never>?
    var reading: HealthReading<[SleepRecord]> = .unavailable
    func requestSleepAccess() async throws { requests += 1; hasCompletedSleepRequest = true }
    func readSleep(start: Date, end: Date) async -> HealthReading<[SleepRecord]> {
        queries += 1
        if suspend { return await withCheckedContinuation { continuation = $0 } }
        return reading
    }
}

final class SleepModelTests: XCTestCase {
    @MainActor
    func testCancelledQueryReleasesLoadingState() async {
        let stub = SleepStub(); stub.hasCompletedSleepRequest = true; stub.suspend = true
        let model = SleepModel(service: stub)
        let task = Task { await model.load(day: .now) }
        while stub.continuation == nil { await Task.yield() }
        XCTAssertTrue(model.loading)
        task.cancel()
        stub.continuation?.resume(returning: .unavailable)
        await task.value
        XCTAssertFalse(model.loading)
        XCTAssertTrue(model.nights.isEmpty)
    }

    @MainActor
    func testStaleQueryCannotReplaceNewRequestOrKeepSpinnerAfterUnavailable() async {
        let stub = SleepStub(); stub.hasCompletedSleepRequest = true; stub.suspend = true
        let model = SleepModel(service: stub)
        let task = Task { await model.load(day: .now) }
        while stub.continuation == nil { await Task.yield() }
        stub.isAvailable = false
        await model.load(day: .now)
        XCTAssertFalse(model.loading)
        XCTAssertFalse(model.available)
        stub.continuation?.resume(returning: .failed(.queryFailed))
        await task.value
        XCTAssertFalse(model.loading)
        XCTAssertNil(model.error)
    }

    @MainActor
    func testRefreshNeverRequestsPermissionAndExplicitConnectDoes() async {
        let stub = SleepStub(), now = Date.now
        let model = SleepModel(service: stub)
        await model.load(day: now, now: now)
        XCTAssertEqual(stub.requests, 0); XCTAssertEqual(stub.queries, 0)
        await model.connect(day: now, now: now)
        XCTAssertEqual(stub.requests, 1); XCTAssertEqual(stub.queries, 1)
        XCTAssertEqual(model.nights.count, 7)
        XCTAssertNil(model.nights.first?.summary.asleepSeconds)
    }
    @MainActor
    func testAvailableMissingAndFailedReadStatesRemainDistinct() async {
        let stub = SleepStub(); stub.hasCompletedSleepRequest = true
        let now = Date.now
        let window = SleepWindow(day: now, now: now, calendar: .current)!
        stub.reading = .value([SleepRecord(id: UUID(), start: window.start, end: window.start.addingTimeInterval(3600), kind: .asleep)])
        let model = SleepModel(service: stub)
        await model.load(day: now, now: now)
        XCTAssertEqual(model.nights.first?.summary.asleepSeconds, 3600)
        stub.reading = .failed(.deviceLocked)
        await model.load(day: now, now: now)
        XCTAssertNotNil(model.error); XCTAssertTrue(model.nights.isEmpty)
        stub.reading = .unavailable
        await model.load(day: now, now: now)
        XCTAssertNil(model.error); XCTAssertNil(model.nights.first?.summary.asleepSeconds)
    }
    @MainActor
    func testSleepQueryIncludesOvernightOverlapsAndRequestsOnlySleep() throws {
        let start = Date(timeIntervalSince1970: 1_700_000_000), end = start.addingTimeInterval(3600)
        XCTAssertEqual(HealthKitService.sleepReadTypes.map(\.identifier), [HKCategoryType(.sleepAnalysis).identifier])
        let descriptor = HealthKitService.sleepDescriptor(start: start, end: end)
        let predicate = try XCTUnwrap(descriptor.predicates.first?.nsPredicate)
        let overlap = HKCategorySample(type: HKCategoryType(.sleepAnalysis), value: HKCategoryValueSleepAnalysis.asleepCore.rawValue,
            start: start.addingTimeInterval(-3600), end: start.addingTimeInterval(60))
        XCTAssertTrue(predicate.evaluate(with: overlap))
        let outside = HKCategorySample(type: HKCategoryType(.sleepAnalysis), value: HKCategoryValueSleepAnalysis.asleepCore.rawValue,
            start: end.addingTimeInterval(60), end: end.addingTimeInterval(120))
        XCTAssertFalse(predicate.evaluate(with: outside))
    }

    @MainActor
    func testSleepCategoryConversionKeepsInBedSeparateFromAsleepStages() throws {
        let start = Date(timeIntervalSince1970: 1_700_000_000), end = start.addingTimeInterval(3600)
        for stage in [HKCategoryValueSleepAnalysis.asleepCore, .asleepREM, .asleepDeep, .asleepUnspecified] {
            let sample = HKCategorySample(type: HKCategoryType(.sleepAnalysis), value: stage.rawValue, start: start, end: end)
            XCTAssertEqual(HealthKitService.sleepRecord(sample)?.kind, .asleep)
        }
        let bed = HKCategorySample(type: HKCategoryType(.sleepAnalysis), value: HKCategoryValueSleepAnalysis.inBed.rawValue, start: start, end: end)
        XCTAssertEqual(HealthKitService.sleepRecord(bed)?.kind, .inBed)
    }
}
