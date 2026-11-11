import Foundation

/// Product heuristics, not clinical thresholds. Units and coverage never mix.
struct ScoringConfiguration: Codable, Equatable, Sendable {
    var personalizeLoad = true
    var targetScale = 1.0
    var rpeTarget = 300.0
    var minutesTarget = 60.0
    var activeEnergyTarget = 500.0
    var stepsTarget = 10_000.0
    var minimumTargetDays = 7
    var sleepTargetMinutes = 480.0
    var sleepWeight = 40.0
    var hrvWeight = 30.0
    var restingHRWeight = 20.0
    var loadWeight = 10.0
    var hrvSlope = 100.0
    var restingHRPenalty = 5.0
    var baselineDays = 28
    var minimumBaselineDays = 14
    var recentDays = 3
    var minimumRecentDays = 2
    var minimumLoadDays = 21
    var minimumRecentLoadDays = 5
    var dailyExpenditure: Double? = nil
    var profile: ExpenditureProfile? = nil

    func validated() throws -> Self {
        let positive = [targetScale, rpeTarget, minutesTarget, activeEnergyTarget, stepsTarget, sleepTargetMinutes, hrvSlope, restingHRPenalty]
        let weights = [sleepWeight, hrvWeight, restingHRWeight, loadWeight]
        guard positive.allSatisfy({ $0.isFinite && $0 > 0 && $0 <= 100_000 }),
              weights.allSatisfy({ $0.isFinite && $0 >= 0 && $0 <= 100 }), weights.reduce(0, +) > 0,
              (1...28).contains(minimumTargetDays), (21...28).contains(baselineDays),
              (2...7).contains(recentDays),
              (7...baselineDays - recentDays).contains(minimumBaselineDays), (2...recentDays).contains(minimumRecentDays),
              (7...28).contains(minimumLoadDays), (2...7).contains(minimumRecentLoadDays),
              (180...900).contains(sleepTargetMinutes),
              dailyExpenditure.map({ $0.isFinite && (500...10_000).contains($0) }) ?? true else { throw ScoringError.configuration }
        if let profile { _ = try profile.validated() }
        return self
    }
}
enum ScoringError: String, LocalizedError {
    case configuration = "Check scoring settings: targets must be positive, weights nonnegative with a positive total, and history requirements within their supported ranges."
    case profile = "The equation needs explicit adult age (19–78 years), height (100–250 cm), weight (30–350 kg), equation parameter; an optional activity multiplier must be 1–2.5. These are input limits, not health recommendations."
    var errorDescription: String? { rawValue }
}

struct ExpenditureProfile: Codable, Equatable, Sendable {
    enum EquationParameter: String, Codable, CaseIterable { case male, female }
    var age: Double
    var heightCM: Double
    var weightKG: Double
    var parameter: EquationParameter
    var multiplier: Double? = nil
    func validated() throws -> Self {
        guard [age, heightCM, weightKG].allSatisfy(\.isFinite),
              (19...78).contains(age), (100...250).contains(heightCM), (30...350).contains(weightKG),
              multiplier.map({ $0.isFinite && (1...2.5).contains($0) }) ?? true else { throw ScoringError.profile }
        return self
    }
    var fullDayEstimate: Double? {
        guard (try? validated()) != nil, let multiplier else { return nil }
        return EnergyExpenditureService.restingPrediction(self).map { $0 * multiplier }
    }
}

enum ScoringQualityRules {
    static let historyDays = 28
    static let recentLoadDays = 7
    static let hrvRecentSamples = 3
    static let restingHRRecentSamples = 2
    static let duplicateOverlapFraction = 0.8
    static let workoutTimeToleranceSeconds = 300.0
    static let durationToleranceMinutes = 1.0
    static let cacheSeconds = 300.0
    static let hrvRange = 5.0...300.0
    static let restingHRRange = 30.0...120.0
    static let madScale = 1.4826
    static let baselineMADMultiplier = 3.0
    static let recentMADMultiplier = 4.0
    static let hrvBaselineRelativeFloor = 0.5
    static let restingHRBaselineFloor = 10.0
    static let restingHRRecentFloor = 25.0
    static let loadIncreasePenalty = 50.0
    static let maximumRecentAgeSeconds = 36.0 * 3600
}

enum ScoreMath {
    static func bounded(_ value: Double) -> Double? { value.isFinite ? min(100, max(0, value)) : nil }
    static func median(_ values: [Double]) -> Double? {
        let sorted = values.filter(\.isFinite).sorted()
        guard !sorted.isEmpty else { return nil }
        let i = sorted.count / 2
        return sorted.count.isMultiple(of: 2) ? sorted[i - 1] / 2 + sorted[i] / 2 : sorted[i]
    }
}

struct LoadSession: Identifiable, Equatable, Sendable {
    enum Origin: String, Sendable { case manual, health }
    let id: UUID
    let start: Date
    let end: Date
    let activity: WorkoutActivity
    let origin: Origin
    var rpe: Double? = nil
    var durationMinutes: Double? = nil
}
enum LoadUnit: String, Sendable { case sessionRPE = "session-RPE units", minutes = "workout minutes", active = "active kcal", steps = "steps" }
struct DailyLoad: Equatable, Sendable {
    let day: Date
    let value: Double?
    let unit: LoadUnit?
    let partial: Bool
    let notes: [String]
    let duplicateCount: Int
}
struct StrainEstimate: Equatable {
    let load: DailyLoad
    let score: Double?
    let target: Double?
    let personalized: Bool
    let historyDays: Int
    var provisional: Bool { !personalized || load.partial || load.unit != .sessionRPE || load.duplicateCount > 0 }
}

