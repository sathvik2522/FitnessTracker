import XCTest
#if SWIFT_PACKAGE
@testable import PersonalFitnessCore
#else
@testable import PersonalFitness
#endif

final class EnergyExpenditureTests: XCTestCase {
    var calendar: Calendar { var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(secondsFromGMT: 0)!; return c }
    var day: Date { calendar.date(from: DateComponents(year: 2026, month: 10, day: 19))! }
    func assessment(resting: Double? = nil, active: Double? = nil, food: Double? = 2000, window: LocalDayWindow? = nil) throws -> EnergyAssessment {
        let w = try window ?? LocalDayWindow(day: day, now: day.addingTimeInterval(86400), calendar: calendar)
        return EnergyReconciliation.assess(window: w, food: FoodEnergy(reading: food.map(CalorieReading.value) ?? .missing, window: w), aggregates: [EnergyAggregate(kind: .resting, reading: resting.map(CalorieReading.value) ?? .missing, window: w), EnergyAggregate(kind: .active, reading: active.map(CalorieReading.value) ?? .missing, window: w)])
    }
    var configuration: ScoringConfiguration {
        var c = ScoringConfiguration()
        c.profile = ExpenditureProfile(age: 30, heightCM: 180, weightKG: 80, parameter: .male, multiplier: 1.5)
        return c
    }
    func testBothExplicitEquationsAndInvalidOrMissingInputs() throws {
        var p = try XCTUnwrap(configuration.profile)
        XCTAssertEqual(EnergyExpenditureService.restingPrediction(p), 1780)
        p.parameter = .female; XCTAssertEqual(EnergyExpenditureService.restingPrediction(p), 1614)
        XCTAssertNil(EnergyExpenditureService.restingPrediction(nil))
        for bad in [-1.0, 0, Double.nan, .infinity, 1e300] {
            p = try XCTUnwrap(configuration.profile); p.weightKG = bad; XCTAssertNil(EnergyExpenditureService.restingPrediction(p))
            p = try XCTUnwrap(configuration.profile); p.heightCM = bad; XCTAssertNil(EnergyExpenditureService.restingPrediction(p))
            p = try XCTUnwrap(configuration.profile); p.age = bad; XCTAssertNil(EnergyExpenditureService.restingPrediction(p))
        }
        let data = try JSONEncoder().encode(configuration.profile)
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        object.removeValue(forKey: "parameter")
        XCTAssertThrowsError(try JSONDecoder().decode(ExpenditureProfile.self, from: JSONSerialization.data(withJSONObject: object)))
    }
    func testHealthWinsBothComponentsWithoutMultiplier() throws {
        let value = EnergyExpenditureService.calculate(assessment: try assessment(resting: 1500, active: 600), configuration: configuration, calendar: calendar)
        XCTAssertEqual(value.total, 2100); XCTAssertFalse(value.predicted)
        XCTAssertEqual(value.resting?.source, .healthKit); XCTAssertEqual(value.active?.source, .healthKit)
    }
    func testMixedSourceUsesFormulaRestingPlusHealthActive() throws {
        let value = EnergyExpenditureService.calculate(assessment: try assessment(active: 600), configuration: configuration, calendar: calendar, now: day.addingTimeInterval(90000))
        XCTAssertEqual(value.total, 2380); XCTAssertEqual(value.resting?.kcal, 1780)
        XCTAssertEqual(value.resting?.source, .mifflin); XCTAssertEqual(value.active?.source, .healthKit)
        XCTAssertTrue(value.predicted); XCTAssertFalse(value.partial)
        XCTAssertEqual(value.timeZoneIdentifier, calendar.timeZone.identifier); XCTAssertEqual(value.profile, configuration.profile)
    }
    func testMissingActiveIsExplicitAssumptionNeverMultipliedHealthResting() throws {
        let value = EnergyExpenditureService.calculate(assessment: try assessment(resting: 1500), configuration: configuration, calendar: calendar)
        XCTAssertEqual(value.active?.kcal, 890); XCTAssertEqual(value.active?.source, .activityAssumption)
        XCTAssertEqual(value.total, 2390) // 1500 + predicted 1780 × (1.5−1), not 1500×1.5 plus activity.
        let noProfile = EnergyExpenditureService.calculate(assessment: try assessment(resting: 1500), configuration: .init(), calendar: calendar)
        XCTAssertNil(noProfile.total); XCTAssertNil(noProfile.active)
    }
    func testRestingPredictionDoesNotRequireAnActivityAssumption() throws {
        var c = configuration; c.profile?.multiplier = nil
        XCTAssertEqual(EnergyExpenditureService.restingPrediction(c.profile), 1780)
        let mixed = EnergyExpenditureService.calculate(assessment: try assessment(active: 600), configuration: c, calendar: calendar)
        XCTAssertEqual(mixed.total, 2380); XCTAssertEqual(mixed.active?.source, .healthKit)
        let missing = EnergyExpenditureService.calculate(assessment: try assessment(), configuration: c, calendar: calendar)
        XCTAssertNil(missing.total); XCTAssertEqual(missing.resting?.kcal, 1780); XCTAssertNil(missing.active)
        XCTAssertNil(c.profile?.fullDayEstimate)
    }
    func testObservedZeroWinsAndInvalidValuesCannotBecomeHealthReadings() throws {
        let value = EnergyExpenditureService.calculate(assessment: try assessment(resting: 0, active: 0), configuration: configuration, calendar: calendar)
        XCTAssertEqual(value.total, 0); XCTAssertFalse(value.predicted)
        XCTAssertNil(DashboardEnergyEstimate.make(assessment: try assessment(resting: 0, active: 0), configuration: configuration, calendar: calendar).progressFraction)
        for bad in [-1.0, Double.nan, .infinity] {
            let value = EnergyExpenditureService.calculate(assessment: try assessment(resting: bad, active: bad), configuration: .init(), calendar: calendar)
            XCTAssertNil(value.total)
        }
    }
    func testPredictionPartialDayDSTAndMidnight() throws {
        var ny = calendar; ny.timeZone = TimeZone(identifier: "America/New_York")!
        for (month, date, hours, elapsed) in [(3,10,23.0,11.0),(11,3,25.0,13.0)] {
            let d = try XCTUnwrap(ny.date(from: DateComponents(year: 2024, month: month, day: date)))
            let noon = try XCTUnwrap(ny.date(from: DateComponents(year: 2024, month: month, day: date, hour: 12)))
            let w = try LocalDayWindow(day: d, now: noon, calendar: ny)
            let value = EnergyExpenditureService.calculate(assessment: try assessment(window: w), configuration: configuration, calendar: ny)
            XCTAssertEqual(value.total ?? -1, 2670 * elapsed / hours, accuracy: 1e-8); XCTAssertTrue(value.partial)
            let end = try LocalDayWindow.interval(for: d, calendar: ny).end
            let closed = try LocalDayWindow(day: d, now: end, calendar: ny)
            let full = EnergyExpenditureService.calculate(assessment: try assessment(window: closed), configuration: configuration, calendar: ny)
            XCTAssertEqual(full.total, 2670); XCTAssertFalse(full.partial)
        }
    }
    func testClosedDayPredictionPreservesInputsAcrossProfileChangesAndJSON() throws {
        let a = try assessment(active: 600)
        let original = EnergyExpenditureService.calculate(assessment: a, configuration: configuration, calendar: calendar, now: day.addingTimeInterval(90000))
        var changed = configuration; changed.profile?.weightKG = 100
        let saved = try JSONDecoder().decode(EnergyExpenditureRecord.self, from: JSONEncoder().encode(original))
        let historical = EnergyExpenditureService.calculate(assessment: a, configuration: changed, calendar: calendar, historical: saved)
        XCTAssertEqual(historical, original)
        XCTAssertEqual(EnergyExpenditureService.calculate(assessment: a, configuration: changed, calendar: calendar).total, 2580)
        let live = EnergyExpenditureService.calculate(assessment: try assessment(resting: 1400, active: 500), configuration: changed, calendar: calendar, historical: saved)
        XCTAssertEqual(live.total, 1900); XCTAssertFalse(live.predicted)
        let other = try LocalDayWindow(day: day.addingTimeInterval(-86400), now: day, calendar: calendar)
        XCTAssertNotEqual(EnergyExpenditureService.calculate(assessment: try assessment(window: other), configuration: changed, calendar: calendar, historical: saved).start, saved.start)
    }
    func testEnergyArcReflectsIntakeOverExpenditureAndSignedBalance() throws {
        for (food, balance, fraction) in [(0.0,-2000.0,0.0),(1500,-500,0.75),(2000,0,1),(2500,500,1)] {
            let value = DashboardEnergyEstimate.make(assessment: try assessment(resting: 1500, active: 500, food: food), configuration: .init(), calendar: calendar)
            XCTAssertEqual(value.balance, balance); XCTAssertEqual(value.progressFraction, fraction)
        }
        let empty = DashboardEnergyEstimate.make(assessment: try assessment(resting: 1500, active: 500, food: nil), configuration: .init(), calendar: calendar)
        XCTAssertNil(empty.balance); XCTAssertNil(empty.progressFraction)
    }
    func testExplicitTotalRemainsIndependentAndNoWorkoutInputExists() throws {
        var c = ScoringConfiguration(); c.dailyExpenditure = 2400
        let value = EnergyExpenditureService.calculate(assessment: try assessment(resting: 1500), configuration: c, calendar: calendar)
        XCTAssertEqual(value.total, 2400); XCTAssertNil(value.active); XCTAssertEqual(value.explicitDailyEstimate, 2400)
    }
}
