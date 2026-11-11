import Foundation
import Observation
import SwiftData

@MainActor @Observable
final class DashboardWeightModel {
    private let health: any HealthHistoryReading
    private var requestID = UUID()
    private(set) var weights: [WeightObservation] = []
    private(set) var loading = false
    private(set) var issue: String?
    init(health: (any HealthHistoryReading)? = nil) { self.health = health ?? HealthKitService() }
    func load(day: Date, context: ModelContext, now: Date = .now, calendar: Calendar = .current) async {
        let token = UUID(); requestID = token
        loading = true; issue = nil; weights = []
        defer { if requestID == token { loading = false } }
        do {
            let window = try LocalDayWindow(day: day, now: now, calendar: calendar)
            guard let start = calendar.date(byAdding: .day, value: -13, to: window.start) else { throw ReportError.dates }
            let end = window.end
            let manual = try context.fetch(FetchDescriptor<ManualWeight>(predicate: #Predicate { $0.date >= start && $0.date < end }))
                .map { try $0.observation.validated(now: now) }
            let reading: HealthReading<[WeightObservation]> = health.isAvailable && health.hasCompletedRequest
                ? await health.readWeights(start: start, end: end) : .unavailable
            guard requestID == token, !Task.isCancelled else { return }
            weights = manual + (reading.value ?? [])
            issue = reading.issue?.rawValue
        } catch {
            guard token == requestID else { return }
            issue = error.localizedDescription
        }
    }
}