enum ActivityLoad {
    /// Suspected representations are excluded from calculations only; no records
    /// are merged/deleted. Manual records win; overlapping manual logs are kept.
    static func reconcile(_ sessions: [LoadSession], now: Date) -> (sessions: [LoadSession], excluded: Int) {
        let valid = sessions.filter { $0.start.timeIntervalSince1970.isFinite && $0.end.timeIntervalSince1970.isFinite && $0.end > $0.start && $0.end <= now }
            .sorted { $0.origin != $1.origin ? $0.origin == .manual : $0.id.uuidString < $1.id.uuidString }
        var kept: [LoadSession] = [], excluded = 0
        let groups = Dictionary(grouping: valid, by: \.id)
        var candidates: [LoadSession] = []
        for id in groups.keys.sorted(by: { $0.uuidString < $1.uuidString }) {
            let all = groups[id, default: []]
            let preferred = all.contains(where: { $0.origin == .manual }) ? all.filter { $0.origin == .manual } : all
            guard let first = preferred.first, preferred.dropFirst().allSatisfy({ $0 == first }) else { excluded += all.count; continue }
            candidates.append(first); excluded += all.count - 1
        }
        candidates.sort { $0.origin != $1.origin ? $0.origin == .manual : $0.id.uuidString < $1.id.uuidString }
        for session in candidates {
            let matches = session.origin == .health && kept.contains { prior in
                guard prior.activity == session.activity else { return false }
                let overlap = min(prior.end, session.end).timeIntervalSince(max(prior.start, session.start))
                let shorter = min(prior.end.timeIntervalSince(prior.start), session.end.timeIntervalSince(session.start))
                return overlap > 0 && overlap / shorter >= ScoringQualityRules.duplicateOverlapFraction
                    && abs(prior.start.timeIntervalSince(session.start)) <= ScoringQualityRules.workoutTimeToleranceSeconds
                    && abs(prior.end.timeIntervalSince(session.end)) <= ScoringQualityRules.workoutTimeToleranceSeconds
            }
            if matches { excluded += 1 } else { kept.append(session) }
        }
        return (kept, excluded)
    }
    static func day(window: LocalDayWindow, sessions: [LoadSession], active: Double?, steps: Double?, now: Date) -> DailyLoad {
        let matching = sessions.filter { $0.start >= window.start && $0.start < window.end }
        let reconciled = reconcile(matching, now: now)
        var notes = ["Workouts are assigned to their local start day; completed duration may cross midnight."]
        if reconciled.excluded > 0 { notes.append("Excluded \(reconciled.excluded) duplicate/conflicting or possibly overlapping Health representations from load only; saved records are unchanged.") }
        notes.append("Contributing representations: \(reconciled.sessions.filter { $0.origin == .manual }.count) manual, \(reconciled.sessions.filter { $0.origin == .health }.count) Apple Health. No workout calories enter this load sum.")
        let durations = reconciled.sessions.compactMap { session -> (Double, Double?)? in
            let minutes = session.durationMinutes ?? session.end.timeIntervalSince(session.start) / 60
            guard minutes.isFinite, minutes > 0, minutes <= session.end.timeIntervalSince(session.start) / 60 + ScoringQualityRules.durationToleranceMinutes else { return nil }
            return (minutes, SessionEffort.isValid(session.rpe) ? session.rpe : nil)
        }
        let rated = durations.filter { $0.1 != nil }
        let value: Double?, unit: LoadUnit?
        if !durations.isEmpty {
            if rated.count == durations.count {
                value = durations.reduce(0) { $0 + $1.0 * ($1.1 ?? 0) }; unit = .sessionRPE
                notes.append("Completed workout minutes × explicitly reported RPE (0–10). Subjective training load, not measured physiological strain.")
            } else {
                value = durations.reduce(0) { $0 + $1.0 }; unit = .minutes
                notes.append("Duration-only activity fallback: \(durations.count - rated.count) workout(s) lack RPE. No intensity is invented; rate sessions to use session-RPE load.")
            }
        } else if let active, active.isFinite, active >= 0 {
            value = active; unit = .active; notes.append("Apple Health active-energy fallback. Energy is an estimate, not physiological strain; workout calories are not added.")
        } else if let steps, steps.isFinite, steps >= 0 {
            value = steps; unit = .steps; notes.append("Step-count activity fallback; it does not measure training intensity.")
        } else { value = nil; unit = nil; notes.append("Start logging activity or connect Apple Health. No records does not establish a rest day.") }
        let invalid = matching.count - reconciled.sessions.count - reconciled.excluded
        if invalid > 0 || durations.count != reconciled.sessions.count { notes.append("Invalid, unfinished or unsupported workout inputs were excluded.") }
        return DailyLoad(day: window.start, value: value.flatMap { $0.isFinite ? $0 : nil }, unit: unit,
                         partial: window.isPartial || invalid > 0 || durations.count != reconciled.sessions.count,
                         notes: notes, duplicateCount: reconciled.excluded)
    }
    static func strain(load: DailyLoad, history: [DailyLoad], configuration c: ScoringConfiguration, calendar: Calendar = .current) -> StrainEstimate {
        guard (try? c.validated()) != nil, let value = load.value, value.isFinite, value >= 0, let unit = load.unit else {
            return StrainEstimate(load: load, score: nil, target: nil, personalized: false, historyDays: 0)
        }
        let historyStart = calendar.date(byAdding: .day, value: -ScoringQualityRules.historyDays, to: load.day) ?? load.day
        let eligible = history.filter { $0.day >= historyStart && $0.day < load.day && !$0.partial && $0.unit == unit && ($0.value ?? -1) > 0 && $0.value?.isFinite == true }
        let unique = Dictionary(grouping: eligible, by: \.day).compactMap { _, days in days.count == 1 ? days.first?.value : nil }
        let personalized = c.personalizeLoad && unique.count >= c.minimumTargetDays
        let provisional: Double
        switch unit { case .sessionRPE: provisional = c.rpeTarget; case .minutes: provisional = c.minutesTarget; case .active: provisional = c.activeEnergyTarget; case .steps: provisional = c.stepsTarget }
        let target = (personalized ? ScoreMath.median(unique) ?? provisional : provisional) * c.targetScale
        return StrainEstimate(load: load, score: target.isFinite && target > 0 ? ScoreMath.bounded(100 * min(1, value / target)) : nil,
                              target: target, personalized: personalized, historyDays: unique.count)
    }
}

