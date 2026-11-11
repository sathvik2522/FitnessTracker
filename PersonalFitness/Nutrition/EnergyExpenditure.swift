import Foundation

/// An expenditure component over one shared query window. Health values remain
/// estimates from Apple Health; prediction never masquerades as a measurement.
struct ExpenditureComponent: Codable, Equatable, Sendable {
    enum Source: String, Codable, Sendable {
        case healthKit = "Apple Health cumulative kilocalories"
        case mifflin = "Mifflin–St Jeor prediction"
        case activityAssumption = "Explicit activity assumption"
    }
    let kcal: Double
    let source: Source
    var predicted: Bool { source != .healthKit }
}

struct EnergyExpenditureRecord: Codable, Equatable, Sendable {
    let start: Date
    let end: Date
    let timeZoneIdentifier: String
    let calculatedAt: Date
    let partial: Bool
    let resting: ExpenditureComponent?
    let active: ExpenditureComponent?
    let total: Double?
    let assumptions: String
    let inputIssues: [String]
    let profile: ExpenditureProfile?
    let explicitDailyEstimate: Double?
    var predicted: Bool { explicitDailyEstimate != nil || resting?.predicted == true || active?.predicted == true }
    var key: String { Self.key(start: start, timeZone: timeZoneIdentifier) }
    static func key(start: Date, timeZone: String) -> String { "\(start.timeIntervalSince1970)|\(timeZone)" }
    func matches(_ window: LocalDayWindow) -> Bool {
        start == window.start && end == window.end && timeZoneIdentifier == window.timeZoneIdentifier && partial == window.isPartial
    }
    func validated() throws -> Self {
        guard end > start, TimeZone(identifier: timeZoneIdentifier) != nil,
              calculatedAt.timeIntervalSince1970.isFinite, start.timeIntervalSince1970.isFinite, end.timeIntervalSince1970.isFinite,
              [resting?.kcal, active?.kcal, total].compactMap({ $0 }).allSatisfy({ $0.isFinite && $0 >= 0 }),
              total != nil, predicted, !partial else { throw ScoringError.configuration }
        if let profile { _ = try profile.validated() }
        var local = Calendar(identifier: .gregorian); local.timeZone = TimeZone(identifier: timeZoneIdentifier)!
        guard let interval = local.dateInterval(of: .day, for: start), interval.start == start, interval.end == end else { throw ScoringError.configuration }
        if explicitDailyEstimate == nil {
            guard profile != nil else { throw ScoringError.configuration }
            guard let resting, let active, let total,
                  abs(total - (resting.kcal + active.kcal)) < 1e-8 else { throw ScoringError.configuration }
        }
        if let explicitDailyEstimate { guard (500...10_000).contains(explicitDailyEstimate), total == explicitDailyEstimate else { throw ScoringError.configuration } }
        return self
    }
}

/// Accepts only canonical, reconciled aggregates. There is intentionally no
/// workout-calorie input. A multiplier estimates the missing active component
/// from predicted REE; it never multiplies Health resting energy.
enum EnergyExpenditureService {
    static func restingPrediction(_ profile: ExpenditureProfile?) -> Double? {
        guard let profile, (try? profile.validated()) != nil else { return nil }
        let value = 10 * profile.weightKG + 6.25 * profile.heightCM - 5 * profile.age
            + (profile.parameter == .male ? 5 : -161)
        return value.isFinite && value > 0 ? value : nil
    }
    static func calculate(assessment: EnergyAssessment, configuration c: ScoringConfiguration,
                          calendar: Calendar, now: Date = .now,
                          historical: EnergyExpenditureRecord? = nil) -> EnergyExpenditureRecord {
        let w = assessment.window
        func observed(_ value: Double?) -> ExpenditureComponent? {
            value.flatMap { $0.isFinite && $0 >= 0 ? ExpenditureComponent(kcal: $0, source: .healthKit) : nil }
        }
        var resting = observed(assessment.balance.resting)
        var active = observed(assessment.balance.active)
        func record(_ total: Double?, _ notes: String, profile: ExpenditureProfile? = nil, explicit: Double? = nil) -> EnergyExpenditureRecord {
            EnergyExpenditureRecord(start: w.start, end: w.end, timeZoneIdentifier: w.timeZoneIdentifier,
                calculatedAt: now, partial: w.isPartial, resting: resting, active: active, total: total,
                assumptions: notes, inputIssues: assessment.expenditureReasons.map(\.rawValue), profile: profile, explicitDailyEstimate: explicit)
        }
        // Complete live Health aggregates always have priority. Archived predictions
        // remain separately retained, and are shown again if live reads disappear.
        if let r = resting, let a = active, (r.kcal + a.kcal).isFinite {
            return record(r.kcal + a.kcal, "Apple Health resting + active, same local-day window. Coverage is unverified; source and device overlap are delegated to HealthKit cumulative statistics.")
        }
        if let historical, !w.isPartial, historical.matches(w), (try? historical.validated()) != nil { return historical }
        guard (try? c.validated()) != nil, calendar.timeZone.identifier == w.timeZoneIdentifier,
              let day = try? LocalDayWindow.interval(for: w.start, calendar: calendar),
              day.start == w.start, day.duration > 0, w.end <= day.end, w.end >= w.start else {
            return record(nil, "Invalid settings or mismatched local-day window. Review setup.")
        }
        // A deliberately configured total is an independent fallback, never added
        // to a partial Health component. Formula-based components are preferred
        // where an explicit profile permits compatible mixed-source arithmetic.
        let fraction = min(1, max(0, w.end.timeIntervalSince(w.start) / day.duration))
        if let ree = restingPrediction(c.profile), let profile = c.profile {
            if resting == nil { resting = ExpenditureComponent(kcal: ree * fraction, source: .mifflin) }
            if active == nil, let multiplier = profile.multiplier { active = ExpenditureComponent(kcal: ree * (multiplier - 1) * fraction, source: .activityAssumption) }
            if let r = resting, let a = active, (r.kcal + a.kcal).isFinite {
                return record(r.kcal + a.kcal,
                    "Missing resting: (10 × kg + 6.25 × cm − 5 × age + coefficient). Missing active: predicted resting × (explicit multiplier − 1). Health components take priority individually. Predictions are prorated by elapsed seconds / actual local-day seconds. No multiplier is applied to Health resting energy; no workouts are added. Profile weight is explicitly selected in settings; not inferred or automatically carried from Health. Individual error can be substantial.", profile: profile)
            }
        }
        if let explicit = c.dailyExpenditure {
            resting = observed(assessment.balance.resting); active = observed(assessment.balance.active)
            // Leave observed components inspectable, but do not pretend this total
            // decomposes into measured resting and active energy.
            return record(explicit * fraction, "Explicit independent full-day expenditure, elapsed-time prorated by the actual local day's length. Readable Health components are not added to this total.", explicit: explicit)
        }
        return record(nil, "Connect Apple Health or provide an explicit equation profile / daily estimate. Predicting missing active energy additionally needs an explicit activity multiplier. Missing resting or active energy is not zero.", profile: c.profile)
    }
}
