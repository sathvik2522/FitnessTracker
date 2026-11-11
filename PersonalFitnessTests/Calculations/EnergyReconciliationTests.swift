import XCTest
#if SWIFT_PACKAGE
@testable import PersonalFitnessCore
#else
@testable import PersonalFitness
#endif

final class EnergyReconciliationTests: XCTestCase {
    private func window(partial: Bool = false) throws -> LocalDayWindow {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let date = calendar.date(from: DateComponents(year: 2026, month: 10, day: 13))!
        return try LocalDayWindow(day: date, now: date.addingTimeInterval(partial ? 43200 : 86400), calendar: calendar)
    }

    private func aggregates(_ window: LocalDayWindow) -> [EnergyAggregate] {
        [EnergyAggregate(kind: .resting, reading: .value(1600), window: window, coverage: .complete),
         EnergyAggregate(kind: .active, reading: .value(500), window: window, coverage: .complete)]
    }

    private func assess(_ window: LocalDayWindow, food: CalorieReading = .value(1900),
                        energy: [EnergyAggregate]? = nil) -> EnergyAssessment {
        EnergyReconciliation.assess(window: window,
            food: FoodEnergy(reading: food, window: window, coverage: .complete),
            aggregates: energy ?? aggregates(window))
    }

    func testDeficitSurplusAndZeroWithoutExtraEnergy() throws {
        let window = try window()
        for (intake, expected) in [(1900.0, -200.0), (2400, 300), (2100, 0)] {
            let result = assess(window, food: .value(intake))
            XCTAssertEqual(result.balance.expenditure, 2100)
            XCTAssertEqual(result.balance.net, expected)
            XCTAssertEqual(result.balanceQuality, .available)
        }
    }

    func testMissingFoodPreservesExpenditureButSuppressesBalance() throws {
        let result = assess(try window(), food: .missing)
        XCTAssertEqual(result.balance.expenditure, 2100)
        XCTAssertNil(result.balance.net)
        XCTAssertEqual(result.balanceQuality, .unavailable)
        XCTAssertTrue(result.balanceReasons.contains(.foodMissing))
    }

    func testMissingRestingOrActiveIsNotZero() throws {
        let window = try window()
        for kind in [EnergyKind.resting, .active] {
            var values = aggregates(window)
            values.removeAll { $0.kind == kind }
            let result = assess(window, energy: values)
            XCTAssertNil(result.balance.expenditure)
            XCTAssertNil(result.balance.net)
        }
    }

    func testPartialDayHasProvisionalValuesNotAFullDayForecast() throws {
        let result = assess(try window(partial: true))
        XCTAssertEqual(result.balance.net, -200)
        XCTAssertEqual(result.expenditureQuality, .partial)
        XCTAssertEqual(result.balanceQuality, .partial)
        XCTAssertTrue(result.balanceReasons.contains(.dayInProgress))
        XCTAssertEqual(result.scopeTitle, "Day in progress")
    }

    func testEmptyDayDoesNotInventZeroExpenditureOrFasting() throws {
        let result = assess(try window(), food: .missing, energy: [])
        XCTAssertNil(result.balance.consumed)
        XCTAssertNil(result.balance.expenditure)
        XCTAssertNil(result.balance.net)
    }

    func testConfirmedZeroReadingsRemainValid() throws {
        let window = try window()
        let values = [EnergyAggregate(kind: .resting, reading: .value(0), window: window, coverage: .complete),
                      EnergyAggregate(kind: .active, reading: .value(0), window: window, coverage: .complete)]
        XCTAssertEqual(assess(window, food: .value(0), energy: values).balance.net, 0)
    }

    func testIdenticalAggregateCopiesAreUsedOnce() throws {
        let window = try window()
        let values = aggregates(window)
        XCTAssertEqual(assess(window, energy: values + values).balance.expenditure, 2100)
    }

    func testSourceSubtotalsAndWorkoutRepresentationsAreNeverAdded() throws {
        let window = try window()
        let extras = [EnergyAggregate(kind: .active, reading: .value(500), window: window, representation: .sourceSubtotal),
                      EnergyAggregate(kind: .active, reading: .value(900), window: window, representation: .workout)]
        XCTAssertEqual(assess(window, energy: aggregates(window) + extras).balance.expenditure, 2100)
        XCTAssertNil(assess(window, energy: extras).balance.expenditure)
    }

    func testConflictingAggregatesAreRejectedInsteadOfSummedOrMaximized() throws {
        let window = try window()
        let conflict = EnergyAggregate(kind: .active, reading: .value(600), window: window)
        let result = assess(window, energy: aggregates(window) + [conflict])
        XCTAssertNil(result.balance.expenditure)
        XCTAssertTrue(result.expenditureReasons.contains(.conflictingAggregates))
    }