struct RecoverySample: Identifiable, Equatable, Sendable {
    let id: UUID
    let date: Date
    let value: Double
    let source: String
}
struct RecoveryComponent: Equatable, Identifiable {
    let id: String
    let score: Double?
    let weight: Double
    var detail: String
    var recent: Double? = nil
    var baseline: Double? = nil
    var sampleCount = 0
    var baselineDayCount = 0
    var source: String? = nil
    var baselineWindow: DateInterval? = nil
    var recentWindow: DateInterval? = nil
}
struct RecoveryEstimate: Equatable {
    let score: Double?
    let components: [RecoveryComponent]
    let provisional: Bool
    var eligible: [RecoveryComponent] { components.filter { $0.score.map { $0.isFinite && (0...100).contains($0) } == true && $0.weight.isFinite && $0.weight > 0 } }
    var eligibleWeight: Double { eligible.reduce(0) { $0 + $1.weight } }
}
enum RecoveryScoring {
    static func sleep(_ summary: SleepSummary?, window: SleepWindow?, c: ScoringConfiguration) -> RecoveryComponent {
        guard (try? c.validated()) != nil, let summary, let seconds = summary.asleepSeconds,
              seconds.isFinite, seconds >= 0, let window, seconds <= window.end.timeIntervalSince(window.start),
              !summary.invalidSamples, !summary.conflictingStates else {
            return RecoveryComponent(id: "Sleep duration", score: nil, weight: c.sleepWeight, detail: "Enable sleep insights or wait for valid, nonconflicting records. Missing sleep is not zero.")
        }
        return RecoveryComponent(id: "Sleep duration", score: ScoreMath.bounded(100 * (seconds / 60 / c.sleepTargetMinutes)),
            weight: c.sleepWeight, detail: "Recorded minutes / \(c.sleepTargetMinutes.formatted()) minute target. Duration only, not sleep quality. \(window.isPartial ? "Sleep window is still open." : "Closed noon-to-noon window.")",
            recent: seconds / 60, baseline: c.sleepTargetMinutes, source: summary.sources.joined(separator: ", "), recentWindow: DateInterval(start: window.start, end: window.end))
    }
    static func heart(_ samples: [RecoverySample], hrv: Bool, day: Date, now: Date, calendar: Calendar, c: ScoringConfiguration) -> RecoveryComponent {
        let title = hrv ? "HRV SDNN" : "Resting heart rate", weight = hrv ? c.hrvWeight : c.restingHRWeight
        func absent(_ reason: String, days: Int = 0) -> RecoveryComponent {
            RecoveryComponent(id: title, score: nil, weight: weight, detail: reason, baselineDayCount: days)
        }
        guard (try? c.validated()) != nil, let window = try? LocalDayWindow(day: day, now: now, calendar: calendar),
              let start = calendar.date(byAdding: .day, value: -c.baselineDays, to: window.start),
              let recentStart = calendar.date(byAdding: .day, value: -(c.recentDays - 1), to: window.start) else { return absent("Invalid date or configuration.") }
        let range = hrv ? ScoringQualityRules.hrvRange : ScoringQualityRules.restingHRRange
        let sorted = samples.filter { $0.date.timeIntervalSince1970.isFinite && $0.date >= start && $0.date < window.end && $0.value.isFinite && range.contains($0.value) }
            .sorted { $0.date == $1.date ? $0.id.uuidString < $1.id.uuidString : $0.date < $1.date }
        let groups = Dictionary(grouping: sorted, by: \.id)
        let consistent = sorted.filter { sample in groups[sample.id, default: []].allSatisfy { $0 == sample } }
        let events = Dictionary(grouping: consistent, by: { "\($0.source)|\($0.date.timeIntervalSince1970)" })
        let coherent = consistent.filter { sample in events["\(sample.source)|\(sample.date.timeIntervalSince1970)", default: []].allSatisfy { $0.value == sample.value } }
        var ids = Set<UUID>(), representations = Set<String>()
        let unique = coherent.filter { ids.insert($0.id).inserted && representations.insert("\($0.source)|\($0.date.timeIntervalSince1970)|\($0.value)").inserted }
        let sourceGroups = Dictionary(grouping: unique.filter { $0.date < recentStart }, by: \.source)
        let source = sourceGroups.keys.sorted().max { a, b in
            Set(sourceGroups[a, default: []].map { calendar.startOfDay(for: $0.date) }).count < Set(sourceGroups[b, default: []].map { calendar.startOfDay(for: $0.date) }).count
        }
        guard let source else { return absent("Building baseline: needs \(c.minimumBaselineDays) distinct prior days from one source, plus \(c.minimumRecentDays) recent days. Missing access and absent samples cannot be distinguished.") }
        func daily(_ values: [RecoverySample]) -> [Double] {
            Dictionary(grouping: values, by: { calendar.startOfDay(for: $0.date) }).values.compactMap { ScoreMath.median($0.map(\.value)) }
        }
        let baselineDays = daily(unique.filter { $0.source == source && $0.date < recentStart })
        guard let initial = ScoreMath.median(baselineDays) else { return absent("Building personal baseline.") }
        let mad = ScoreMath.median(baselineDays.map { abs($0 - initial) }) ?? 0
        let threshold = max(ScoringQualityRules.baselineMADMultiplier * ScoringQualityRules.madScale * mad, hrv ? initial * ScoringQualityRules.hrvBaselineRelativeFloor : ScoringQualityRules.restingHRBaselineFloor)
        let filteredBaseline = baselineDays.filter { abs($0 - initial) <= threshold }
        guard filteredBaseline.count >= c.minimumBaselineDays, let baseline = ScoreMath.median(filteredBaseline), baseline > 0 else {
            return absent("Building baseline: \(filteredBaseline.count)/\(c.minimumBaselineDays) valid prior days from \(source). Extreme daily values are excluded.", days: filteredBaseline.count)
        }
        let recentLimit = max(ScoringQualityRules.recentMADMultiplier * ScoringQualityRules.madScale * mad, hrv ? baseline : ScoringQualityRules.restingHRRecentFloor)
        let recentSamples = unique.filter { $0.source == source && $0.date >= recentStart && abs($0.value - baseline) <= recentLimit }
        let recentValues = daily(recentSamples)
        guard recentValues.count >= c.minimumRecentDays, recentSamples.count >= (hrv ? ScoringQualityRules.hrvRecentSamples : ScoringQualityRules.restingHRRecentSamples),
              let newest = recentSamples.map(\.date).max(), window.end.timeIntervalSince(newest) <= ScoringQualityRules.maximumRecentAgeSeconds,
              let recent = ScoreMath.median(recentValues) else { return absent("Need recent coverage from baseline source \(source); missing or stale readings do not become a normal score.", days: filteredBaseline.count) }
        let score = hrv ? 50 + c.hrvSlope * (recent / baseline - 1) : 100 - c.restingHRPenalty * max(0, recent - baseline)
        return RecoveryComponent(id: title, score: ScoreMath.bounded(score), weight: weight,
            detail: "\(source). Median of daily medians; \(filteredBaseline.count) baseline days, \(recentValues.count) recent days, \(recentSamples.count) recent samples. One source only; range/MAD filters exclude outliers. Mapping is a provisional heuristic.",
            recent: recent, baseline: baseline, sampleCount: recentSamples.count, baselineDayCount: filteredBaseline.count, source: source, baselineWindow: DateInterval(start: start, end: recentStart), recentWindow: DateInterval(start: recentStart, end: window.end))
    }
    static func training(history: [DailyLoad], day: Date, calendar: Calendar, c: ScoringConfiguration) -> RecoveryComponent {
        func absent(_ text: String) -> RecoveryComponent { RecoveryComponent(id: "Recent training load", score: nil, weight: c.loadWeight, detail: text) }
        guard let start = calendar.date(byAdding: .day, value: -ScoringQualityRules.historyDays, to: calendar.startOfDay(for: day)),
              let recentStart = calendar.date(byAdding: .day, value: -ScoringQualityRules.recentLoadDays, to: calendar.startOfDay(for: day)), (try? c.validated()) != nil else { return absent("Invalid dates or configuration.") }
        let candidates = history.filter { $0.day >= start && $0.day < calendar.startOfDay(for: day) && !$0.partial && $0.value.map({ $0.isFinite && $0 >= 0 }) == true }
        let byDay = Dictionary(grouping: candidates, by: \.day)
        let values = byDay.values.compactMap { entries -> DailyLoad? in
            guard let first = entries.first, entries.allSatisfy({ $0 == first }), first.unit != nil else { return nil }
            return first
        }
        guard Set(values.compactMap(\.unit)).count <= 1 else {
            return absent("Daily load modes changed. A 7/28-day comparison must use one consistent mode across the whole history, not omit known training days in a different unit.")
        }
        // One mode and one record per day. No RPE/minutes/calorie mixing or guessed rest days.
        guard let mode = Dictionary(grouping: values, by: \.unit).sorted(by: { $0.value.count == $1.value.count ? ($0.key?.rawValue ?? "") < ($1.key?.rawValue ?? "") : $0.value.count > $1.value.count }).first?.key else { return absent("Needs recorded load history; unlogged days are unknown.") }
        let days = Dictionary(grouping: values.filter { $0.unit == mode }, by: \.day).compactMap { _, entries in entries.count == 1 ? entries.first : nil }.sorted { $0.day < $1.day }
        let recent = days.filter { $0.day >= recentStart }.compactMap(\.value)
        let prior = days.compactMap(\.value)
        guard days.count >= c.minimumLoadDays, recent.count >= c.minimumRecentLoadDays else {
            return absent("Needs \(c.minimumLoadDays)/28 observed days and \(c.minimumRecentLoadDays)/7 recent days in one load mode; missing days are never rest days.")
        }
        let mean = prior.reduce(0) { $0 + $1 / Double(prior.count) }
        guard mean.isFinite, mean > 0 else { return absent("No positive finite usual-load baseline exists; a zero baseline is not invented or divided by.") }
        let recentMean = recent.reduce(0) { $0 + $1 / Double(recent.count) }
        guard recentMean.isFinite else { return absent("Recent load arithmetic is invalid; refresh or review the recorded inputs.") }
        return RecoveryComponent(id: "Recent training load", score: ScoreMath.bounded(100 - ScoringQualityRules.loadIncreasePenalty * max(0, recentMean / mean - 1)), weight: c.loadWeight,
            detail: "Prior 7-day observed-day mean vs prior 28-day observed-day mean (overlapping windows), \(mode.rawValue) only. Coverage \(recent.count)/7 and \(days.count)/28. Not an injury-risk or safe-training predictor.", recent: recentMean, baseline: mean, baselineDayCount: days.count, baselineWindow: DateInterval(start: start, end: calendar.startOfDay(for: day)), recentWindow: DateInterval(start: recentStart, end: calendar.startOfDay(for: day)))
    }
    static func combine(_ components: [RecoveryComponent], partial: Bool) -> RecoveryEstimate {
        var seen = Set<String>()
        let groups = Dictionary(grouping: components, by: \.id)
        let unique = components.filter { component in seen.insert(component.id).inserted && groups[component.id, default: []].allSatisfy { $0 == component } }
        let eligible = unique.filter { $0.score.map({ $0.isFinite && (0...100).contains($0) }) == true && $0.weight.isFinite && $0.weight > 0 }.sorted { $0.id < $1.id }
        let sum = eligible.reduce(0) { $0 + $1.weight }
        let score = sum > 0 && sum.isFinite ? ScoreMath.bounded(eligible.reduce(0) { $0 + ($1.score ?? 0) * ($1.weight / sum) }) : nil
        return RecoveryEstimate(score: score, components: unique, provisional: partial || eligible.count < 4)
    }
}

