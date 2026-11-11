import Foundation
import Observation
import SwiftData

/// Health retrieval and persisted-log adaptation stay out of SwiftUI and the
/// pure engines. Results stay in memory; only explicit configuration is saved.
@MainActor @Observable final class ScoringDashboardModel {
    private let health: any ScoringHealthReading
    private var requestID = UUID()
    private var cachedAt: Date?
    private var cachedDay: Date?
    private var cachedZone: String?
    private(set) var localSessions: [LoadSession] = []
    private(set) var history: [HealthLoadDay] = []
    private(set) var windows: [LocalDayWindow] = []
    private(set) var readWindow: DateInterval?
    private(set) var readings = RecoveryReadings(hrv: .unavailable, restingHR: .unavailable)
    private(set) var loading = false
    private(set) var requesting = false
    private(set) var error: String?
    var historyIssue: String? {
        let failed = history.filter { $0.active.issue != nil || $0.workouts.issue != nil }
        guard !failed.isEmpty else { return nil }
        return "Historical Health queries failed for \(failed.count) day(s). Coverage may be incomplete. Unlock the phone, review access and refresh to retry."
    }
    var recoveryRequested: Bool { health.hasCompletedRecoveryRequest }
    var healthAvailable: Bool { health.isAvailable }
    init(health: (any ScoringHealthReading)? = nil) { self.health = health ?? HealthKitService() }