    func testOverlappingDifferentWindowsCannotBeCombined() throws {
        let full = try window()
        let partial = try window(partial: true)
        let result = assess(full, energy: aggregates(partial))
        XCTAssertNil(result.balance.expenditure)
        XCTAssertTrue(result.expenditureReasons.contains(.mismatchedWindow))
        // An exact merged result is authoritative; unrelated overlapping results add nothing.
        XCTAssertEqual(assess(full, energy: aggregates(full) + aggregates(partial)).balance.expenditure, 2100)
    }

    func testMismatchedFoodCutoffSuppressesOnlyBalance() throws {
        let full = try window()
        let result = EnergyReconciliation.assess(window: full,
            food: FoodEnergy(reading: .value(1900), window: try window(partial: true)), aggregates: aggregates(full))
        XCTAssertEqual(result.balance.expenditure, 2100)
        XCTAssertNil(result.balance.net)
        XCTAssertTrue(result.balanceReasons.contains(.mismatchedWindow))
    }

    func testKnownIncompleteEnergyCannotBecomeATrustedTotal() throws {
        let window = try window()
        var values = aggregates(window)
        values[1] = EnergyAggregate(kind: .active, reading: .incomplete(100), window: window)
        let result = assess(window, energy: values)
        XCTAssertNil(result.balance.expenditure)
        XCTAssertTrue(result.expenditureReasons.contains(.energyIncomplete))
    }

    func testKnownIncompleteIntakeSuppressesBalance() throws {
        let result = assess(try window(), food: .incomplete(500))
        XCTAssertEqual(result.balance.expenditure, 2100)
        XCTAssertNil(result.balance.net)
        XCTAssertTrue(result.balanceReasons.contains(.foodIncomplete))
    }

    func testClosedHistoricalWindowDoesNotProveInputCompleteness() throws {
        let window = try window()
        let values = aggregates(window).map {
            EnergyAggregate(kind: $0.kind, reading: $0.reading, window: window)
        }
        let result = EnergyReconciliation.assess(window: window,
            food: FoodEnergy(reading: .value(1900), window: window), aggregates: values)
        XCTAssertEqual(result.balance.net, -200)
        XCTAssertEqual(result.balanceQuality, .partial)
        XCTAssertTrue(result.balanceReasons.contains(.coverageUnverified))
        XCTAssertTrue(result.balanceReasons.contains(.foodUnverified))
        XCTAssertEqual(result.scopeTitle, "Closed historical-day window")
    }

    func testNoIntermediateRounding() throws {
        let window = try window()
        let values = [EnergyAggregate(kind: .resting, reading: .value(1600.49), window: window),
                      EnergyAggregate(kind: .active, reading: .value(500.49), window: window)]
        let result = assess(window, food: .value(2100.99), energy: values)
        XCTAssertEqual(try XCTUnwrap(result.balance.expenditure), 2100.98, accuracy: 0.000001)
        XCTAssertEqual(try XCTUnwrap(result.balance.net), 0.01, accuracy: 0.000001)
    }

    func testInvalidAndOverflowingAggregatesAreUnavailable() throws {
        let window = try window()
        for value in [-1.0, Double.nan, Double.infinity] {
            let values = [EnergyAggregate(kind: .resting, reading: .value(value), window: window), aggregates(window)[1]]
            XCTAssertNil(assess(window, energy: values).balance.expenditure)
        }
        let overflow = [EnergyAggregate(kind: .resting, reading: .value(.greatestFiniteMagnitude), window: window),
                        EnergyAggregate(kind: .active, reading: .value(.greatestFiniteMagnitude), window: window)]
        let result = assess(window, energy: overflow)
        XCTAssertNil(result.balance.expenditure)
        XCTAssertTrue(result.expenditureReasons.contains(.arithmeticInvalid))
    }
    func testHistoricalCalculationsAcrossBothDSTTransitions() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        for (month, day, hours) in [(3, 8, 23), (11, 1, 25)] {
            let start = calendar.date(from: DateComponents(year: 2026, month: month, day: day))!
            let next = calendar.date(byAdding: .day, value: 1, to: start)!
            let window = try LocalDayWindow(day: start, now: next, calendar: calendar)
            let result = assess(window)
            XCTAssertEqual(window.end.timeIntervalSince(window.start), Double(hours * 3600))
            XCTAssertEqual(result.balance.net, -200)
            XCTAssertFalse(result.window.isPartial)
            XCTAssertFalse(result.balanceReasons.contains(.dayInProgress))
        }
    }

    func testFailedFoodDoesNotHideAvailableExpenditure() throws {
        let result = assess(try window(), food: .failed)
        XCTAssertEqual(result.balance.expenditure, 2100)
        XCTAssertNil(result.balance.net)
        XCTAssertTrue(result.balanceReasons.contains(.foodFailed))
    }

}