// MARK: - Advanced model v1 (opt-in calculation preview)

/// A separately versioned, deterministic model. It is deliberately not wired
/// into the displayed legacy scores: callers must opt in and provide only
/// authorized, source-consistent samples. SDNN remains SDNN; it is never
/// converted to RMSSD.
struct AdvancedScoringConfiguration: Codable, Equatable, Sendable {
    static let version = 1
    var enabled = false
    var baselineDays = 28
    var minimumBaselineDays = 14
    var recoveryWeights = AdvancedRecoveryWeights()
    func validated() throws -> Self {
        guard (21...60).contains(baselineDays), (7...baselineDays).contains(minimumBaselineDays),
              recoveryWeights.valid else { throw ScoringError.configuration }
        return self
    }
}
struct AdvancedRecoveryWeights: Codable, Equatable, Sendable {
    var sdnn = 35.0, restingHR = 25.0, sleepDuration = 25.0, recentLoad = 15.0
    var valid: Bool { [sdnn, restingHR, sleepDuration, recentLoad].allSatisfy { $0.isFinite && $0 >= 0 } && sdnn + restingHR + sleepDuration + recentLoad > 0 }
}
struct AdvancedVitalSample: Identifiable, Equatable, Sendable {
    enum Kind: String, Codable, Sendable { case sdnn, restingHeartRate, respiratoryRate, wristTemperature, oxygenSaturation }
    let id: UUID; let date: Date; let value: Double; let source: String; let kind: Kind
}
struct AdvancedRecoveryEstimate: Equatable, Sendable {
    let score: Double?
    let confidence: Double
    let contributions: [RecoveryComponent]
    let notes: [String]
}
enum AdvancedRecoveryScoring {
    /// Baseline-relative component with a robust median/MAD gate. Higher is
    /// favorable for SDNN; lower is favorable for RHR. Vital kinds not present
    /// in the existing consent model remain unavailable rather than inferred.
    static func vital(_ kind: AdvancedVitalSample.Kind, samples: [AdvancedVitalSample], day: Date, now: Date, calendar: Calendar, weight: Double, higherBetter: Bool, configuration c: AdvancedScoringConfiguration) -> RecoveryComponent {
        let title = kind == .sdnn ? "HRV SDNN (advanced)" : kind == .restingHeartRate ? "Resting heart rate (advanced)" : "\(kind.rawValue) (not authorized)"
        guard (try? c.validated()) != nil, let window = try? LocalDayWindow(day: day, now: now, calendar: calendar),
              let start = calendar.date(byAdding: .day, value: -c.baselineDays, to: window.start) else { return RecoveryComponent(id: title, score: nil, weight: weight, detail: "Invalid advanced configuration.") }
        let valid = samples.filter { $0.kind == kind && $0.date >= start && $0.date < window.end && $0.date <= now && $0.value.isFinite && !$0.source.isEmpty }
        let source = Dictionary(grouping: valid, by: \.source).max { a, b in a.value.count < b.value.count }?.key
        guard let source else { return RecoveryComponent(id: title, score: nil, weight: weight, detail: "No authorized \(kind.rawValue) samples. Missing data is not zero.") }
        let values = valid.filter { $0.source == source }
        let byDay = Dictionary(grouping: values, by: { calendar.startOfDay(for: $0.date) }).compactMapValues { ScoreMath.median($0.map(\.value)) }
        let prior = byDay.filter { $0.key < window.start }.map(\.value)
        guard prior.count >= c.minimumBaselineDays, let median = ScoreMath.median(prior), median > 0,
              let current = ScoreMath.median(byDay.filter { $0.key >= window.start }.map(\.value)) else { return RecoveryComponent(id: title, score: nil, weight: weight, detail: "Building a same-source baseline: \(prior.count)/\(c.minimumBaselineDays) prior days.", baselineDayCount: prior.count, source: source) }
        let mad = ScoreMath.median(prior.map { abs($0 - median) }) ?? 0
        let scale = max(1, 1.4826 * mad, abs(median) * 0.05)
        let z = (current - median) / scale
        let direction = higherBetter ? z : -z
        return RecoveryComponent(id: title, score: ScoreMath.bounded(50 + 15 * direction), weight: weight,
            detail: "Same-source daily median compared with a \(prior.count)-day robust median/MAD baseline. This is a wellness heuristic, not readiness certification.", recent: current, baseline: median, sampleCount: values.count, baselineDayCount: prior.count, source: source)
    }
    static func combine(_ components: [RecoveryComponent], configuration c: AdvancedScoringConfiguration) -> AdvancedRecoveryEstimate {
        let eligible = components.filter { $0.score != nil && $0.weight > 0 }
        let total = eligible.reduce(0) { $0 + $1.weight }
        let score = total > 0 ? ScoreMath.bounded(eligible.reduce(0) { $0 + ($1.score ?? 0) * $1.weight } / total) : nil
        return AdvancedRecoveryEstimate(score: score, confidence: min(1, total / (c.recoveryWeights.sdnn + c.recoveryWeights.restingHR + c.recoveryWeights.sleepDuration + c.recoveryWeights.recentLoad)), contributions: components, notes: ["Advanced model v1 is opt-in and does not replace legacy Recovery.", "SDNN is not RMSSD; unavailable vital signs are omitted and weights renormalize."])
    }
}

