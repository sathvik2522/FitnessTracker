import SwiftUI

extension Notification.Name {
    static let openFoodDiary = Notification.Name("PersonalFitness.openFoodDiary")
    static let openWorkoutLog = Notification.Name("PersonalFitness.openWorkoutLog")
    static let composeFood = Notification.Name("PersonalFitness.composeFood")
    static let composeWeight = Notification.Name("PersonalFitness.composeWeight")
}
struct FoodLoggingRequest: Identifiable {
    let id = UUID()
    let day: Date
    let meal: DiaryMeal
}
struct WeightLoggingRequest: Identifiable { let id = UUID(); let day: Date }
enum TrainingAction: Equatable { case strength, cardio, stairs }

struct AppNavigation: View {
    @State private var tab = 0
    @State private var diaryDay = Date.now
    @State private var foodRequest: FoodLoggingRequest?
    @State private var weightRequest: WeightLoggingRequest?
    @State private var trainingAction: TrainingAction?
    @State private var preferences = GoalPreferences(defaults: GoalPreferences.currentDefaults)
    @State private var scoringPreferences = ScoringPreferences(defaults: GoalPreferences.currentDefaults)
    private var scheme: ColorScheme? { preferences.appearance == "system" ? nil : preferences.appearance == "light" ? .light : .dark }
    var body: some View {
        TabView(selection: $tab) {
            DashboardView().tabItem { Label("Today", systemImage: "house.fill") }.tag(0)
            FoodDiaryView(day: $diaryDay).tabItem { Label("Food", systemImage: "fork.knife") }.tag(1)
            WorkoutsView(launchAction: $trainingAction).tabItem { Label("Training", systemImage: "dumbbell.fill") }.tag(2)
            ProgressReportView().tabItem { Label("Progress", systemImage: "chart.bar.fill") }.tag(3)
            MoreView().tabItem { Label("More", systemImage: "ellipsis") }.tag(4)
        }
        .onReceive(NotificationCenter.default.publisher(for: .openFoodDiary)) { event in
            if let day = event.object as? Date { diaryDay = day }
            tab = 1
        }
        .onReceive(NotificationCenter.default.publisher(for: .openWorkoutLog)) { event in
            trainingAction = event.object as? TrainingAction
            tab = 2
        }
        .onReceive(NotificationCenter.default.publisher(for: .composeFood)) { event in
            guard foodRequest == nil, let request = event.object as? FoodLoggingRequest else { return }
            diaryDay = request.day; tab = 1; foodRequest = request
        }
        .onReceive(NotificationCenter.default.publisher(for: .composeWeight)) { event in
            if let day = event.object as? Date { weightRequest = WeightLoggingRequest(day: day) }
        }
        .onOpenURL { url in
            guard let destination = WidgetSnapshotContract.destination(for: url) else { return }
            switch destination {
            case .today, .recovery, .strain: tab = 0
            case .nutrition: diaryDay = .now; tab = 1
            case .workout: tab = 2
            }
        }
        // Attach the logging session to the stable navigation root, not a tab's
        // conditional content. Changing/refreshing underlying tabs cannot destroy
        // the draft. Native sheets keep tab switching out of the editing session.
        .sheet(item: $foodRequest) { request in AddFoodFlow(day: request.day, meal: request.meal) }
        .sheet(item: $weightRequest) { request in ManualWeightEditor(day: request.day) }
        .environment(preferences)
        .environment(scoringPreferences)
        .preferredColorScheme(scheme)
        .tint(FitnessTheme.accent(preferences.accent))
        .toolbarBackground(FitnessTheme.background, for: .tabBar)
        .toolbarBackground(.visible, for: .tabBar)
        .listStyle(.insetGrouped)
    }
}
