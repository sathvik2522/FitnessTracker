import Foundation
import Observation

struct SleepNight: Identifiable {
    var id: Date { day }
    let day: Date
    let window: SleepWindow
    let summary: SleepSummary
}

@MainActor @Observable
final class SleepModel {
    private let service: any SleepDataReading
    private var requestID = UUID()
    private(set) var requested: Bool
    private(set) var available: Bool
    private(set) var loading = false
    private(set) var connecting = false
    private(set) var error: String?
    private(set) var nights: [SleepNight] = []
    init(service: (any SleepDataReading)? = nil) {
        let service = service ?? HealthKitService()
        self.service = service
        requested = service.hasCompletedSleepRequest; available = service.isAvailable
    }
    func connect(day: Date, now: Date = .now, calendar: Calendar = .current) async {
        guard !connecting else { return }
        connecting = true
        defer { connecting = false }
        do {
            try await service.requestSleepAccess()
            requested = service.hasCompletedSleepRequest
            await load(day: day, now: now, calendar: calendar)
        } catch { self.error = "Sleep read request did not complete. Unlock your phone and try again." }
    }
    func load(day: Date, now: Date = .now, calendar: Calendar = .current) async {
        let token = UUID(); requestID = token
        nights = []; error = nil; loading = false
        available = service.isAvailable
        requested = service.hasCompletedSleepRequest
        guard available, requested else { return }
        let windows: [(Date, SleepWindow)] = (0..<7).compactMap { offset in
            guard let date = calendar.date(byAdding: .day, value: -offset, to: day),
                  let window = SleepWindow(day: date, now: now, calendar: calendar) else { return nil }
            return (date, window)
        }
        guard let first = windows.last, let last = windows.first else { return }
        loading = true
        // A cancelled current request must release the spinner. An older request
        // must never release a newer request's loading state or replace its data.
        defer { if token == requestID { loading = false } }
        let reading = await service.readSleep(start: first.1.start, end: last.1.end)
        guard token == requestID, !Task.isCancelled else { return }
        switch reading {
        case .failed(let issue): error = issue.rawValue
        case .unavailable:
            nights = windows.map { SleepNight(day: $0.0, window: $0.1, summary: SleepAnalysis.summarize([], in: $0.1)) }
        case .value(let records):
            nights = windows.map { day, window in
                SleepNight(day: day, window: window, summary: SleepAnalysis.summarize(records, in: window))
            }
        }
    }
    var observation: String? {
        guard let current = nights.first, !current.window.isPartial else { return nil }
        return SleepAnalysis.observation(current: current.summary, previous: nights.dropFirst().map(\.summary))
    }
}
