import XCTest
#if SWIFT_PACKAGE
@testable import PersonalFitnessCore
#else
@testable import PersonalFitness
#endif

final class WellnessScoringTests: XCTestCase {
    var calendar: Calendar { var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(secondsFromGMT: 0)!; return c }
    var day: Date { calendar.date(from: DateComponents(year: 2026, month: 10, day: 20))! }
    var now: Date { day.addingTimeInterval(86_400) }
    func date(_ offset: Int) -> Date { calendar.date(byAdding: .day, value: offset, to: day)! }
    func session(_ minutes: Double = 60, rpe: Double? = 5, day offset: Int = 0, origin: LoadSession.Origin = .manual, id: UUID = UUID()) -> LoadSession {
        let start = date(offset).addingTimeInterval(3600)
        return LoadSession(id: id, start: start, end: start.addingTimeInterval(minutes * 60), activity: .strength, origin: origin, rpe: rpe)
    }
    func load(_ sessions: [LoadSession], active: Double? = nil, steps: Double? = nil) throws -> DailyLoad {
        ActivityLoad.day(window: try LocalDayWindow(day: day, now: now, calendar: calendar), sessions: sessions, active: active, steps: steps, now: now)
    }
    func history(_ count: Int = 28, value: Double? = 300, unit: LoadUnit = .sessionRPE) -> [DailyLoad] {
        (1...count).map { DailyLoad(day: date(-$0), value: value, unit: unit, partial: false, notes: [], duplicateCount: 0) }
    }
    func samples(baseline: Double, recent: Double, source: String = "watch") -> [RecoverySample] {
        let prior = (3...22).map { RecoverySample(id: UUID(), date: date(-$0).addingTimeInterval(3600), value: baseline, source: source) }
        return prior + [-1, -1, 0].enumerated().map { index, offset in RecoverySample(id: UUID(), date: date(offset).addingTimeInterval(Double(3600 + index * 60)), value: recent, source: source) }
    }
    func assessment(food: Double? = 2000, resting: Double? = 1500, active: Double? = 600, window: LocalDayWindow? = nil) throws -> EnergyAssessment {
        let w = try window ?? LocalDayWindow(day: day, now: now, calendar: calendar)
        return EnergyReconciliation.assess(window: w, food: FoodEnergy(reading: food.map(CalorieReading.value) ?? .missing, window: w), aggregates: [EnergyAggregate(kind: .resting, reading: resting.map(CalorieReading.value) ?? .missing, window: w), EnergyAggregate(kind: .active, reading: active.map(CalorieReading.value) ?? .missing, window: w)])
    }
    func testDurationTimesRPEAndMultipleSessions() throws {
        let value = try load([session(60, rpe: 5), session(20, rpe: 3)])
        XCTAssertEqual(value.value, 360); XCTAssertEqual(value.unit, .sessionRPE)
        let estimate = ActivityLoad.strain(load: value, history: [], configuration: .init(), calendar: calendar)
        XCTAssertEqual(estimate.score, 100); XCTAssertEqual(estimate.target, 300); XCTAssertTrue(estimate.provisional)
    }
    func testRecordedZeroIsDifferentFromMissingDay() throws {
        XCTAssertNil(try load([]).value)
        XCTAssertEqual(try load([], active: 0).value, 0)
        XCTAssertEqual(try load([session(rpe: 0)]).value, 0)
        XCTAssertNil(ActivityLoad.strain(load: try load([]), history: [], configuration: .init()).score)
    }
    func testMissingOrInvalidRPEUsesDurationWithoutInventedIntensity() throws {
        for rpe in [Double?.none, -1, 11, .nan, .infinity] {
            let result = try load([session(40, rpe: rpe), session(20, rpe: 5)])
            XCTAssertEqual(result.value, 60); XCTAssertEqual(result.unit, .minutes)
        }
    }
    func testHealthActivityFallbacksAreAlternativesNotAdditions() throws {
        XCTAssertEqual(try load([], active: 200, steps: 9000).value, 200)
        XCTAssertEqual(try load([], active: nil, steps: 9000).unit, .steps)
        XCTAssertEqual(try load([session(30, rpe: 4)], active: 5000, steps: 9000).value, 120)
        XCTAssertNil(try load([], active: .nan, steps: -.infinity).value)
    }
    func testPersonalTargetRequiresDistinctRecentMatchingModeDays() throws {
        let current = try load([session(30, rpe: 5)])
        let c = ScoringConfiguration()
        XCTAssertFalse(ActivityLoad.strain(load: current, history: history(6), configuration: c, calendar: calendar).personalized)
        let result = ActivityLoad.strain(load: current, history: history(7, value: 600), configuration: c, calendar: calendar)
        XCTAssertTrue(result.personalized); XCTAssertEqual(result.score, 25)
        XCTAssertFalse(ActivityLoad.strain(load: current, history: history(7, unit: .active), configuration: c, calendar: calendar).personalized)
        XCTAssertFalse(ActivityLoad.strain(load: current, history: history(7).map { DailyLoad(day: date(-40), value: $0.value, unit: $0.unit, partial: false, notes: [], duplicateCount: 0) }, configuration: c, calendar: calendar).personalized)
    }
    func testConfiguredScaleBoundsAndInvalidConfiguration() throws {
        let current = try load([session(60, rpe: 5)])
        var c = ScoringConfiguration(); c.targetScale = 2
        XCTAssertEqual(ActivityLoad.strain(load: current, history: [], configuration: c).score, 50)
        c.rpeTarget = .leastNonzeroMagnitude
        XCTAssertEqual(ActivityLoad.strain(load: current, history: [], configuration: c).score, 100)
        for invalid in [0, -1, Double.nan, .infinity] {
            c.rpeTarget = invalid; XCTAssertThrowsError(try c.validated()); XCTAssertNil(ActivityLoad.strain(load: current, history: [], configuration: c).score)
        }
    }
    func testDuplicateAndOverlappingHealthRepresentationsDoNotIncreaseLoad() throws {
        let manual = session(60, rpe: 5)
        let imported = session(60, rpe: nil, origin: .health)
        let value = try load([manual, manual, imported, imported])
        XCTAssertEqual(value.value, 300); XCTAssertEqual(value.duplicateCount, 3)
        XCTAssertEqual(try load([manual, session(60, rpe: 5)]).value, 600, "Distinct manual logs are never silently merged")
        XCTAssertEqual(try load([imported, session(60, rpe: nil, origin: .health)]).value, 60)
    }
    func testUnfinishedAndInvalidSessionsNeverBecomeMeasuredZero() throws {
        let future = LoadSession(id: UUID(), start: day.addingTimeInterval(3600), end: now.addingTimeInterval(60), activity: .strength, origin: .manual, rpe: 10)
        XCTAssertNil(try load([future]).value)
        XCTAssertTrue(try load([future]).partial)
        let invalid = LoadSession(id: UUID(), start: day, end: day.addingTimeInterval(-1), activity: .strength, origin: .manual)
        XCTAssertNil(try load([invalid]).value)
    }
    func testWorkoutAssignedToStartDayAcrossMidnight() throws {
        let start = day.addingTimeInterval(-600)
        let crossing = LoadSession(id: UUID(), start: start, end: day.addingTimeInterval(600), activity: .running, origin: .manual, rpe: 4)
        XCTAssertNil(try load([crossing]).value)
        let prior = try LocalDayWindow(day: date(-1), now: now, calendar: calendar)
        XCTAssertEqual(ActivityLoad.day(window: prior, sessions: [crossing], active: nil, steps: nil, now: now).value, 80)
    }
    func testSleepUsesExistingUnionAndTargetAndRejectsConflicts() throws {
        let w = try XCTUnwrap(SleepWindow(day: day, now: now, calendar: calendar))
        let record = SleepRecord(id: UUID(), start: day, end: day.addingTimeInterval(6 * 3600), kind: .asleep)
        let summary = SleepAnalysis.summarize([record, record], in: w)
        XCTAssertEqual(RecoveryScoring.sleep(summary, window: w, c: .init()).score, 75)
        var c = ScoringConfiguration(); c.sleepTargetMinutes = 360
        XCTAssertEqual(RecoveryScoring.sleep(summary, window: w, c: c).score, 100)
        let conflict = SleepAnalysis.summarize([record, SleepRecord(id: UUID(), start: day, end: day.addingTimeInterval(60), kind: .awake)], in: w)
        XCTAssertNil(RecoveryScoring.sleep(conflict, window: w, c: c).score)
        XCTAssertNil(RecoveryScoring.sleep(nil, window: w, c: c).score)
    }
    func testHRVMappingsUsePersonalMedianAndRequireBaseline() {
        for (ratio, expected) in [(0.8, 30.0), (1, 50), (1.2, 70)] {
            let result = RecoveryScoring.heart(samples(baseline: 50, recent: 50 * ratio), hrv: true, day: day, now: now, calendar: calendar, c: .init())
            XCTAssertEqual(result.score ?? -1, expected, accuracy: 1e-10); XCTAssertEqual(result.baselineDayCount, 20)
        }
        XCTAssertNil(RecoveryScoring.heart([], hrv: true, day: day, now: now, calendar: calendar, c: .init()).score)
        XCTAssertNil(RecoveryScoring.heart(samples(baseline: 0, recent: 50), hrv: true, day: day, now: now, calendar: calendar, c: .init()).score)
    }
    func testRestingHeartRateMappingDoesNotBonusLowerValues() {
        for (recent, expected) in [(55.0,100.0), (60,75), (50,100), (75,0)] {
            XCTAssertEqual(RecoveryScoring.heart(samples(baseline: 55, recent: recent), hrv: false, day: day, now: now, calendar: calendar, c: .init()).score, expected)
        }
    }
    func testHeartOutliersDuplicatesFutureAndOrderAreHandled() {
        let base = samples(baseline: 50, recent: 50)
        let junk = [RecoverySample(id: UUID(), date: date(-4), value: .nan, source: "watch"),
                    RecoverySample(id: UUID(), date: date(-5), value: 300, source: "watch"),
                    RecoverySample(id: UUID(), date: date(2), value: 100, source: "watch")]
        let a = RecoveryScoring.heart(base, hrv: true, day: day, now: now, calendar: calendar, c: .init())
        let b = RecoveryScoring.heart((base + base + junk).reversed(), hrv: true, day: day, now: now, calendar: calendar, c: .init())
        XCTAssertEqual(a.score, b.score); XCTAssertEqual(a.baseline, b.baseline); XCTAssertEqual(a.sampleCount, b.sampleCount)
    }
    func testSingleRecentReadingAndChangedSourceRemainIneligible() {
        let baseline = samples(baseline: 50, recent: 50).filter { $0.date < date(-2) }
        let one = RecoverySample(id: UUID(), date: day.addingTimeInterval(3600), value: 50, source: "watch")
        XCTAssertNil(RecoveryScoring.heart(baseline + [one], hrv: true, day: day, now: now, calendar: calendar, c: .init()).score)
        let other = samples(baseline: 50, recent: 50).filter { $0.date >= date(-2) }.map { RecoverySample(id: $0.id, date: $0.date, value: $0.value, source: "new watch") }
        XCTAssertNil(RecoveryScoring.heart(baseline + other, hrv: true, day: day, now: now, calendar: calendar, c: .init()).score)
    }
    func testRecoveryWeightsRenormalizeWithoutFabricatingSignals() {
        let components = [RecoveryComponent(id: "sleep", score: 75, weight: 40, detail: ""), RecoveryComponent(id: "hrv", score: 50, weight: 30, detail: ""), RecoveryComponent(id: "rhr", score: 100, weight: 20, detail: ""), RecoveryComponent(id: "load", score: 50, weight: 10, detail: "")]
        let result = RecoveryScoring.combine(components, partial: false)
        XCTAssertEqual(result.score, 70); XCTAssertFalse(result.provisional)
        XCTAssertEqual(RecoveryScoring.combine([components[0]], partial: false).score, 75)
        XCTAssertTrue(RecoveryScoring.combine([components[0]], partial: false).provisional)
        XCTAssertNil(RecoveryScoring.combine([], partial: false).score)
        XCTAssertEqual(RecoveryScoring.combine(components + [components[0]], partial: false).score, 70)
    }
    func testLoadComparisonRequiresObservedCoverageAndSameUnits() {
        XCTAssertNil(RecoveryScoring.training(history: history(20), day: day, calendar: calendar, c: .init()).score)
        XCTAssertNil(RecoveryScoring.training(history: history(value: nil), day: day, calendar: calendar, c: .init()).score)
        XCTAssertEqual(RecoveryScoring.training(history: history(), day: day, calendar: calendar, c: .init()).score, 100)
        let highRecent = history().map { d in DailyLoad(day: d.day, value: d.day >= date(-7) ? 600 : 300, unit: .sessionRPE, partial: false, notes: [], duplicateCount: 0) }
        XCTAssertEqual(RecoveryScoring.training(history: highRecent, day: day, calendar: calendar, c: .init()).score ?? -1, 70, accuracy: 1e-8)
        XCTAssertEqual(RecoveryScoring.training(history: highRecent, day: day, calendar: calendar, c: .init()), RecoveryScoring.training(history: highRecent.reversed(), day: day, calendar: calendar, c: .init()))
    }
    func testEnergyPreferredHealthSignAndMissingInputs() throws {
        let c = ScoringConfiguration()
        XCTAssertEqual(DashboardEnergyEstimate.make(assessment: try assessment(), configuration: c, calendar: calendar).balance, -100)
        XCTAssertEqual(DashboardEnergyEstimate.make(assessment: try assessment(food: 2200), configuration: c, calendar: calendar).balance, 100)
        XCTAssertNil(DashboardEnergyEstimate.make(assessment: try assessment(food: nil), configuration: c, calendar: calendar).balance)
        XCTAssertNil(DashboardEnergyEstimate.make(assessment: try assessment(resting: nil), configuration: c, calendar: calendar).expenditure)
        XCTAssertNil(DashboardEnergyEstimate.make(assessment: try assessment(active: nil), configuration: c, calendar: calendar).balance)
    }
    func testExplicitFallbackDoesNotAddReadablePartialHealthOrWorkouts() throws {
        var c = ScoringConfiguration(); c.dailyExpenditure = 2500
        let fallback = DashboardEnergyEstimate.make(assessment: try assessment(active: nil), configuration: c, calendar: calendar)
        XCTAssertEqual(fallback.expenditure, 2500); XCTAssertEqual(fallback.balance, -500); XCTAssertTrue(fallback.fallback)
        XCTAssertEqual(DashboardEnergyEstimate.make(assessment: try assessment(), configuration: c, calendar: calendar).expenditure, 2100)
    }
    func testMifflinRequiresAllExplicitAdultInputs() throws {
        var c = ScoringConfiguration()
        XCTAssertNil(DashboardEnergyEstimate.make(assessment: try assessment(active: nil), configuration: c, calendar: calendar).expenditure)
        c.profile = ExpenditureProfile(age: 30, heightCM: 180, weightKG: 80, parameter: .male, multiplier: 1.5)
        XCTAssertEqual(c.profile?.fullDayEstimate, 2670)
        XCTAssertEqual(DashboardEnergyEstimate.make(assessment: try assessment(active: nil), configuration: c, calendar: calendar).expenditure, 2390)
        c.profile?.age = .nan; XCTAssertThrowsError(try c.validated()); XCTAssertNil(c.profile?.fullDayEstimate)
    }
    func testCurrentDayAndDSTFallbackUseActualCalendarLength() throws {
        var ny = calendar; ny.timeZone = TimeZone(identifier: "America/New_York")!
        let d = ny.date(from: DateComponents(year: 2024, month: 3, day: 10))!
        let noon = ny.date(from: DateComponents(year: 2024, month: 3, day: 10, hour: 12))!
        let w = try LocalDayWindow(day: d, now: noon, calendar: ny)
        XCTAssertEqual(try LocalDayWindow.interval(for: d, calendar: ny).duration, 23 * 3600)
        var c = ScoringConfiguration(); c.dailyExpenditure = 2300
        let e = DashboardEnergyEstimate.make(assessment: try assessment(resting: nil, window: w), configuration: c, calendar: ny)
        XCTAssertTrue(e.partial); XCTAssertEqual(e.expenditure ?? -1, 1100, accuracy: 1e-8)
        let fall = ny.date(from: DateComponents(year: 2024, month: 11, day: 3))!
        XCTAssertEqual(try LocalDayWindow.interval(for: fall, calendar: ny).duration, 25 * 3600)
    }
    func testHeartBaselineWindowsUseLocalDaysAcrossDST() throws {
        var ny = calendar; ny.timeZone = TimeZone(identifier: "America/New_York")!
        let selected = try XCTUnwrap(ny.date(from: DateComponents(year: 2024, month: 3, day: 12)))
        let end = try XCTUnwrap(ny.date(byAdding: .day, value: 1, to: selected))
        func sample(_ offset: Int, minute: Int = 0) -> RecoverySample {
            let date = ny.date(byAdding: .day, value: offset, to: selected)!.addingTimeInterval(Double(3600 + minute * 60))
            return RecoverySample(id: UUID(), date: date, value: 50, source: "fixture")
        }
        let samples = (3...22).map { sample(-$0) } + [sample(-1), sample(-1, minute: 1), sample(0)]
        let result = RecoveryScoring.heart(samples, hrv: true, day: selected, now: end, calendar: ny, c: .init())
        XCTAssertEqual(result.score, 50)
        XCTAssertEqual(result.baselineWindow?.start, ny.date(byAdding: .day, value: -28, to: selected))
        XCTAssertEqual(result.recentWindow?.start, ny.date(byAdding: .day, value: -2, to: selected))
        XCTAssertEqual(result.recentWindow?.duration, 71 * 3600)
    }
    func testActionStatesAndRealScoresNeverUseSampleProductionValues() throws {
        let emptyRecovery = RecoveryScoring.combine([], partial: true)
        let energy = DashboardEnergyEstimate.make(assessment: try assessment(food: nil, active: nil), configuration: .init(), calendar: calendar)
        for kind in DashboardRingKind.allCases {
            let state = DashboardRingState.wellness(kind, strain: nil, recovery: emptyRecovery, energy: energy, loading: false)
            XCTAssertFalse(state.status.contains("Unavailable")); XCTAssertFalse(state.value.contains("%"))
        }
        let sleepOnly = RecoveryScoring.combine([RecoveryComponent(id: "Sleep", score: 75, weight: 40, detail: "fixture")], partial: true)
        XCTAssertEqual(DashboardRingState.wellness(.recovery, strain: nil, recovery: sleepOnly, energy: energy, loading: false).value, "75")
    }
    func testInvalidHistorySettingsFailSafely() {
        var c = ScoringConfiguration(); c.recentDays = 100
        XCTAssertThrowsError(try c.validated())
        c.recentDays = 0; XCTAssertThrowsError(try c.validated())
        c = ScoringConfiguration(); c.sleepWeight = 0; c.hrvWeight = 0; c.restingHRWeight = 0; c.loadWeight = 0
        XCTAssertThrowsError(try c.validated())
    }
    func testConflictingSameIDIsNotArbitrarilySelected() throws {
        let first = session(); var conflict = first; conflict.rpe = 8
        XCTAssertNil(try load([first, conflict]).value)
        XCTAssertNil(try load([conflict, first]).value)
    }
    func testConflictingHeartIDsAndComponentsAreNotArbitrarilySelected() {
        let base = samples(baseline: 50, recent: 50)
        let last = base.last!
        let conflict = RecoverySample(id: last.id, date: last.date, value: 70, source: last.source)
        let result = RecoveryScoring.heart(base + [conflict], hrv: true, day: day, now: now, calendar: calendar, c: .init())
        XCTAssertNil(result.score, "Conflicting newest ID is excluded, leaving insufficient recent days")
        let otherID = RecoverySample(id: UUID(), date: last.date, value: 70, source: last.source)
        XCTAssertNil(RecoveryScoring.heart(base + [otherID], hrv: true, day: day, now: now, calendar: calendar, c: .init()).score)
        let a = RecoveryComponent(id: "same", score: 75, weight: 40, detail: "")
        let b = RecoveryComponent(id: "same", score: 80, weight: 40, detail: "")
        XCTAssertNil(RecoveryScoring.combine([a, b], partial: false).score)
    }
    func testConflictingLoadDaysDoNotSatisfyCoverage() {
        let data = history(21)
        let conflict = DailyLoad(day: data[0].day, value: 999, unit: .sessionRPE, partial: false, notes: [], duplicateCount: 0)
        XCTAssertNil(RecoveryScoring.training(history: data + [conflict], day: day, calendar: calendar, c: .init()).score)
    }
    func testMixedLoadModesCannotHideKnownTrainingDays() {
        let mixed = history().enumerated().map { index, value in
            DailyLoad(day: value.day, value: value.value, unit: index < 7 ? .sessionRPE : .active, partial: false, notes: [], duplicateCount: 0)
        }
        XCTAssertNil(RecoveryScoring.training(history: mixed, day: day, calendar: calendar, c: .init()).score)
    }
    func testRPEJSONCompatibilityAndValidation() throws {
        let old = Data("{\"id\":\"00000000-0000-4000-8000-000000000001\",\"name\":\"Legacy\",\"start\":0,\"status\":\"active\",\"exercises\":[]}".utf8)
        var draft = try JSONDecoder().decode(StrengthDraft.self, from: old)
        XCTAssertNil(draft.sessionRPE)
        draft.sessionRPE = 7
        XCTAssertEqual(try JSONDecoder().decode(StrengthDraft.self, from: JSONEncoder().encode(draft)).sessionRPE, 7)
        draft.sessionRPE = -1; XCTAssertThrowsError(try draft.validated(now: now))
        var cardio = CardioDraft(start: day, durationSeconds: 60)
        cardio.sessionRPE = 11; XCTAssertThrowsError(try cardio.validated(now: now))
    }
    func testAdvancedPreviewUsesSameSourceRobustBaselineAndDoesNotReplaceLegacy() {
        let c = AdvancedScoringConfiguration(enabled: true)
        let values = (1...20).map { offset in AdvancedVitalSample(id: UUID(), date: date(-offset).addingTimeInterval(3600), value: 50, source: "watch", kind: .sdnn) }
            + [AdvancedVitalSample(id: UUID(), date: day.addingTimeInterval(3600), value: 60, source: "watch", kind: .sdnn)]
        let advanced = AdvancedRecoveryScoring.vital(.sdnn, samples: values, day: day, now: now, calendar: calendar, weight: 35, higherBetter: true, configuration: c)
        XCTAssertGreaterThan(advanced.score ?? 0, 50)
        XCTAssertEqual(advanced.source, "watch")
        let legacy = RecoveryScoring.heart(values.map { RecoverySample(id: $0.id, date: $0.date, value: $0.value, source: $0.source) }, hrv: true, day: day, now: now, calendar: calendar, c: .init())
        XCTAssertNotEqual(advanced.id, legacy.id)
        let unauthorized = AdvancedRecoveryScoring.vital(.oxygenSaturation, samples: [], day: day, now: now, calendar: calendar, weight: 1, higherBetter: true, configuration: c)
        XCTAssertNil(unauthorized.score)
    }
    func testAdvancedCardiovascularLoadRejectsSparseCoverageAndUsesExplicitAssumptions() {
        let start = day, end = day.addingTimeInterval(3600)
        let points = stride(from: 0.0, through: 3600, by: 60).map { HeartRatePoint(id: UUID(), date: start.addingTimeInterval($0), bpm: 140, source: "watch") }
        let observed = AdvancedStrainScoring.cardiovascular(points: points, start: start, end: end, restingHR: 55, maximumHR: 190)
        XCTAssertNotNil(observed.trimp); XCTAssertGreaterThan(observed.coverage, 0.9)
        let sparse = AdvancedStrainScoring.cardiovascular(points: [points[0], points[1]], start: start, end: end, restingHR: 55, maximumHR: 190)
        XCTAssertNil(sparse.trimp)
    }
    func testInsightsAreDeterministicAndSuppressIncompleteRecovery() {
        let empty = RecoveryScoring.combine([], partial: false)
        let missing = InsightEngine.daily(recovery: empty, strain: nil, sleepObservation: nil, partial: false)
        XCTAssertEqual(missing.first?.kind, .setup)
        XCTAssertTrue(missing.contains { $0.title == "Activity load unavailable" })
        let recovery = RecoveryScoring.combine([RecoveryComponent(id: "HRV SDNN", score: 70, weight: 30, detail: "Same source")], partial: false)
        let load = DailyLoad(day: day, value: 250, unit: .sessionRPE, partial: false, notes: ["Observed fixture"], duplicateCount: 0)
        let strain = StrainEstimate(load: load, score: 85, target: 300, personalized: true, historyDays: 14)
        let first = InsightEngine.daily(recovery: recovery, strain: strain, sleepObservation: "Recorded sleep was similar to recent nights.", partial: false)
        XCTAssertEqual(first, InsightEngine.daily(recovery: recovery, strain: strain, sleepObservation: "Recorded sleep was similar to recent nights.", partial: false))
        XCTAssertEqual(first.count, 3)
        XCTAssertFalse(first.contains { $0.kind == .suggestion })
        let partial = InsightEngine.daily(recovery: recovery, strain: strain, sleepObservation: nil, partial: true)
        XCTAssertEqual(partial.count, 2)
        XCTAssertTrue(partial.allSatisfy { $0.summary.contains("Provisional") })
        let missingRecovery = InsightEngine.daily(recovery: empty, strain: strain, sleepObservation: nil, partial: false)
        XCTAssertFalse(missingRecovery.contains { $0.kind == .suggestion })
        XCTAssertTrue(missingRecovery.contains { $0.title == "Recovery is building context" })
    }
    func testWidgetSnapshotRoundTripAndFreshnessContract() throws {
        let snapshot = PersonalFitnessWidgetSnapshot(generatedAt: now, localDayStart: day, timeZoneIdentifier: "UTC", privacy: .showValues,
            recovery: WidgetMetricSnapshot(kind: .recovery, score: 73, state: .current, sourceLabel: "2 eligible inputs"),
            strain: WidgetMetricSnapshot(kind: .strain, score: 41, state: .partial, sourceLabel: "Observed activity"),
            nutrition: WidgetNutritionSnapshot(consumedCalories: 1_200, calorieGoal: 2_000, state: .partial), activeWorkout: nil)
        let decoded = try WidgetSnapshotContract.decode(WidgetSnapshotContract.encode(snapshot), now: now)
        XCTAssertEqual(decoded, snapshot)
        XCTAssertEqual(WidgetSnapshotContract.freshness(of: snapshot, now: now.addingTimeInterval(7_200)), .partial)
        XCTAssertEqual(WidgetSnapshotContract.freshness(of: snapshot, now: now.addingTimeInterval(7_201)), .unavailable)
        XCTAssertEqual(WidgetSnapshotContract.nextRefresh(after: snapshot), now.addingTimeInterval(7_200))
    }
    func testWidgetSnapshotMakesMissingAndPrivateDataHonest() {
        let workout = WidgetActiveWorkoutSnapshot(name: "Strength A", completedSets: 2, plannedSets: 4, startedAt: now)
        let snapshot = PersonalFitnessWidgetSnapshot(generatedAt: now, localDayStart: day, timeZoneIdentifier: "UTC", privacy: .hideValues,
            recovery: WidgetMetricSnapshot(kind: .recovery, score: nil, state: .current, sourceLabel: "No eligible inputs"),
            strain: WidgetMetricSnapshot(kind: .strain, score: 66, state: .current, sourceLabel: "Observed activity"),
            nutrition: WidgetNutritionSnapshot(consumedCalories: nil, calorieGoal: 2_000, state: .current), activeWorkout: workout).redacted()
        XCTAssertEqual(snapshot.recovery.state, .unavailable)
        XCTAssertNil(snapshot.strain.score); XCTAssertEqual(snapshot.strain.sourceLabel, "Open PersonalFitness to view")
        XCTAssertNil(snapshot.nutrition.consumedCalories); XCTAssertEqual(snapshot.activeWorkout?.name, "Workout in progress")
    }
    func testWidgetDeepLinksAndContractRejectsUnsupportedVersions() throws {
        XCTAssertEqual(WidgetSnapshotContract.destination(for: try XCTUnwrap(WidgetSnapshotContract.deepLink(.nutrition))), .nutrition)
        let json = #"{"schemaVersion":2,"generatedAt":0,"localDayStart":0,"timeZoneIdentifier":"UTC","privacy":"showValues","recovery":{"kind":"recovery","score":null,"state":"unavailable","sourceLabel":""},"strain":{"kind":"strain","score":null,"state":"unavailable","sourceLabel":""},"nutrition":{"consumedCalories":null,"calorieGoal":null,"state":"unavailable"}}"#.data(using: .utf8)!
        XCTAssertThrowsError(try WidgetSnapshotContract.decode(json, now: now))
    }
}