    func connect(day: Date, context: ModelContext, now: Date = .now, calendar: Calendar = .current) async {
        guard !requesting else { return }
        requesting = true
        defer { requesting = false }
        do {
            try await health.requestRecoveryAccess()
            await load(day: day, context: context, now: now, calendar: calendar, force: true)
        } catch { self.error = "Recovery read request did not complete. Unlock the phone and try again. Existing local logs are unchanged." }
    }
    func load(day: Date, context: ModelContext, now: Date = .now, calendar: Calendar = .current, force: Bool = false) async {
        let token = UUID(); requestID = token
        loading = true; error = nil
        defer { if token == requestID { loading = false } }
        do {
            let current = try LocalDayWindow(day: day, now: now, calendar: calendar)
            guard let start = calendar.date(byAdding: .day, value: -ScoringQualityRules.historyDays, to: current.start) else { throw LocalDayWindow.WindowError.invalidDay }
            let end = current.end
            let strength = try context.fetch(FetchDescriptor<StrengthSession>(predicate: #Predicate { $0.start >= start && $0.start < end }))
            let cardio = try context.fetch(FetchDescriptor<CardioSession>(predicate: #Predicate { $0.start >= start && $0.start < end }))
            var adapted: [LoadSession] = [], unreadable = 0
            for record in strength {
                do {
                    let draft = try record.draft().validated(now: now)
                    if draft.status == .completed, let end = draft.end {
                        adapted.append(LoadSession(id: draft.id, start: draft.start, end: end, activity: .strength, origin: .manual, rpe: draft.sessionRPE))
                    }
                } catch { unreadable += 1 }
            }
            for record in cardio {
                do {
                    let draft = try record.draft().validated(now: now)
                    adapted.append(LoadSession(id: draft.id, start: draft.start, end: draft.end, activity: draft.activity,
                        origin: .manual, rpe: draft.sessionRPE, durationMinutes: draft.durationSeconds / 60))
                } catch { unreadable += 1 }
            }
            localSessions = adapted
            if unreadable > 0 { error = "Some saved session details could not be read; load may be understated. No records were changed." }
            if !force, cachedDay == current.start, cachedZone == calendar.timeZone.identifier,
               let cachedAt, now.timeIntervalSince(cachedAt) >= 0, now.timeIntervalSince(cachedAt) < ScoringQualityRules.cacheSeconds { return }
            readWindow = nil
            history = []; readings = RecoveryReadings(hrv: .unavailable, restingHR: .unavailable)
            let windows = try (1...ScoringQualityRules.historyDays).map { offset -> LocalDayWindow in
                guard let date = calendar.date(byAdding: .day, value: -offset, to: current.start) else { throw LocalDayWindow.WindowError.invalidDay }
                return try LocalDayWindow(day: date, now: now, calendar: calendar)
            }
            self.windows = windows
            async let loads = authorizedHistory(windows)
            async let signals = authorizedSignals(start: start, end: end)
            let (nextHistory, nextReadings) = await (loads, signals)
            guard token == requestID, !Task.isCancelled else { return }
            history = nextHistory; readings = nextReadings
            readWindow = DateInterval(start: start, end: end)
            cachedDay = current.start; cachedZone = calendar.timeZone.identifier; cachedAt = now
        } catch {
            guard token == requestID else { return }
            readWindow = nil
            history = []; localSessions = []; readings = RecoveryReadings(hrv: .unavailable, restingHR: .unavailable)
            self.error = "Scoring inputs could not be loaded. Refresh to retry; your store has not been reset."
        }
    }
    func estimates(day: Date, snapshot: HealthDaySnapshot?, sleep: SleepNight?, configuration c: ScoringConfiguration,
                   now: Date = .now, calendar: Calendar = .current) -> (StrainEstimate?, RecoveryEstimate) {
        let loads = windows.map { window in
            let record = history.first { $0.window == window }
            return ActivityLoad.day(window: window, sessions: localSessions + Self.sessions(record?.workouts.value ?? []), active: record?.active.value, steps: nil, now: now)
        }
        let aligned = snapshot.flatMap { calendar.isDate($0.window.start, inSameDayAs: day) && $0.window.timeZoneIdentifier == calendar.timeZone.identifier ? $0 : nil }
        let rawCurrent = (try? LocalDayWindow(day: day, now: now, calendar: calendar)).map { window in
            ActivityLoad.day(window: aligned?.window ?? window,
                sessions: localSessions + Self.sessions(aligned?.workouts.value ?? []),
                active: aligned?.active.value, steps: aligned?.steps.value, now: now)
        }
        let current = rawCurrent.map { value in
            DailyLoad(day: value.day, value: value.value, unit: value.unit, partial: value.partial || error != nil,
                notes: value.notes + (error.map { [$0] } ?? []), duplicateCount: value.duplicateCount)
        }
        let strain = current.map { ActivityLoad.strain(load: $0, history: loads, configuration: c, calendar: calendar) }
        let night = sleep.flatMap { calendar.isDate($0.day, inSameDayAs: day) ? $0 : nil }
        var training = RecoveryScoring.training(history: loads, day: day, calendar: calendar, c: c)
        if training.score == nil {
            // Same load engine, one mode across every comparison day. Do not
            // compare rest-day kcal while silently omitting RPE workout days.
            let activeHistory = windows.map { window in
                ActivityLoad.day(window: window, sessions: [], active: history.first { $0.window == window }?.active.value,
                                 steps: nil, now: now)
            }
            let alternative = RecoveryScoring.training(history: activeHistory, day: day, calendar: calendar, c: c)
            if alternative.score != nil {
                training = alternative
                training.source = "Apple Health active-energy aggregates"
                training.detail = "Consistent all-days active-energy fallback from the same activity-load engine. The current Strain ring may use rated-workout load; the two modes are never added or compared numerically. " + training.detail
            }
        }
        let signalNow = cachedDay == calendar.startOfDay(for: day) && cachedZone == calendar.timeZone.identifier
            ? min(now, readWindow?.end ?? now) : now
        let signalPartial = (try? LocalDayWindow(day: day, now: signalNow, calendar: calendar))?.isPartial == true
        let components = [RecoveryScoring.sleep(night?.summary, window: night?.window, c: c),
            RecoveryScoring.heart(readings.hrv.value ?? [], hrv: true, day: day, now: signalNow, calendar: calendar, c: c),
            RecoveryScoring.heart(readings.restingHR.value ?? [], hrv: false, day: day, now: signalNow, calendar: calendar, c: c),
            training]
        return (strain, RecoveryScoring.combine(components, partial: current?.partial != false || sleep?.window.isPartial == true || signalPartial || error != nil))
    }
    private func authorizedHistory(_ windows: [LocalDayWindow]) async -> [HealthLoadDay] {
        guard health.isAvailable, health.hasCompletedRequest else { return [] }
        return await health.readLoadHistory(windows: windows)
    }
    private func authorizedSignals(start: Date, end: Date) async -> RecoveryReadings {
        guard health.isAvailable, health.hasCompletedRecoveryRequest else { return RecoveryReadings(hrv: .unavailable, restingHR: .unavailable) }
        return await health.readRecovery(start: start, end: end)
    }
    private static func sessions(_ records: [HealthWorkout]) -> [LoadSession] {
        records.map { LoadSession(id: $0.id, start: $0.start, end: $0.end, activity: $0.activity, origin: .health,
                                 durationMinutes: $0.durationSeconds.map { $0 / 60 }) }
    }
}
