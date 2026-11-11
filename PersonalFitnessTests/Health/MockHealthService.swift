import Foundation
@testable import PersonalFitness

@MainActor
final class MockHealthService: HealthDataReading {
    var isAvailable = true
    var hasCompletedRequest = false
    var requestFails = false
    var requestCount = 0
    var windows: [HealthDayWindow] = []
    var handler: ((HealthDayWindow) async -> HealthDaySnapshot)?
    var snapshot: (HealthDayWindow) -> HealthDaySnapshot = { window in
        HealthDaySnapshot(window: window, refreshedAt: window.end,
                          resting: .unavailable, active: .unavailable, steps: .unavailable,
                          workouts: .unavailable, weight: .unavailable)
    }

    func requestReadAccess() async throws {
        requestCount += 1
        if requestFails { throw HealthServiceError.unavailable }
        hasCompletedRequest = true
    }

    func readDay(_ window: HealthDayWindow) async -> HealthDaySnapshot {
        windows.append(window)
        if let handler { return await handler(window) }
        return snapshot(window)
    }
}
