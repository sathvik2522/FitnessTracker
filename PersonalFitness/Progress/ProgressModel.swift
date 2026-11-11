import Foundation
import Observation
import SwiftData

struct ProgressReport {
    let range: ReportRange
    let calendar: Calendar
    let refreshed: Date
    let days: [ReportDay]
    let healthDays: [HealthDaySnapshot]
    let local: LocalProgressData
    let weights: [WeightObservation]
    let healthWeights: HealthReading<[WeightObservation]>
    var totals: ReportTotals { ReportTotals(days) }
    var healthWorkouts: [HealthWorkout] {
        HealthWorkout.uniqueRecords(healthDays.flatMap { $0.workouts.value ?? [] })
            .filter { $0.start >= range.start && $0.start < min(range.end, refreshed) }
    }
    var readableWorkoutDays: Int { healthDays.filter { $0.workouts.value != nil }.count }
    var trend: [WeightTrendPoint] { WeightTrend.points(weights, calendar: calendar).filter { $0.day >= range.start && $0.day < range.end } }
}

/// Builds reports from local snapshots and Health queries with one captured
/// calendar/cutoff. Cancellation and request IDs prevent stale range updates.
@MainActor @Observable
final class ProgressModel {
    var period: ReportPeriod = .week
    var anchor: Date
    var customStart: Date
    var customEnd: Date
    var reloadID = UUID()
    var loading = true
    private(set) var today: Date
    private(set) var calendar: Calendar
    private(set) var report: ProgressReport?
    private(set) var completedDays = 0
    private(set) var requestedDays = 0
    private(set) var error: String?
    private(set) var connectionMessage: String?
    private(set) var connecting = false
    private let health: any HealthHistoryReading
    private var requestID = UUID()

    init(now: Date = .now, calendar: Calendar = .current, health: (any HealthHistoryReading)? = nil) {
        self.calendar = calendar
        let day = calendar.startOfDay(for: now)
        today = day
        anchor = day; customEnd = day
        customStart = calendar.date(byAdding: .day, value: -6, to: day)!
        self.health = health ?? HealthKitService()
    }
    var canMoveForward: Bool {
        let unit: Calendar.Component = period == .day ? .day : period == .week ? .weekOfYear : .month
        return !calendar.isDate(anchor, equalTo: today, toGranularity: unit)
    }
    func movePeriod(by value: Int) {
        let unit: Calendar.Component = period == .day ? .day : period == .week ? .weekOfYear : .month
        if let date = calendar.date(byAdding: unit, value: value, to: anchor) { anchor = min(date, today) }
    }
    func selectRecentDays(_ count: Int) {
        guard (1...90).contains(count), let start = calendar.date(byAdding: .day, value: 1 - count, to: today) else { return }
        period = .custom; customStart = start; customEnd = today; reloadID = UUID()
    }
    func isRecentDays(_ count: Int) -> Bool {
        guard period == .custom, (1...90).contains(count), calendar.isDate(customEnd, inSameDayAs: today),
              let start = calendar.date(byAdding: .day, value: 1 - count, to: today) else { return false }
        return calendar.isDate(customStart, inSameDayAs: start)
    }
    func foreground(now: Date = .now, calendar next: Calendar = .current) {
        let previous = calendar
        func transferredDay(_ date: Date) -> Date {
            if previous.identifier != next.identifier { return next.startOfDay(for: date) }
            let parts = previous.dateComponents([.era, .year, .month, .day, .isLeapMonth], from: date)
            return next.date(from: parts) ?? next.startOfDay(for: date)
        }
        let followedToday = previous.isDate(anchor, inSameDayAs: today)
        calendar = next; today = next.startOfDay(for: now)
        anchor = followedToday ? today : min(transferredDay(anchor), today)
        customStart = min(transferredDay(customStart), today)
        customEnd = min(transferredDay(customEnd), today)
        reloadID = UUID()
    }
    func connect(context: ModelContext) async {
        guard !connecting else { return }
        guard health.isAvailable else { connectionMessage = "Apple Health is unavailable on this device."; return }
        connecting = true
        defer { connecting = false }
        do { try await health.requestReadAccess(); reloadID = UUID() }
        catch { connectionMessage = "Apple Health read request did not finish. Unlock your phone and try again." }
    }
    func load(context: ModelContext, now: Date = .now) async {
        let token = UUID(); requestID = token
        defer { if token == requestID { loading = false } }
        loading = true; error = nil; completedDays = 0
        do {
            let range = try ReportRange(period: period, anchor: anchor, customStart: customStart, customEnd: customEnd, now: now, calendar: calendar)
            if report?.range != range { report = nil }
            let scopeCalendar = calendar
            requestedDays = range.days.count
            let local = try ProgressStore(context: context).read(range, now: now, calendar: scopeCalendar)
            let canRead = health.isAvailable && health.hasCompletedRequest
            connectionMessage = !health.isAvailable ? "Apple Health is unavailable. Local reports and manual weight entries remain available."
                : !health.hasCompletedRequest ? "Connect Apple Health to read estimated energy, weight and workout history." : nil
            let weightStart = scopeCalendar.date(byAdding: .day, value: -6, to: range.start)!
            async let weights: HealthReading<[WeightObservation]> = canRead ? health.readWeights(start: weightStart, end: min(range.end, now)) : .unavailable
            var reports: [ReportDay] = []
            var snapshots: [HealthDaySnapshot] = []
            for day in range.days {
                try Task.checkCancellation()
                guard token == requestID else { return }
                let window = try LocalDayWindow(day: day, now: now, calendar: scopeCalendar)
                let snapshot: HealthDaySnapshot? = canRead ? await health.readDay(window) : nil
                try Task.checkCancellation()
                guard token == requestID else { return }
                if let snapshot { snapshots.append(snapshot) }
                reports.append(ReportDay(window: window, food: local.food, aggregates: snapshot?.energyAggregates ?? []))
                completedDays += 1
            }
            let healthWeights = await weights
            try Task.checkCancellation()
            guard token == requestID else { return }
            report = ProgressReport(range: range, calendar: scopeCalendar, refreshed: now, days: reports,
                healthDays: snapshots, local: local, weights: local.weights + (healthWeights.value ?? []), healthWeights: healthWeights)
            loading = false
        } catch is CancellationError {
            // A new UI task may already be preparing another range.
            return
        } catch {
            guard token == requestID else { return }
            self.error = error.localizedDescription; loading = false
        }
    }
}
