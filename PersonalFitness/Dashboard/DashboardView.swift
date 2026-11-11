import SwiftUI
import SwiftData

struct DashboardView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.dynamicTypeSize) private var dynamicType
    @State private var model = DashboardModel()
    @State private var sleep = SleepModel()
    @State private var weight = DashboardWeightModel()
    @State private var scoring = ScoringDashboardModel()
    @Environment(ScoringPreferences.self) private var scoringPreferences
    @State private var expandedHealth = false
    @State private var refreshID = UUID()
    @Environment(GoalPreferences.self) private var preferences

    private var columns: [GridItem] {
        dynamicType >= .xLarge
            ? [GridItem(.flexible())]
            : [GridItem(.adaptive(minimum: 155), spacing: FitnessStyle.spacing)]
    }

    var body: some View {
        NavigationStack {
            TimelineView(.periodic(from: .now, by: 60)) { timeline in
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        dateNavigation
                        switch model.state {
                        case .loading:
                            LoadingState()
                        case .failed:
                            ErrorMessage(title: "Summary unavailable",
                                         message: "Your saved food entries could not be loaded. Try again; your data has not been reset.") {
                                Task { await refresh() }
                            }
                        case .loaded(let nutrition):
                            summary(nutrition)
                        }
                    }
                    .padding(FitnessStyle.spacing)
                    .padding(.bottom, 24)
                }
                .accessibilityIdentifier("dashboard.scroll")
                .background(FitnessTheme.background)
                .onChange(of: model.calendar.startOfDay(for: timeline.date)) { _, day in
                    model.updateToday(day)
                }
            }
            .navigationTitle("Today")
            .navigationBarTitleDisplayMode(.inline)
            .fitnessScreen()
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Label("PersonalFitness", systemImage: "leaf.fill").labelStyle(.titleAndIcon)
                        .font(.headline).lineLimit(1).minimumScaleFactor(0.75)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button("Log food", systemImage: "fork.knife") {
                            NotificationCenter.default.post(name: .composeFood, object: FoodLoggingRequest(day: model.selectedDate, meal: .unassigned))
                        }.accessibilityIdentifier("quick.food")
                        Button("Start workout", systemImage: "dumbbell") { NotificationCenter.default.post(name: .openWorkoutLog, object: TrainingAction.strength) }.accessibilityIdentifier("quick.strength")
                        Button("Log cardio", systemImage: "figure.run") { NotificationCenter.default.post(name: .openWorkoutLog, object: TrainingAction.cardio) }.accessibilityIdentifier("quick.cardio")
                        Button("Log stair climber", systemImage: "figure.stair.stepper") { NotificationCenter.default.post(name: .openWorkoutLog, object: TrainingAction.stairs) }.accessibilityIdentifier("quick.stairs")
                        Button("Record weight", systemImage: "scalemass") { NotificationCenter.default.post(name: .composeWeight, object: model.selectedDate) }.accessibilityIdentifier("quick.weight")
                    } label: { Image(systemName: "plus.circle.fill").font(.title2).frame(minWidth: 44, minHeight: 44) }
                    .accessibilityLabel("Quick actions")
                }
                ToolbarItem(placement: .topBarLeading) {
                    NavigationLink { ScrollView { SleepOverview(day: model.selectedDate).padding() }.navigationTitle("Sleep & context") }
                    label: { Label("Sleep", systemImage: "moon.zzz") }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Task { await refresh(forceScores: true) }
                    } label: { Label("Refresh", systemImage: "arrow.clockwise") }
                    .disabled(model.isRequestingHealth)
                }
            }
            .task(id: model.selectedDate) {
                await refresh()
            }
            .refreshable { await refresh(forceScores: true) }
            .onChange(of: scoringPreferences.configuration) { _, _ in
                if !model.isReadingHealth, case .loaded(let nutrition) = model.state { scoringPreferences.preserveHistoricalEstimate(model.assessment(for: nutrition), calendar: model.calendar) }
            }
            .onReceive(NotificationCenter.default.publisher(for: .nutritionDidChange)) { _ in
                Task { await refresh() }
            }
            .onReceive(NotificationCenter.default.publisher(for: .workoutsDidChange)) { _ in
                Task { await refresh() }
            }
            .onReceive(NotificationCenter.default.publisher(for: .manualWeightDidChange)) { _ in
                Task { await weight.load(day: model.selectedDate, context: context, calendar: model.calendar) }
            }
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.significantTimeChangeNotification)) { _ in
                model.updateToday(.now, calendar: .current)
                Task { await refresh() }
            }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active {
                    model.updateToday(.now, calendar: .current)
                    Task { await refresh() }
                }
            }
        }
    }

    private var dateNavigation: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeading(title: model.isToday ? "Today" : "Daily summary")
            if dynamicType.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 8) {
                    datePicker
                    HStack {
                        previousDayButton
                        Spacer()
                        nextDayButton
                    }
                }
            } else {
                HStack {
                    previousDayButton
                    datePicker.frame(maxWidth: .infinity)
                    nextDayButton
                }
            }
            if !model.isToday {
                Button("Return to today") { model.select(model.today) }
                    .buttonStyle(.bordered)
                    .frame(minHeight: 44)
            }
        }
    }

    private var datePicker: some View {
        DatePicker("Viewing date", selection: Binding(
            get: { model.selectedDate }, set: { model.select($0) }),
                   in: ...model.today, displayedComponents: .date)
            .labelsHidden()
            .accessibilityLabel("Viewing date")
    }

    private var previousDayButton: some View {
        Button { model.moveDay(by: -1) } label: {
            Image(systemName: "chevron.left").frame(width: 44, height: 44)
        }
        .accessibilityLabel("Previous day")
    }

    private var nextDayButton: some View {
        Button { model.moveDay(by: 1) } label: {
            Image(systemName: "chevron.right").frame(width: 44, height: 44)
        }
        .disabled(!model.canMoveForward)
        .accessibilityLabel("Next day")
    }

    private func refresh(forceScores: Bool = false) async {
        let token = UUID(); refreshID = token
        await model.load(from: FoodEntryStore(context: context))
        guard !Task.isCancelled, token == refreshID else { return }
        let selected = model.selectedDate
        await sleep.load(day: selected, calendar: model.calendar)
        guard !Task.isCancelled, token == refreshID, selected == model.selectedDate else { return }
        await weight.load(day: selected, context: context, calendar: model.calendar)
        guard !Task.isCancelled, token == refreshID, selected == model.selectedDate else { return }
        await scoring.load(day: selected, context: context, calendar: model.calendar, force: forceScores)
        if token == refreshID, selected == model.selectedDate, case .loaded(let nutrition) = model.state {
            scoringPreferences.preserveHistoricalEstimate(model.assessment(for: nutrition), calendar: model.calendar)
            if model.isToday {
                let estimates = scoring.estimates(day: selected, snapshot: model.healthSnapshot, sleep: sleep.nights.first,
                                                  configuration: scoringPreferences.configuration,
                                                  calendar: model.calendar)
                WidgetSnapshotStore.save(nutrition: nutrition, recovery: estimates.1, strain: estimates.0,
                                         preferences: preferences, context: context)
            }
        }
    }

    @ViewBuilder
    private func summary(_ daily: DailyNutrition) -> some View {
        let assessment = model.assessment(for: daily)
        let snapshot = model.healthSnapshot
        ForEach(preferences.dashboard.order) { section in
            if !preferences.dashboard.hidden.contains(section) { dashboardSection(section, daily: daily, assessment: assessment, snapshot: snapshot) }
        }
    }
    @ViewBuilder private func dashboardSection(_ section: DashboardSection, daily: DailyNutrition, assessment: EnergyAssessment, snapshot: HealthDaySnapshot?) -> some View {
        switch section {
        case .overview:
            VStack(alignment: .leading, spacing: 12) {
                Label(daily.window.isPartial ? "Your day so far" : "Daily overview", systemImage: "sparkles").font(.headline)
                Text(daily.totals.entryCount == 0 ? "No food logged. Intake is unknown." : "\(daily.totals.entryCount) \(daily.totals.entryCount == 1 ? "portion" : "portions") logged \(model.isToday ? "today" : "on this date").")
                    .font(.subheadline).foregroundStyle(.secondary)
                ViewThatFits(in: .horizontal) {
                    HStack { overviewActions }
                    VStack(alignment: .leading) { overviewActions }
                }
            }.fitnessCard()
            if preferences.insightsVisible && preferences.dashboard.hidden.contains(.scores) { insightsCard(snapshot: snapshot) }
        case .scores:
            let columns = dynamicType.isAccessibilitySize || preferences.dashboard.compactMetrics ? [GridItem(.flexible())] : Array(repeating: GridItem(.flexible(), spacing: 12, alignment: .top), count: 3)
            VStack(alignment: .leading, spacing: 14) {
                Label("Daily scores", systemImage: "chart.xyaxis.line").font(.headline)
                LazyVGrid(columns: columns, spacing: 14) { ForEach(DashboardRingKind.allCases) { DashboardRingButton(kind: $0, assessment: assessment, snapshot: snapshot, day: model.selectedDate, calendar: model.calendar, scoring: scoring, sleep: sleep, healthLoading: model.isReadingHealth) } }
                if daily.window.isPartial { Label("Day in progress · readings are provisional", systemImage: "clock").font(.caption).foregroundStyle(.secondary) }
            }.fitnessCard()
            if let error = scoringPreferences.error { ErrorMessage(title: "Review scoring settings", message: error) }
            if preferences.insightsVisible { insightsCard(snapshot: snapshot) }
        case .nutrition:
            VStack(alignment: .leading, spacing: 8) {
                NutritionSummaryCard(totals: daily.totals, goals: preferences.goals)
                HStack {
                    Button { openFood() } label: { Label("Quick food", systemImage: "plus").frame(minHeight: 44) }
                    Spacer()
                    NavigationLink { GoalsEditor() } label: { Text("Goals").frame(minHeight: 44) }
                }
            }
        case .health:
            healthConnectionPanel; DisclosureGroup("Health & Activity", isExpanded: $expandedHealth) { healthSummary(daily).padding(.top, 12) }.font(.headline).fitnessCard()
        case .sleep: DailySleepCard(model: sleep, day: model.selectedDate)
        case .training: RecentTrainingCard(day: model.selectedDate)
        case .weight:
            VStack(alignment: .leading, spacing: 12) { Label("Weight trend", systemImage: "scalemass").font(.headline); if weight.loading { LoadingState(message: "Reading weight trend") } else { WeightHistoryChart(points: WeightTrend.points(weight.weights, calendar: model.calendar)) }; Text("Last 14 local days · sources stay separate.").font(.caption).foregroundStyle(.secondary) }.fitnessCard()
        case .context:
            EmptyState(title: "Daily context", message: daily.window.isPartial ? "Today's totals can change as Health data syncs." : daily.totals.entryCount == 0 ? "No food logged; intake is unknown." : "Based on recorded food and available Health data.", symbol: "sparkles")
                .accessibilityIdentifier("dashboard.context")
        }
    }
    @ViewBuilder private func insightsCard(snapshot: HealthDaySnapshot?) -> some View {
        let values = scoring.estimates(day: model.selectedDate, snapshot: snapshot, sleep: sleep.nights.first, configuration: scoringPreferences.configuration, calendar: model.calendar)
        let insights = InsightEngine.daily(recovery: values.1, strain: values.0, sleepObservation: sleep.observation,
                                          partial: model.isToday)
        VStack(alignment: .leading, spacing: 10) {
            Label("Health insights", systemImage: "waveform.path.ecg").font(.headline)
            if scoring.loading || sleep.loading { LoadingState(message: "Reviewing observed inputs") }
            else { ForEach(insights) { insight in
                DisclosureGroup { Text(insight.detail).font(.footnote).foregroundStyle(.secondary) } label: {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(insight.title).font(.subheadline.weight(.semibold))
                        Text(insight.summary).font(.caption).foregroundStyle(.secondary)
                    }
                }.accessibilityElement(children: .combine)
            } }
        }.fitnessCard().accessibilityIdentifier("dashboard.insights")
    }
    private func openFood() {
        NotificationCenter.default.post(name: .composeFood, object: FoodLoggingRequest(day: model.selectedDate, meal: .unassigned))
    }
    @ViewBuilder private var overviewActions: some View {
        Button { openFood() } label: { Label("Log food", systemImage: "fork.knife").frame(minHeight: 44) }
            .buttonStyle(.borderedProminent)
        Button {
            NotificationCenter.default.post(name: .openWorkoutLog, object: TrainingAction.strength)
        } label: { Label("Start workout", systemImage: "dumbbell").frame(minHeight: 44) }
        .buttonStyle(.bordered)
        .disabled(!model.isToday)
    }

    @ViewBuilder
    private var healthConnectionPanel: some View {
        switch model.healthConnection {
        case .unavailable:
            EmptyState(title: "Apple Health unavailable", message: "Health data cannot be read on this device. Local food tracking remains available.", symbol: "heart")
        case .requesting:
            LoadingState(message: "Waiting for Apple Health read request")
        case .notRequested, .requestFailed:
            VStack(alignment: .leading, spacing: 12) {
                EmptyState(title: "Read your Apple Health data",
                           message: "Choose which energy, steps, workouts, and body-weight data to share. PersonalFitness only reads data and keeps it on this iPhone.", symbol: "heart")
                if case .requestFailed = model.healthConnection {
                    ErrorMessage(title: "Read request did not complete", message: "Unlock your iPhone and try again. Local tracking is still available.")
                }
                ActionButton(title: "Connect Apple Health", symbol: "heart") {
                    Task { await model.connectHealth(); await refresh(forceScores: true) }
                }
            }
        case .requestCompleted:
            DisclosureGroup("Apple Health connection") {
                Text("Apple Health read request completed. This does not confirm access to each data type. Missing data can mean no samples or that access is off. Manage access in Apple Health or Settings.")
                    .font(.footnote).foregroundStyle(.primary)
                ActionButton(title: "Review Apple Health access", symbol: "heart") {
                    Task { await model.connectHealth(); await refresh(forceScores: true) }
                }
                if let snapshot = model.healthSnapshot {
                    Text("Last refreshed: \(snapshot.refreshedAt.formatted(date: .abbreviated, time: .shortened))")
                        .font(.caption).foregroundStyle(.primary)
                }
            }
        }
    }

    @ViewBuilder
    private func healthSummary(_ nutrition: DailyNutrition) -> some View {
        let snapshot = model.healthSnapshot
        let assessment = model.assessment(for: nutrition)
        let energy = scoringPreferences.estimate(assessment, calendar: model.calendar)
        if case .loading = model.healthState { LoadingState(message: "Reading Apple Health") }
        SectionHeading(title: "Energy", subtitle: assessment.scopeTitle)
        Text("Through \(assessment.window.end.formatted(date: .abbreviated, time: .shortened)) · \(assessment.window.timeZoneIdentifier)")
            .font(.caption).foregroundStyle(.primary)
        if case .failed = model.healthState {
            ErrorMessage(title: "Health summary unavailable", message: "This day's read window could not be prepared. Refresh to try again.")
        }
        LazyVGrid(columns: columns, spacing: FitnessStyle.spacing) {
            HealthMetricCard(title: "Resting energy", reading: snapshot?.resting ?? .unavailable, symbol: "bed.double")
            HealthMetricCard(title: "Active energy", reading: snapshot?.active ?? .unavailable, symbol: "flame")
            MetricCard(title: "Estimated total expenditure", value: energy.expenditure, symbol: "sum")
            MetricCard(title: EnergyDisplay.balanceTitle(energy.balance), value: energy.balance, symbol: "equal.circle")
        }
        if energy.fallback { Text("Includes a configured estimate. Open the energy balance ring for sources.").font(.footnote) }
        else { EmptyState(title: assessment.balanceQuality == .unavailable ? "Balance unavailable" : assessment.balanceQuality == .partial ? "Partial-data estimate" : "Estimated energy balance",
                   message: assessment.balanceReasons.map(\.rawValue).joined(separator: " "),
                   symbol: assessment.balanceQuality == .unavailable ? "questionmark.circle" : "info.circle") }
        Text("Apple Watch energy estimates can change as Health data syncs.")
            .font(.footnote).foregroundStyle(.primary)
        SectionHeading(title: "Activity & body", subtitle: "Latest body-weight sample within the selected day; no carry-forward")
        LazyVGrid(columns: columns, spacing: FitnessStyle.spacing) {
            VStack(alignment: .leading, spacing: 8) {
                HealthMetricCard(title: "Steps", reading: snapshot?.steps ?? .unavailable, unit: "steps", symbol: "figure.walk")
                FitnessProgressBar(progress: GoalProgress(amount: snapshot?.steps.value, goal: preferences.goals.steps), color: FitnessTheme.blue)
                if let goal = preferences.goals.steps { Text("Goal \(goal.formatted()) steps").font(.caption) }
            }
            HealthMetricCard(title: "Body weight", reading: snapshot?.weight ?? .unavailable, unit: "kg", symbol: "scalemass")
        }
        WorkoutDaySummary(day: model.selectedDate, calendar: model.calendar,
                          health: snapshot?.workouts ?? .unavailable)
    }
}

#Preview {
    AppNavigation().modelContainer(for: [FoodEntry.self, SavedFood.self, SavedMeal.self, ExerciseRecord.self, WorkoutRoutine.self, StrengthSession.self, CardioSession.self, ManualWeight.self], inMemory: true)
}
