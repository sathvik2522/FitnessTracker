import Foundation
import Observation

/// Coordinates selected-day state and independently fallible food/Health reads.
/// Refresh tokens prevent an older query from replacing a newer day's results.
@Observable
@MainActor
final class DashboardModel {
    enum LoadState {
        case loading
        case loaded(DailyNutrition)
        case failed
    }

    enum HealthConnection {
        case unavailable, notRequested, requesting, requestCompleted, requestFailed
    }

    enum HealthLoadState {
        case idle, loading, loaded(HealthDaySnapshot), failed
    }

    private(set) var healthConnection: HealthConnection
    private(set) var healthState: HealthLoadState = .idle
    private let health: any HealthDataReading
    private var healthRefreshID = UUID()

    var healthSnapshot: HealthDaySnapshot? {
        if case .loaded(let snapshot) = healthState { return snapshot }
        return nil
    }

    var isReadingHealth: Bool { if case .loading = healthState { return true }; return false }

    var isRequestingHealth: Bool {
        if case .requesting = healthConnection { return true }
        return false
    }

    private(set) var selectedDate: Date
    private(set) var today: Date
    private(set) var state: LoadState = .loading
    private(set) var calendar: Calendar

    init(now: Date = .now, calendar: Calendar = .current, health: (any HealthDataReading)? = nil) {
        let service = health ?? HealthKitService()
        self.health = service
        healthConnection = !service.isAvailable ? .unavailable
            : service.hasCompletedRequest ? .requestCompleted : .notRequested
        self.calendar = calendar
        let day = calendar.startOfDay(for: now)
        today = day
        selectedDate = day
    }

    var isToday: Bool { selectedDate == today }
    var canMoveForward: Bool { selectedDate < today }

    func select(_ date: Date) {
        let day = min(calendar.startOfDay(for: date), today)
        guard day != selectedDate else { return }
        selectedDate = day
        state = .loading
        invalidateHealth()
    }

    func moveDay(by offset: Int) {
        guard let date = calendar.date(byAdding: .day, value: offset, to: selectedDate) else { return }
        select(date)
    }

    /// Follow midnight only when viewing today; preserve a historical selection.
    func updateToday(_ now: Date, calendar refreshedCalendar: Calendar? = nil) {
        let nextCalendar = refreshedCalendar ?? calendar
        let components = calendar.dateComponents([.era, .year, .month, .day, .isLeapMonth], from: selectedDate)
        let wasToday = isToday
        let zoneChanged = nextCalendar.timeZone != calendar.timeZone
            || nextCalendar.identifier != calendar.identifier
        let newToday = nextCalendar.startOfDay(for: now)
        guard newToday != today || zoneChanged else { return }
        let calendarBeforeRefresh = calendar
        calendar = nextCalendar
        today = newToday
        // Civil components can be transferred between time zones, but years
        // from one calendar must never be reinterpreted in another calendar.
        let historical = nextCalendar.identifier == calendarBeforeRefresh.identifier
            ? nextCalendar.date(from: components) ?? today
            : nextCalendar.startOfDay(for: selectedDate)
        select(wasToday ? today : min(historical, today))
        if zoneChanged { invalidateHealth() }
    }

    private func invalidateHealth() {
        healthRefreshID = UUID()
        healthState = .idle
    }

    func load(from store: FoodEntryStore, now: Date = .now) async {
        state = .loading
        // Give SwiftUI an opportunity to render the loading state.
        await Task.yield()
        guard !Task.isCancelled else { return }
        do {
            let window = try LocalDayWindow(day: selectedDate, now: now, calendar: calendar)
            state = .loaded(try store.snapshot(in: window))
        } catch {
            state = .failed
        }
        await refreshHealth()
    }

    /// Called only by an explicit user action. Query refresh never requests permission.
    func connectHealth() async {
        guard !isRequestingHealth else { return }
        guard health.isAvailable else {
            healthConnection = .unavailable
            invalidateHealth()
            return
        }
        healthConnection = .requesting
        invalidateHealth()
        do {
            try await health.requestReadAccess()
            healthConnection = .requestCompleted
            await refreshHealth()
        } catch {
            healthConnection = .requestFailed
        }
    }

    func refreshHealth(now: Date = .now) async {
        guard !isRequestingHealth else { return }
        guard health.isAvailable else {
            healthConnection = .unavailable
            invalidateHealth()
            return
        }
        guard health.hasCompletedRequest else {
            // Keep a failed request visible until the user retries explicitly.
            if case .requestFailed = healthConnection {} else { healthConnection = .notRequested }
            invalidateHealth()
            return
        }
        healthConnection = .requestCompleted
        let refreshID = UUID()
        healthRefreshID = refreshID
        defer {
            if healthRefreshID == refreshID, Task.isCancelled {
                healthState = .idle
            }
        }
        let day = selectedDate
        do {
            let window: LocalDayWindow
            if case .loaded(let nutrition) = state {
                // Keep food and energy on one cutoff. A manual/foreground load
                // creates a fresh shared scope for both reads.
                window = nutrition.window
            } else {
                window = try LocalDayWindow(day: day, now: now, calendar: calendar)
            }
            healthState = .loading
            let snapshot = await health.readDay(window)
            guard !Task.isCancelled, healthRefreshID == refreshID, selectedDate == day else { return }
            healthState = .loaded(snapshot)
        } catch {
            guard healthRefreshID == refreshID else { return }
            healthState = .failed
        }
    }

    func assessment(for nutrition: DailyNutrition) -> EnergyAssessment {
        let totals = nutrition.totals
        let reading: CalorieReading = totals.entryCount == 0 ? .missing
            : totals.calories.map(CalorieReading.value) ?? .failed
        return EnergyReconciliation.assess(
            window: nutrition.window,
            food: FoodEnergy(reading: reading, window: nutrition.window),
            aggregates: healthSnapshot?.energyAggregates ?? []
        )
    }
}
