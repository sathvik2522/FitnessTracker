import XCTest
#if SWIFT_PACKAGE
@testable import PersonalFitnessCore
#else
@testable import PersonalFitness
#endif

final class SleepAnalysisTests: XCTestCase {
    private var calendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        return value
    }
    private func date(_ text: String) -> Date { ISO8601DateFormatter().date(from: text)! }
    private func record(_ start: String, _ end: String, _ kind: SleepRecord.Kind = .asleep) -> SleepRecord {
        SleepRecord(id: UUID(), start: date(start), end: date(end), kind: kind)
    }
    func testOvernightStagesAndInBedAreSeparateAndOverlapsUnioned() throws {
        let day = date("2026-10-17T15:00:00Z"), now = date("2026-10-17T21:00:00Z")
        let window = try XCTUnwrap(SleepWindow(day: day, now: now, calendar: calendar))
        let broad = record("2026-10-17T05:00:00Z", "2026-10-17T13:00:00Z")
        let summary = SleepAnalysis.summarize([broad, broad,
            record("2026-10-17T06:00:00Z", "2026-10-17T10:00:00Z"),
            record("2026-10-17T04:00:00Z", "2026-10-17T14:00:00Z", .inBed)], in: window)
        XCTAssertEqual(summary.asleepSeconds, 8 * 3600)
        XCTAssertEqual(summary.inBedSeconds, 10 * 3600)
        XCTAssertFalse(summary.conflictingStates)
    }
    func testSourcesDescribeOnlyValidOverlappingRecords() throws {
        let now = date("2026-10-17T21:00:00Z")
        let window = try XCTUnwrap(SleepWindow(day: now, now: now, calendar: calendar))
        let result = SleepAnalysis.summarize([
            SleepRecord(id: UUID(), start: window.start, end: window.end, kind: .asleep, sourceName: "Watch"),
            SleepRecord(id: UUID(), start: window.start, end: window.end, kind: .asleep, sourceName: "Watch"),
            SleepRecord(id: UUID(), start: window.end, end: now, kind: .asleep, sourceName: "Outside")
        ], in: window)
        XCTAssertEqual(result.sources, ["Watch"])
        XCTAssertEqual(result.asleepSeconds, window.end.timeIntervalSince(window.start))
    }

    func testMissingSleepAndInBedOnlyNeverBecomeZeroSleep() throws {
        let now = date("2026-10-17T21:00:00Z")
        let window = try XCTUnwrap(SleepWindow(day: now, now: now, calendar: calendar))
        XCTAssertNil(SleepAnalysis.summarize([], in: window).asleepSeconds)
        let result = SleepAnalysis.summarize([record("2026-10-17T05:00:00Z", "2026-10-17T13:00:00Z", .inBed)], in: window)
        XCTAssertNil(result.asleepSeconds)
        XCTAssertEqual(result.inBedSeconds, 8 * 3600)
    }
    func testConflictingAwakeRecordsWithholdComparison() throws {
        let now = date("2026-10-17T21:00:00Z")
        let window = try XCTUnwrap(SleepWindow(day: now, now: now, calendar: calendar))
        let result = SleepAnalysis.summarize([record("2026-10-17T05:00:00Z", "2026-10-17T13:00:00Z"),
            record("2026-10-17T06:00:00Z", "2026-10-17T07:00:00Z", .awake)], in: window)
        XCTAssertTrue(result.conflictingStates)
        XCTAssertNil(SleepAnalysis.observation(current: result, previous: [result, result, result]))
    }
    func testNoonWindowsRespectDSTAndCurrentCutoff() throws {
        for (text, hours) in [("2026-03-08T21:00:00Z", 23.0), ("2026-11-01T22:00:00Z", 25.0)] {
            let now = date(text)
            let window = try XCTUnwrap(SleepWindow(day: now, now: now, calendar: calendar))
            XCTAssertEqual(window.end.timeIntervalSince(window.start), hours * 3600)
            XCTAssertFalse(window.isPartial)
        }
        let morning = date("2026-10-17T14:00:00Z")
        let window = try XCTUnwrap(SleepWindow(day: morning, now: morning, calendar: calendar))
        XCTAssertEqual(window.end, morning); XCTAssertTrue(window.isPartial)
    }
    func testClippingAndInvalidSamples() throws {
        let now = date("2026-10-17T21:00:00Z")
        let window = try XCTUnwrap(SleepWindow(day: now, now: now, calendar: calendar))
        let result = SleepAnalysis.summarize([
            SleepRecord(id: UUID(), start: window.start.addingTimeInterval(-3600), end: window.start.addingTimeInterval(3600), kind: .asleep),
            SleepRecord(id: UUID(), start: now, end: now.addingTimeInterval(-1), kind: .asleep)], in: window)
        XCTAssertEqual(result.asleepSeconds, 3600); XCTAssertTrue(result.invalidSamples)
    }
    func testTimelineShowsClippedUnionIntervalsWithoutInventingStagesOrGaps() throws {
        let now = date("2026-10-17T21:00:00Z")
        let window = try XCTUnwrap(SleepWindow(day: now, now: now, calendar: calendar))
        let first = window.start.addingTimeInterval(3600)
        let records = [
            SleepRecord(id: UUID(), start: window.start.addingTimeInterval(-60), end: first, kind: .asleep, sourceName: "Watch"),
            SleepRecord(id: UUID(), start: window.start, end: first, kind: .asleep, sourceName: "Phone"),
            SleepRecord(id: UUID(), start: first.addingTimeInterval(600), end: first.addingTimeInterval(1200), kind: .asleep, sourceName: "Watch")]
        let result = SleepAnalysis.summarize(records, in: window)
        XCTAssertEqual(result.asleepIntervals.count, 2)
        XCTAssertEqual(result.asleepIntervals[0], DateInterval(start: window.start, end: first))
        XCTAssertEqual(result.asleepIntervals[1].start.timeIntervalSince(first), 600)
        XCTAssertEqual(result.asleepIntervals.reduce(0) { $0 + $1.duration }, result.asleepSeconds)
        XCTAssertEqual(result.sources, ["Phone", "Watch"])
        XCTAssertTrue(SleepAnalysis.summarize([], in: window).asleepIntervals.isEmpty)
    }

    func testFutureAndInvalidWindowsAreUnavailable() {
        let now = date("2026-10-17T21:00:00Z")
        XCTAssertNil(SleepWindow(day: now.addingTimeInterval(2 * 86400), now: now, calendar: calendar))
        XCTAssertNil(SleepWindow(day: Date(timeIntervalSince1970: .nan), now: now, calendar: calendar))
    }
    func testSleepComparisonDescribesLongerSimilarAndInvalidReadingsWithoutScores() {
        func summary(_ seconds: Double) -> SleepSummary { SleepSummary(asleepSeconds: seconds, inBedSeconds: nil, conflictingStates: false, invalidSamples: false) }
        let prior = Array(repeating: summary(6 * 3600), count: 3)
        XCTAssertTrue(SleepAnalysis.observation(current: summary(8 * 3600), previous: prior)?.contains("120 minutes longer") == true)
        XCTAssertTrue(SleepAnalysis.observation(current: summary(6 * 3600), previous: prior)?.contains("within one minute") == true)
        XCTAssertNil(SleepAnalysis.observation(current: summary(.nan), previous: prior))
        XCTAssertNil(SleepAnalysis.observation(current: summary(7 * 3600), previous: [summary(.infinity), summary(6 * 3600), summary(6 * 3600)]))
    }

    func testComparisonsRequireThreeValidNights() {
        func summary(_ hours: Double) -> SleepSummary { SleepSummary(asleepSeconds: hours * 3600, inBedSeconds: nil, conflictingStates: false, invalidSamples: false) }
        XCTAssertNil(SleepAnalysis.observation(current: summary(6), previous: [summary(8), summary(8)]))
        XCTAssertNotNil(SleepAnalysis.observation(current: summary(6), previous: [summary(8), summary(8), summary(8)]))
    }
}
