import Foundation
import Observation

@MainActor @Observable final class ScoringPreferences {
    static let historyKey = "personalFitness.energyHistory.v1"
    private(set) var history: [EnergyExpenditureRecord] = []
    static let key = "personalFitness.scoring.v1"
    private let defaults: UserDefaults?
    private var historyReadable = true
    private(set) var configuration: ScoringConfiguration
    private(set) var error: String?
    init(defaults: UserDefaults? = .standard) {
        self.defaults = defaults
        do { configuration = try Self.saved(defaults: defaults) ?? ScoringConfiguration() }
        catch { configuration = ScoringConfiguration(); self.error = "Saved scoring settings could not be read. Inspect them before using estimates; records are unchanged." }
        do { history = try Self.savedHistory(defaults: defaults) }
        catch { historyReadable = false; self.error = "Saved expenditure history could not be read. Export/preserve the app container before repairing it; history has not been reset." }
    }
    func save(_ configuration: ScoringConfiguration) throws {
        let valid = try configuration.validated()
        guard let defaults else { throw CocoaError(.fileWriteUnknown) }
        let data = try JSONEncoder().encode(valid)
        defaults.set(data, forKey: Self.key)
        self.configuration = valid
        if historyReadable { error = nil }
    }
    func estimate(_ assessment: EnergyAssessment, calendar: Calendar, now: Date = .now) -> DashboardEnergyEstimate {
        if error != nil { return DashboardEnergyEstimate.make(assessment: assessment, configuration: .init(), calendar: calendar, now: now) }
        let prior = history.first { $0.matches(assessment.window) }
        return DashboardEnergyEstimate.make(assessment: assessment, configuration: configuration, calendar: calendar, now: now, historical: prior)
    }
    /// Called after a successful screen refresh, never while SwiftUI renders.
    /// First computed closed-day prediction is immutable. Intake is not frozen:
    /// historical food edits still update the balance against that expenditure.
    func preserveHistoricalEstimate(_ assessment: EnergyAssessment, calendar: Calendar, now: Date = .now) {
        guard error == nil, !assessment.window.isPartial else { return }
        let value = estimate(assessment, calendar: calendar, now: now).record
        guard value.predicted, value.total != nil, !history.contains(where: { $0.key == value.key }) else { return }
        do {
            _ = try value.validated()
            guard let defaults else { throw CocoaError(.fileWriteUnknown) }
            let updated = history + [value]
            defaults.set(try JSONEncoder().encode(updated), forKey: Self.historyKey)
            history = updated
        } catch { self.error = "Historical expenditure could not be preserved. Review settings before relying on estimates; records are unchanged." }
    }
    static func savedHistory(defaults: UserDefaults?) throws -> [EnergyExpenditureRecord] {
        guard let data = defaults?.data(forKey: historyKey) else { return [] }
        let values = try JSONDecoder().decode([EnergyExpenditureRecord].self, from: data)
        guard Set(values.map(\.key)).count == values.count else { throw ScoringError.configuration }
        return try values.map { try $0.validated() }
    }
    static func saved(defaults: UserDefaults?) throws -> ScoringConfiguration? {
        guard let defaults else { throw CocoaError(.fileReadUnknown) }
        guard let data = defaults.data(forKey: key) else { return nil }
        return try JSONDecoder().decode(ScoringConfiguration.self, from: data).validated()
    }
}