struct HeartRatePoint: Identifiable, Equatable, Sendable { let id: UUID; let date: Date; let bpm: Double; let source: String }
struct CardiovascularLoad: Equatable, Sendable { let trimp: Double?; let zoneMinutes: [Int: Double]; let coverage: Double; let notes: [String] }
enum AdvancedStrainScoring {
    /// Banister-style, HR-reserve weighted exposure. It only accepts an explicit
    /// max HR and source-consistent samples; unknown intervals lower coverage.
    static func cardiovascular(points: [HeartRatePoint], start: Date, end: Date, restingHR: Double, maximumHR: Double) -> CardiovascularLoad {
        guard start < end, restingHR.isFinite, maximumHR.isFinite, maximumHR > restingHR + 10 else { return CardiovascularLoad(trimp: nil, zoneMinutes: [:], coverage: 0, notes: ["Provide explicit resting and maximum HR assumptions."]) }
        let samples = points.filter { $0.date >= start && $0.date <= end && $0.bpm.isFinite && $0.bpm > 0 }.sorted { $0.date < $1.date }
        guard samples.count >= 2, let source = Dictionary(grouping: samples, by: \.source).max(by: { $0.value.count < $1.value.count })?.key else { return CardiovascularLoad(trimp: nil, zoneMinutes: [:], coverage: 0, notes: ["No coherent heart-rate series."]) }
        let valid = samples.filter { $0.source == source }
        var trimp = 0.0, zones: [Int: Double] = [:], seconds = 0.0
        for pair in zip(valid, valid.dropFirst()) {
            let dt = pair.1.date.timeIntervalSince(pair.0.date); guard dt > 0 && dt <= 120 else { continue }
            let reserve = min(1, max(0, (pair.0.bpm - restingHR) / (maximumHR - restingHR)))
            let minutes = dt / 60; trimp += minutes * reserve * exp(1.92 * reserve); seconds += dt
            zones[min(5, max(1, Int(reserve * 5) + 1)), default: 0] += minutes
        }
        let coverage = min(1, seconds / end.timeIntervalSince(start))
        return CardiovascularLoad(trimp: coverage >= 0.5 ? trimp : nil, zoneMinutes: zones, coverage: coverage, notes: ["HR-reserve nonlinear exposure from \(source); intervals over 120 seconds are not imputed."])
    }
}

