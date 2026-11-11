import XCTest
@testable import PersonalFitness

final class GoalPreferencesTests: XCTestCase {
    @MainActor func testExplicitGoalsAndAppearanceSurviveRecreationInvalidSaveKeepsPrevious() throws {
        let suite = "GoalsTest." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let preferences = GoalPreferences(defaults: defaults)
        XCTAssertEqual(preferences.goals, NutritionGoals())
        let goal = NutritionGoals(calories: 2100, protein: 130, carbohydrates: 240, fat: 70, steps: 8000)
        try preferences.save(goal); try preferences.setAppearance("light")
        XCTAssertThrowsError(try preferences.save(NutritionGoals(calories: 0)))
        XCTAssertEqual(GoalPreferences(defaults: defaults).goals, goal)
        XCTAssertEqual(GoalPreferences(defaults: defaults).appearance, "light")
        try preferences.save(NutritionGoals())
        XCTAssertEqual(GoalPreferences(defaults: defaults).goals, NutritionGoals())
    }
    @MainActor func testCorruptAndUnavailablePreferencesNeverBecomeInferredGoals() throws {
        let suite = "GoalsTest." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(Data("invalid".utf8), forKey: GoalPreferences.key)
        let preferences = GoalPreferences(defaults: defaults)
        XCTAssertEqual(preferences.goals, NutritionGoals()); XCTAssertNotNil(preferences.loadError)
        XCTAssertThrowsError(try GoalPreferences.saved(defaults: defaults))
        let missing = GoalPreferences(defaults: nil)
        XCTAssertThrowsError(try missing.save(NutritionGoals(calories: 2000)))
    }
    @MainActor func testDashboardAppearanceAndAccentPersistWithoutChangingGoals() throws {
        let suite = "DashboardTest." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let preferences = GoalPreferences(defaults: defaults)
        var dashboard = DashboardConfiguration()
        dashboard.order = [.training, .overview]
        dashboard.hidden = [.weight, .sleep]
        dashboard.compactMetrics = true
        try preferences.setAppearance("black")
        try preferences.setAccent("mint")
        try preferences.saveDashboard(dashboard)
        try preferences.setInsightsVisible(false)
        let restored = GoalPreferences(defaults: defaults)
        XCTAssertEqual(restored.appearance, "black")
        XCTAssertEqual(restored.accent, "mint")
        XCTAssertEqual(restored.dashboard.order.prefix(2), [.training, .overview])
        XCTAssertTrue(restored.dashboard.hidden.contains(.weight))
        XCTAssertTrue(restored.dashboard.compactMetrics)
        XCTAssertFalse(restored.insightsVisible)
        XCTAssertEqual(restored.goals, NutritionGoals())
    }
    @MainActor func testRestDurationIsVersionedValidatedAndSurvivesRecreation() throws {
        let suite = "RestTest." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let preferences = GoalPreferences(defaults: defaults)
        XCTAssertEqual(preferences.restDurationSeconds, 90)
        try preferences.setRestDuration(180)
        XCTAssertThrowsError(try preferences.setRestDuration(0))
        XCTAssertEqual(GoalPreferences(defaults: defaults).restDurationSeconds, 180)
        defaults.set(999, forKey: GoalPreferences.restDurationKey)
        XCTAssertEqual(GoalPreferences(defaults: defaults).restDurationSeconds, 90)
        XCTAssertEqual(preferences.restDurationSeconds, 180)
        XCTAssertThrowsError(try GoalPreferences(defaults: nil).setRestDuration(60))
    }
    @MainActor func testWidgetPrivacyDefaultsHiddenAndPersistsExplicitChoice() throws {
        let suite = "WidgetPrivacyTest." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let preferences = GoalPreferences(defaults: defaults)
        XCTAssertFalse(preferences.widgetValuesVisible)
        try preferences.setWidgetValuesVisible(true)
        XCTAssertTrue(GoalPreferences(defaults: defaults).widgetValuesVisible)
        XCTAssertThrowsError(try GoalPreferences(defaults: nil).setWidgetValuesVisible(true))
    }
}
