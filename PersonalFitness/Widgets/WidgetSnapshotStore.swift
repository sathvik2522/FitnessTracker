import Foundation
import SwiftData
import WidgetKit

enum WidgetSnapshotStore {
    static let appGroup = "group.com.gbssathvik.PersonalFitness"
    static let key = "widgetSnapshot.v1"

    @MainActor static func save(nutrition: DailyNutrition, recovery: RecoveryEstimate,
                                strain: StrainEstimate?, preferences: GoalPreferences,
                                context: ModelContext, now: Date = .now) {
        let state: WidgetDataState = nutrition.window.isPartial ? .partial : .current
        let recoveryMetric = WidgetMetricSnapshot(kind: .recovery, score: recovery.score,
            state: recovery.provisional ? .partial : state,
            sourceLabel: recovery.score == nil ? "Insufficient eligible inputs" : "PersonalFitness recovery estimate")
        let strainMetric = WidgetMetricSnapshot(kind: .strain, score: strain?.score,
            state: strain?.provisional == true ? .partial : state,
            sourceLabel: strain?.score == nil ? "Activity load unavailable" : "PersonalFitness activity-load estimate")
        let active = try? context.fetch(FetchDescriptor<StrengthSession>(predicate: #Predicate { $0.statusRaw == "active" })).first
        let workout = active.flatMap { record -> WidgetActiveWorkoutSnapshot? in
            guard let draft = try? record.draft() else { return nil }
            let sets = draft.exercises.flatMap(\.sets)
            return WidgetActiveWorkoutSnapshot(name: draft.name, completedSets: sets.filter(\.completed).count,
                                               plannedSets: sets.count > 0 ? sets.count : nil, startedAt: draft.start)
        }
        let snapshot = PersonalFitnessWidgetSnapshot(generatedAt: now, localDayStart: nutrition.window.start,
            timeZoneIdentifier: nutrition.window.timeZoneIdentifier,
            privacy: preferences.widgetValuesVisible ? .showValues : .hideValues,
            recovery: recoveryMetric, strain: strainMetric,
            nutrition: WidgetNutritionSnapshot(consumedCalories: nutrition.totals.entryCount == 0 ? nil : nutrition.totals.calories,
                                                calorieGoal: preferences.goals.calories, state: state),
            activeWorkout: workout)
        guard let defaults = UserDefaults(suiteName: appGroup), let data = try? WidgetSnapshotContract.encode(snapshot) else { return }
        defaults.set(data, forKey: key)
        WidgetCenter.shared.reloadAllTimelines()
    }
}