// MARK: - Explainable insights v1

struct HealthInsight: Identifiable, Equatable, Sendable {
    enum Kind: String, Sendable { case recovery, load, sleep, suggestion, setup }
    let kind: Kind
    let title: String
    let summary: String
    let detail: String
    let inputIDs: [String]
    var id: String { kind.rawValue + title }
}
enum InsightEngine {
    /// Rules only report observed scored components and their documented
    /// coverage. They make no behavioral attribution or medical inference.
    static func daily(recovery: RecoveryEstimate, strain: StrainEstimate?, sleepObservation: String?, partial: Bool) -> [HealthInsight] {
        var result: [HealthInsight] = []
        if let score = recovery.score, let strongest = recovery.eligible.max(by: { ($0.weight * ($0.score ?? 0)) < ($1.weight * ($1.score ?? 0)) }) {
            result.append(HealthInsight(kind: .recovery, title: "Recovery estimate: \(Int(score.rounded()))", summary: "\(partial || recovery.provisional ? "Provisional · " : "")Eligible inputs include \(strongest.id.lowercased()).", detail: strongest.detail + " This score is an estimate based on available inputs, not a readiness measure.", inputIDs: recovery.eligible.map(\.id)))
        } else {
            result.append(HealthInsight(kind: .setup, title: "Recovery is building context", summary: "There are not enough eligible same-source inputs for an estimate.", detail: recovery.components.map { "\($0.id): \($0.detail)" }.joined(separator: " "), inputIDs: recovery.components.map(\.id)))
        }
        if let strain, let score = strain.score, let value = strain.load.value, let unit = strain.load.unit {
            result.append(HealthInsight(kind: .load, title: "Activity load: \(Int(score.rounded())) / 100", summary: "\(partial || strain.provisional ? "Provisional · " : "")\(Int(value.rounded())) \(unit.rawValue).", detail: strain.load.notes.joined(separator: " "), inputIDs: ["activity-load"]))
            if !partial, !strain.provisional, !recovery.provisional, let recoveryScore = recovery.score {
                let suggestion = score >= 80 && recoveryScore < 50 ? "Consider keeping the next session flexible while reviewing your recorded inputs." : score < 40 && recoveryScore >= 60 ? "Compare your planned session with recent training history." : "Review your recent training history when planning the next session."
                result.append(HealthInsight(kind: .suggestion, title: "Training context", summary: suggestion, detail: "This uses the displayed heuristic scores only. It does not establish a cause or a safe activity target.", inputIDs: ["activity-load"] + recovery.eligible.map(\.id)))
            }
        } else {
            result.append(HealthInsight(kind: .setup, title: "Activity load unavailable", summary: "Log a completed workout or wait for eligible activity data.", detail: strain?.load.notes.joined(separator: " ") ?? "No compatible activity unit is available.", inputIDs: ["activity-load"]))
        }
        if let sleepObservation { result.append(HealthInsight(kind: .sleep, title: "Sleep trend", summary: sleepObservation, detail: "This describes recorded sleep timing/duration only; it does not establish a cause of recovery changes.", inputIDs: ["sleep"])) }
        return Array(result.prefix(4))
    }
}

