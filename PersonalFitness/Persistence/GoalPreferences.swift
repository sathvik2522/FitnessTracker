import Foundation
import Observation

enum DashboardSection: String, CaseIterable, Codable, Identifiable {
    case overview, scores, nutrition, health, sleep, training, weight, context
    var id: String { rawValue }
    var title: String { rawValue == "scores" ? "Strain, recovery & energy" : rawValue.capitalized }
}
struct DashboardConfiguration: Codable, Equatable {
    var order = DashboardSection.allCases
    var hidden = Set<DashboardSection>()
    var compactMetrics = false
    mutating func validated() {
        hidden = hidden.intersection(Set(DashboardSection.allCases))
        let unique = order.reduce(into: [DashboardSection]()) { if !$0.contains($1) { $0.append($1) } }
        order = unique + DashboardSection.allCases.filter { !unique.contains($0) }
    }
}

@MainActor @Observable
final class GoalPreferences {
    static let key = "personalFitness.goals.v1"
    static let appearanceKey = "personalFitness.appearance"
    static let dashboardKey = "personalFitness.dashboard.v1"
    static let accentKey = "personalFitness.accent.v1"
    static let insightsKey = "personalFitness.insights.v1"
    static let restDurationKey = "personalFitness.restDurationSeconds.v1"
    static let widgetValuesKey = "personalFitness.widgetValuesVisible.v1"
    static let allowedRestDurations = [30, 45, 60, 90, 120, 180, 240, 300]
    static var currentDefaults: UserDefaults? {
        #if DEBUG
        let args = ProcessInfo.processInfo.arguments
        if let index = args.firstIndex(of: "--nutrition-ui-test-store"), args.indices.contains(index + 1),
           let id = UUID(uuidString: args[index + 1]) {
            return UserDefaults(suiteName: "PersonalFitness.UITest.Settings." + id.uuidString)
        }
        #endif
        return .standard
    }
    private let defaults: UserDefaults?
    private(set) var goals: NutritionGoals
    private(set) var loadError: String?
    private(set) var appearance: String
    private(set) var dashboard: DashboardConfiguration
    private(set) var accent: String
    private(set) var insightsVisible: Bool
    private(set) var restDurationSeconds: Int
    private(set) var widgetValuesVisible: Bool
    init(defaults: UserDefaults? = .standard) {
        self.defaults = defaults
        appearance = defaults?.string(forKey: Self.appearanceKey) ?? "dark"
        accent = defaults?.string(forKey: Self.accentKey) ?? "blue"
        insightsVisible = defaults?.object(forKey: Self.insightsKey) as? Bool ?? true
        let savedRest = defaults?.object(forKey: Self.restDurationKey) as? Int
        restDurationSeconds = savedRest.flatMap { Self.allowedRestDurations.contains($0) ? $0 : nil } ?? 90
        widgetValuesVisible = defaults?.object(forKey: Self.widgetValuesKey) as? Bool ?? false
        var loadedDashboard = (try? defaults?.data(forKey: Self.dashboardKey).map { try JSONDecoder().decode(DashboardConfiguration.self, from: $0) }) ?? DashboardConfiguration()
        loadedDashboard.validated()
        dashboard = loadedDashboard
        if let data = defaults?.data(forKey: Self.key) {
            do { goals = try JSONDecoder().decode(NutritionGoals.self, from: data).validated() }
            catch { goals = NutritionGoals(); loadError = "Saved goals could not be read. Configure them again; your diary is unchanged." }
        } else { goals = NutritionGoals() }
    }
    func save(_ goals: NutritionGoals) throws {
        let valid = try goals.validated()
        let data = try JSONEncoder().encode(valid)
        guard let defaults else { throw CocoaError(.fileWriteUnknown) }
        defaults.set(data, forKey: Self.key)
        self.goals = valid; loadError = nil
    }
    func setAppearance(_ value: String) throws {
        guard ["dark", "light", "system", "black"].contains(value), let defaults else { throw CocoaError(.fileWriteUnknown) }
        defaults.set(value, forKey: Self.appearanceKey); appearance = value
    }
    func setAccent(_ value: String) throws {
        guard ["blue", "mint", "violet", "orange"].contains(value), let defaults else { throw CocoaError(.fileWriteUnknown) }
        defaults.set(value, forKey: Self.accentKey); accent = value
    }
    func saveDashboard(_ value: DashboardConfiguration) throws {
        var value = value; value.validated()
        guard let defaults else { throw CocoaError(.fileWriteUnknown) }
        defaults.set(try JSONEncoder().encode(value), forKey: Self.dashboardKey); dashboard = value
    }
    func setInsightsVisible(_ value: Bool) throws {
        guard let defaults else { throw CocoaError(.fileWriteUnknown) }
        defaults.set(value, forKey: Self.insightsKey); insightsVisible = value
    }
    func setRestDuration(_ seconds: Int) throws {
        guard Self.allowedRestDurations.contains(seconds), let defaults else { throw CocoaError(.fileWriteUnknown) }
        defaults.set(seconds, forKey: Self.restDurationKey)
        restDurationSeconds = seconds
    }
    func setWidgetValuesVisible(_ value: Bool) throws {
        guard let defaults else { throw CocoaError(.fileWriteUnknown) }
        defaults.set(value, forKey: Self.widgetValuesKey)
        widgetValuesVisible = value
    }
    static func saved(defaults: UserDefaults? = .standard) throws -> NutritionGoals? {
        guard let defaults else { throw CocoaError(.fileReadUnknown) }
        guard let data = defaults.data(forKey: key) else { return nil }
        return try JSONDecoder().decode(NutritionGoals.self, from: data).validated()
    }
}
