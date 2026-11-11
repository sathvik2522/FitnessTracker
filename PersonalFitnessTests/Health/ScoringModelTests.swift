import XCTest
import SwiftData
import HealthKit
@testable import PersonalFitness

@MainActor private final class ScoringHealthStub: ScoringHealthReading {
    var isAvailable = true
    var hasCompletedRequest = false
    var hasCompletedRecoveryRequest = false
    var authorizations = 0, signalReads = 0, historyReads = 0
    var suspend = false
    var provideActiveHistory = false
    var suppliedSignals = RecoveryReadings(hrv: .unavailable, restingHR: .unavailable)
    var continuation: CheckedContinuation<RecoveryReadings, Never>?
    func requestRecoveryAccess() async throws { authorizations += 1; hasCompletedRecoveryRequest = true }
    func readRecovery(start: Date, end: Date) async -> RecoveryReadings {
        signalReads += 1
        if suspend { return await withCheckedContinuation { continuation = $0 } }
        return suppliedSignals
    }
    func readLoadHistory(windows: [LocalDayWindow]) async -> [HealthLoadDay] {
        historyReads += 1
        return provideActiveHistory ? windows.map { HealthLoadDay(window: $0, active: .value(100), workouts: .unavailable) } : []
    }
}
final class ScoringModelTests: XCTestCase {
    @MainActor func testNewHeartPermissionsAreSeparateAndUnitsConvert() {
        XCTAssertEqual(Set(HealthKitService.recoveryReadTypes.map(\.identifier)), Set([HKQuantityTypeIdentifier.heartRateVariabilitySDNN.rawValue, HKQuantityTypeIdentifier.restingHeartRate.rawValue]))
        XCTAssertEqual(HealthKitService.readTypes.count, 5)
        XCTAssertEqual(HealthKitService.measurement(HKQuantity(unit: .second(), doubleValue: 0.05), unit: .secondUnit(with: .milli)).value, 50)
        XCTAssertEqual(HealthKitService.measurement(HKQuantity(unit: .count().unitDivided(by: .minute()), doubleValue: 60), unit: .count().unitDivided(by: .minute())).value, 60)
    }
    @MainActor func testEnergyUsesBasalAndActiveReadTypesAndKilocalorieConversion() throws {
        XCTAssertTrue(HealthKitService.readTypes.contains(HKObjectType.quantityType(forIdentifier: .basalEnergyBurned)!))
        XCTAssertTrue(HealthKitService.readTypes.contains(HKObjectType.quantityType(forIdentifier: .activeEnergyBurned)!))
        XCTAssertEqual(HealthKitService.measurement(HKQuantity(unit: .jouleUnit(with: .kilo), doubleValue: 4.184), unit: .kilocalorie()).value ?? -1, 1, accuracy: 1e-10)
        XCTAssertNil(HealthKitService.measurement(nil, unit: .kilocalorie()).value)
        XCTAssertEqual(HealthKitService.measurement(HKQuantity(unit: .kilocalorie(), doubleValue: 0), unit: .kilocalorie()).value, 0)
        XCTAssertNil(HealthKitService.measurement(HKQuantity(unit: .kilocalorie(), doubleValue: -1), unit: .kilocalorie()).value)
        let calendar = Calendar.current
        let day = calendar.startOfDay(for: Date.now)
        let zero = try LocalDayWindow(day: day, now: day, calendar: calendar)
        XCTAssertThrowsError(try HealthKitService.cumulativeDescriptor(.basalEnergyBurned, window: zero))
        let valid = try LocalDayWindow(day: day, now: day.addingTimeInterval(3600), calendar: calendar)
        XCTAssertNoThrow(try HealthKitService.cumulativeDescriptor(.basalEnergyBurned, window: valid))
    }
    @MainActor func testLocalLoadWorksWithoutAnyHealthReadOrAutomaticRequest() async throws {
        let container = try AppPersistence.makeContainer(inMemory: true), store = WorkoutStore(context: container.mainContext)
        let calendar = Calendar.current
        let day = try XCTUnwrap(calendar.date(byAdding: .day, value: -1, to: calendar.startOfDay(for: Date.now)))
        let now = try XCTUnwrap(calendar.date(bySettingHour: 12, minute: 0, second: 0, of: day))
        var session = try store.start()
        session.start = now.addingTimeInterval(-1200)
        session.sessionRPE = 6
        session.exercises = [SessionExercise(exercise: ExerciseSnapshot(name: "Fixture"), sets: [TrainingSet(reps: 1, completed: true)])]
        try store.saveSession(session.finished(at: now))
        let stub = ScoringHealthStub(), model = ScoringDashboardModel(health: stub)
        await model.load(day: day, context: container.mainContext, now: now, calendar: calendar)
        XCTAssertEqual(stub.authorizations, 0); XCTAssertEqual(stub.signalReads, 0); XCTAssertEqual(stub.historyReads, 0)
        XCTAssertEqual(model.localSessions.first?.rpe, 6)
        let estimate = model.estimates(day: day, snapshot: nil, sleep: nil, configuration: .init(), now: now, calendar: calendar)
        XCTAssertEqual(estimate.0?.load.value, 120); XCTAssertEqual(estimate.0?.score, 40)
        XCTAssertNil(estimate.1.score)
    }
    @MainActor func testOldHeartResponseCannotReplaceNewDayAndRefreshIsNotAuthorization() async throws {
        let container = try AppPersistence.makeContainer(inMemory: true)
        let context = container.mainContext
        defer { withExtendedLifetime(container) {} }
        let stub = ScoringHealthStub(); stub.hasCompletedRecoveryRequest = true; stub.suspend = true
        let model = ScoringDashboardModel(health: stub), now = Date.now
        let old = Task { await model.load(day: now, context: context, now: now) }
        for _ in 0..<1000 {
            if stub.continuation != nil { break }
            try await Task.sleep(for: .milliseconds(1))
        }
        XCTAssertNotNil(stub.continuation)
        guard stub.continuation != nil else { old.cancel(); return }
        stub.suspend = false
        let previous = try XCTUnwrap(Calendar.current.date(byAdding: .day, value: -30, to: now))
        await model.load(day: previous, context: context, now: now)
        let fake = RecoverySample(id: UUID(), date: now, value: 50, source: "fixture")
        stub.continuation?.resume(returning: RecoveryReadings(hrv: .value([fake]), restingHR: .unavailable))
        await old.value
        XCTAssertNil(model.readings.hrv.value); XCTAssertFalse(model.loading); XCTAssertEqual(stub.authorizations, 0)
        await model.connect(day: previous, context: context, now: now)
        XCTAssertEqual(stub.authorizations, 1)
    }
    @MainActor func testRPEAndAllEightTablesSurviveDiskReopenAndExportRemainsCompatible() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".store")
        defer { for suffix in ["", "-wal", "-shm"] { try? FileManager.default.removeItem(atPath: url.path + suffix) } }
        let id = UUID()
        do {
            let c = try AppPersistence.makeContainer(url: url)
            try WorkoutStore(context: c.mainContext).saveCardio(CardioDraft(id: id, start: Date.now.addingTimeInterval(-3600), durationSeconds: 600, sessionRPE: 7))
        }
        let reopened = try AppPersistence.makeContainer(url: url)
        XCTAssertEqual(try reopened.mainContext.fetch(FetchDescriptor<CardioSession>()).first?.draft().sessionRPE, 7)
        let export = try LocalDataExport.capture(context: reopened.mainContext)
        XCTAssertEqual(export.cardioSessions.first?.id, id)
        XCTAssertEqual(try JSONDecoder().decode(CardioDraft.self, from: XCTUnwrap(export.cardioSessions.first).draftData).sessionRPE, 7)
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: export.encoded()) as? [String: Any])
        for version in [1, 2] {
            object["formatVersion"] = version
            XCTAssertEqual(try LocalDataExport.decode(JSONSerialization.data(withJSONObject: object)).formatVersion, version)
        }
        XCTAssertFalse(reopened.mainContext.hasChanges)
    }
    @MainActor func testRecoveryUsesConsistentAllDaysFallbackInsteadOfOmittingWorkoutDays() async throws {
        let container = try AppPersistence.makeContainer(inMemory: true)
        let calendar = Calendar.current, now = Date.now
        let day = try XCTUnwrap(calendar.date(byAdding: .day, value: -1, to: calendar.startOfDay(for: now)))
        for offset in 0...7 {
            let start = try XCTUnwrap(calendar.date(byAdding: .day, value: -offset, to: day)).addingTimeInterval(3600)
            try WorkoutStore(context: container.mainContext).saveCardio(CardioDraft(start: start, durationSeconds: 600, sessionRPE: 6))
        }
        let stub = ScoringHealthStub(); stub.hasCompletedRequest = true; stub.provideActiveHistory = true
        let model = ScoringDashboardModel(health: stub)
        await model.load(day: day, context: container.mainContext, now: now, calendar: calendar)
        let values = model.estimates(day: day, snapshot: nil, sleep: nil, configuration: .init(), now: now, calendar: calendar)
        XCTAssertEqual(values.0?.load.unit, .sessionRPE)
        let component = try XCTUnwrap(values.1.components.first { $0.id == "Recent training load" })
        XCTAssertEqual(component.score ?? -1, 100, accuracy: 1e-8)
        XCTAssertEqual(component.source, "Apple Health active-energy aggregates")
        XCTAssertTrue(component.detail.contains("same activity-load engine"))
        XCTAssertEqual(stub.authorizations, 0)
    }
    @MainActor func testCachedHeartDetailsKeepActualQueryCutoffUntilExplicitRefresh() async throws {
        let container = try AppPersistence.makeContainer(inMemory: true)
        let calendar = Calendar.current
        let day = try XCTUnwrap(calendar.date(byAdding: .day, value: -1, to: calendar.startOfDay(for: Date.now)))
        let first = try XCTUnwrap(calendar.date(bySettingHour: 12, minute: 0, second: 0, of: day))
        let baseline = try (3...22).map { offset -> RecoverySample in
            let d = try XCTUnwrap(calendar.date(byAdding: .day, value: -offset, to: day))
            return RecoverySample(id: UUID(), date: d.addingTimeInterval(3600), value: 50, source: "fixture")
        }
        let yesterday = try XCTUnwrap(calendar.date(byAdding: .day, value: -1, to: day))
        let recent = [yesterday.addingTimeInterval(3600), yesterday.addingTimeInterval(7200), day.addingTimeInterval(3600)]
            .map { RecoverySample(id: UUID(), date: $0, value: 50, source: "fixture") }
        let stub = ScoringHealthStub(); stub.hasCompletedRecoveryRequest = true
        stub.suppliedSignals = RecoveryReadings(hrv: .value(baseline + recent), restingHR: .unavailable)
        let model = ScoringDashboardModel(health: stub)
        await model.load(day: day, context: container.mainContext, now: first, calendar: calendar)
        let later = first.addingTimeInterval(60)
        await model.load(day: day, context: container.mainContext, now: later, calendar: calendar)
        XCTAssertEqual(stub.signalReads, 1); XCTAssertEqual(model.readWindow?.end, first)
        let component = model.estimates(day: day, snapshot: nil, sleep: nil, configuration: .init(), now: later, calendar: calendar).1.components.first { $0.id == "HRV SDNN" }
        XCTAssertEqual(component?.score, 50); XCTAssertEqual(component?.recentWindow?.end, first)
        await model.load(day: day, context: container.mainContext, now: later, calendar: calendar, force: true)
        XCTAssertEqual(stub.signalReads, 2); XCTAssertEqual(model.readWindow?.end, later)
    }
    @MainActor func testClosedDayEnergyPredictionPersistsAndExportsWithoutRewritingFood() throws {
        let suite = "EnergyHistoryTests." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let prefs = ScoringPreferences(defaults: defaults)
        var configuration = prefs.configuration
        configuration.profile = ExpenditureProfile(age: 30, heightCM: 180, weightKG: 80, parameter: .male, multiplier: 1.5)
        try prefs.save(configuration)
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let day = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 10, day: 19)))
        let window = try LocalDayWindow(day: day, now: day.addingTimeInterval(86400), calendar: calendar)
        func assessment(_ calories: Double) -> EnergyAssessment {
            EnergyReconciliation.assess(window: window, food: FoodEnergy(reading: .value(calories), window: window), aggregates: [])
        }
        prefs.preserveHistoricalEstimate(assessment(2000), calendar: calendar, now: day.addingTimeInterval(90000))
        XCTAssertEqual(prefs.history.count, 1)
        configuration.profile?.weightKG = 100; try prefs.save(configuration)
        prefs.preserveHistoricalEstimate(assessment(2200), calendar: calendar, now: day.addingTimeInterval(91000))
        let reopened = ScoringPreferences(defaults: defaults)
        XCTAssertEqual(reopened.history.count, 1); XCTAssertEqual(reopened.history.first?.profile?.weightKG, 80)
        XCTAssertEqual(reopened.estimate(assessment(2200), calendar: calendar).expenditure, 2670)
        XCTAssertEqual(reopened.estimate(assessment(2200), calendar: calendar).balance, -470)
        let container = try AppPersistence.makeContainer(inMemory: true)
        defer { withExtendedLifetime(container) {} }
        let exported = try LocalDataExport.capture(context: container.mainContext, preferencesDefaults: defaults)
        XCTAssertEqual(try LocalDataExport.decode(exported.encoded()).preferences?.energyHistory, reopened.history)
        let partial = try LocalDayWindow(day: day.addingTimeInterval(86400), now: day.addingTimeInterval(90000), calendar: calendar)
        let current = EnergyReconciliation.assess(window: partial, food: FoodEnergy(reading: .missing, window: partial), aggregates: [])
        prefs.preserveHistoricalEstimate(current, calendar: calendar)
        XCTAssertEqual(prefs.history.count, 1, "Current-day predictions must recalculate rather than be frozen")
    }
    @MainActor func testCorruptEnergyHistoryIsNeverSilentlyReplacedBySettingsSave() throws {
        let suite = "EnergyCorruptTests." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let original = Data("invalid history fixture".utf8)
        defaults.set(original, forKey: ScoringPreferences.historyKey)
        let prefs = ScoringPreferences(defaults: defaults)
        XCTAssertNotNil(prefs.error)
        var c = prefs.configuration; c.dailyExpenditure = 2400
        try prefs.save(c)
        XCTAssertNotNil(prefs.error)
        XCTAssertEqual(defaults.data(forKey: ScoringPreferences.historyKey), original)
        XCTAssertThrowsError(try ScoringPreferences.savedHistory(defaults: defaults))
    }
    @MainActor func testScoringSettingsValidateBeforeSaveAndIncludeOnlyExplicitSettingsInExport() throws {
        let suite = "ScoringTests." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let preferences = ScoringPreferences(defaults: defaults)
        XCTAssertNil(preferences.configuration.dailyExpenditure); XCTAssertNil(preferences.configuration.profile)
        var c = preferences.configuration; c.rpeTarget = 400; c.dailyExpenditure = 2400
        c.profile = ExpenditureProfile(age: 30, heightCM: 180, weightKG: 80, parameter: .male, multiplier: 1.5)
        try preferences.save(c)
        var invalid = c; invalid.rpeTarget = 0; XCTAssertThrowsError(try preferences.save(invalid))
        XCTAssertEqual(ScoringPreferences(defaults: defaults).configuration, c)
        let container = try AppPersistence.makeContainer(inMemory: true)
        let context = container.mainContext
        defer { withExtendedLifetime(container) {} }
        let export = try LocalDataExport.capture(context: context, preferencesDefaults: defaults)
        XCTAssertEqual(export.preferences?.scoring, c)
        XCTAssertEqual(try LocalDataExport.decode(export.encoded()).preferences?.scoring, c)
    }
}