// MARK: - Widget snapshot contract v1

/// Read-only values prepared by the main app for a future WidgetKit extension.
/// This deliberately contains display-safe summaries rather than SwiftData
/// records or raw Health samples. A widget must never open the app container.
struct PersonalFitnessWidgetSnapshot: Codable, Equatable, Sendable {
    static let currentSchemaVersion = 1
    let schemaVersion: Int
    let generatedAt: Date
    let localDayStart: Date
    let timeZoneIdentifier: String
    let privacy: WidgetPrivacyMode
    let recovery: WidgetMetricSnapshot
    let strain: WidgetMetricSnapshot
    let nutrition: WidgetNutritionSnapshot
    let activeWorkout: WidgetActiveWorkoutSnapshot?

    init(generatedAt: Date, localDayStart: Date, timeZoneIdentifier: String,
         privacy: WidgetPrivacyMode, recovery: WidgetMetricSnapshot,
         strain: WidgetMetricSnapshot, nutrition: WidgetNutritionSnapshot,
         activeWorkout: WidgetActiveWorkoutSnapshot?) {
        schemaVersion = Self.currentSchemaVersion
        self.generatedAt = generatedAt
        self.localDayStart = localDayStart
        self.timeZoneIdentifier = timeZoneIdentifier
        self.privacy = privacy
        self.recovery = recovery
        self.strain = strain
        self.nutrition = nutrition
        self.activeWorkout = activeWorkout
    }

    /// Redacts numeric and workout-identifying data for a privacy-sensitive
    /// widget context while retaining honest availability and freshness labels.
    func redacted() -> Self {
        guard privacy == .hideValues else { return self }
        return Self(generatedAt: generatedAt, localDayStart: localDayStart,
                    timeZoneIdentifier: timeZoneIdentifier, privacy: privacy,
                    recovery: recovery.redacted(), strain: strain.redacted(),
                    nutrition: nutrition.redacted(), activeWorkout: activeWorkout?.redacted())
    }
}

enum WidgetPrivacyMode: String, Codable, Sendable { case showValues, hideValues }
enum WidgetDataState: String, Codable, Sendable { case current, partial, unavailable }
enum WidgetMetricKind: String, Codable, Sendable { case recovery, strain }

struct WidgetMetricSnapshot: Codable, Equatable, Sendable {
    let kind: WidgetMetricKind
    let score: Double?
    let state: WidgetDataState
    let sourceLabel: String
    init(kind: WidgetMetricKind, score: Double?, state: WidgetDataState, sourceLabel: String) {
        self.kind = kind
        self.score = score.flatMap { $0.isFinite && (0...100).contains($0) ? $0 : nil }
        self.state = score == nil ? .unavailable : state
        self.sourceLabel = sourceLabel
    }
    func redacted() -> Self { Self(kind: kind, score: nil, state: state, sourceLabel: "Open PersonalFitness to view") }
}

struct WidgetNutritionSnapshot: Codable, Equatable, Sendable {
    let consumedCalories: Double?
    let calorieGoal: Double?
    let state: WidgetDataState
    init(consumedCalories: Double?, calorieGoal: Double?, state: WidgetDataState) {
        self.consumedCalories = consumedCalories.flatMap { $0.isFinite && $0 >= 0 ? $0 : nil }
        self.calorieGoal = calorieGoal.flatMap { $0.isFinite && $0 > 0 ? $0 : nil }
        self.state = consumedCalories == nil ? .unavailable : state
    }
    func redacted() -> Self { Self(consumedCalories: nil, calorieGoal: nil, state: state) }
}

struct WidgetActiveWorkoutSnapshot: Codable, Equatable, Sendable {
    let name: String
    let completedSets: Int
    let plannedSets: Int?
    let startedAt: Date
    init?(name: String, completedSets: Int, plannedSets: Int?, startedAt: Date) {
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              completedSets >= 0, plannedSets.map({ $0 >= completedSets && $0 > 0 }) ?? true else { return nil }
        self.name = name; self.completedSets = completedSets; self.plannedSets = plannedSets; self.startedAt = startedAt
    }
    func redacted() -> Self? { Self(name: "Workout in progress", completedSets: 0, plannedSets: nil, startedAt: startedAt) }
}

enum WidgetSnapshotContract {
    static let maximumCurrentAge: TimeInterval = 2 * 60 * 60
    static let maximumClosedDayAge: TimeInterval = 24 * 60 * 60

    static func encode(_ snapshot: PersonalFitnessWidgetSnapshot) throws -> Data {
        try validate(snapshot, now: snapshot.generatedAt)
        return try JSONEncoder().encode(snapshot)
    }
    static func decode(_ data: Data, now: Date) throws -> PersonalFitnessWidgetSnapshot {
        let snapshot = try JSONDecoder().decode(PersonalFitnessWidgetSnapshot.self, from: data)
        try validate(snapshot, now: now)
        return snapshot
    }
    static func freshness(of snapshot: PersonalFitnessWidgetSnapshot, now: Date) -> WidgetDataState {
        let limit = snapshot.recovery.state == .partial || snapshot.strain.state == .partial || snapshot.nutrition.state == .partial
            ? maximumCurrentAge : maximumClosedDayAge
        guard now.timeIntervalSince(snapshot.generatedAt) <= limit else { return .unavailable }
        return snapshot.recovery.state == .partial || snapshot.strain.state == .partial || snapshot.nutrition.state == .partial
            ? .partial : .current
    }
    /// A future provider should use this as a conservative fallback refresh;
    /// the main app should reload timelines only after a new snapshot is saved.
    static func nextRefresh(after snapshot: PersonalFitnessWidgetSnapshot) -> Date {
        snapshot.generatedAt.addingTimeInterval(snapshot.recovery.state == .partial || snapshot.strain.state == .partial || snapshot.nutrition.state == .partial ? maximumCurrentAge : 6 * 60 * 60)
    }
    static func deepLink(_ destination: WidgetDestination) -> URL? {
        URL(string: "personalfitness://widget/\(destination.rawValue)")
    }
    static func destination(for url: URL) -> WidgetDestination? {
        guard url.scheme == "personalfitness", url.host == "widget" else { return nil }
        return WidgetDestination(rawValue: url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/")))
    }
    private static func validate(_ snapshot: PersonalFitnessWidgetSnapshot, now: Date) throws {
        guard snapshot.schemaVersion == PersonalFitnessWidgetSnapshot.currentSchemaVersion,
              snapshot.generatedAt.timeIntervalSince1970.isFinite,
              snapshot.localDayStart.timeIntervalSince1970.isFinite,
              !snapshot.timeZoneIdentifier.isEmpty,
              snapshot.generatedAt <= now.addingTimeInterval(5 * 60) else { throw WidgetSnapshotError.invalid }
    }
}

enum WidgetDestination: String, Codable, Sendable { case today, recovery, strain, nutrition, workout }
enum WidgetSnapshotError: Error { case invalid }

struct DashboardEnergyEstimate {
    let consumed: Double?
    let expenditure: Double?
    let balance: Double?
    let source: String
    let fallback: Bool
    let partial: Bool
    let record: EnergyExpenditureRecord
    /// Arc = logged intake / estimated expenditure for the same window. It is
    /// capped at one; the signed center value still reveals surplus beyond 100%.
    var progressFraction: Double? {
        guard let consumed, consumed.isFinite, consumed >= 0, let expenditure, expenditure > 0 else { return nil }
        return min(1, consumed / expenditure)
    }
    var progressLabel: String {
        guard let consumed, let expenditure, expenditure > 0 else { return "Log intake and set up energy to track intake / expenditure" }
        let percent = consumed / expenditure * 100
        guard percent.isFinite else { return "Intake / expenditure: beyond display range" }
        return "Intake / expenditure: " + percent.formatted(.number.precision(.fractionLength(0))) + "%"
    }
    static func make(assessment: EnergyAssessment, configuration c: ScoringConfiguration, calendar: Calendar,
                     now: Date = .now, historical: EnergyExpenditureRecord? = nil) -> Self {
        let record = EnergyExpenditureService.calculate(assessment: assessment, configuration: c, calendar: calendar, now: now, historical: historical)
        return Self(consumed: assessment.balance.consumed, expenditure: record.total,
                    balance: record.total.flatMap { total in assessment.balance.consumed.flatMap { ($0 - total).isFinite ? $0 - total : nil } },
                    source: (historical == record && record.predicted ? "Preserved closed-day prediction. " : "") + record.assumptions, fallback: record.predicted, partial: record.partial, record: record)
    }
}

extension DashboardRingState {
    static func wellness(_ kind: DashboardRingKind, strain: StrainEstimate?, recovery: RecoveryEstimate,
                         energy: DashboardEnergyEstimate, loading: Bool) -> Self {
        if loading { return Self(value: "…", unit: "", title: kind == .balance ? "Est. balance" : kind.rawValue, status: "Reading inputs") }
        switch kind {
        case .strain:
            guard let strain, let score = strain.score else { return Self.make(.strain, balance: nil, partial: false) }
            return Self(value: EnergyDisplay.kilocalories(score), unit: "/ 100", title: "Strain", status: strain.provisional ? "Provisional" : "Personalized load")
        case .recovery:
            guard let score = recovery.score else { return Self.make(.recovery, balance: nil, partial: false) }
            return Self(value: EnergyDisplay.kilocalories(score), unit: "/ 100", title: "Recovery", status: recovery.provisional ? "Provisional" : "4 signals · estimate")
        case .balance:
            guard energy.balance != nil else {
                return Self(value: energy.consumed == nil ? "Log food" : "Set up", unit: "", title: "Est. balance", status: energy.consumed == nil ? "Record intake" : "Connect or estimate")
            }
            let state = Self.make(.balance, balance: energy.balance, partial: energy.partial)
            return Self(value: state.value, unit: state.unit, title: state.title, status: energy.fallback ? "Configured estimate" : state.status)
        }
    }
}
