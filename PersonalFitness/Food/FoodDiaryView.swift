import SwiftUI
import SwiftData

struct FoodDiaryView: View {
    @Environment(\.dynamicTypeSize) private var dynamicType
    @Environment(\.scenePhase) private var scenePhase
    @State private var now = Date.now
    @Binding var day: Date
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                VStack(spacing: 6) {
                    Text(day, format: .dateTime.weekday(.wide).month(.wide).day().year())
                        .font(.subheadline.weight(.semibold)).accessibilityIdentifier("diary.selectedDate")
                    if dynamicType.isAccessibilitySize {
                        dayPicker
                        HStack { previousDay; Spacer(); nextDay }
                    } else { HStack { previousDay; dayPicker.frame(maxWidth: .infinity); nextDay } }
                }.padding(.horizontal).padding(.vertical, 8)
                DiaryDayList(day: day)
            }
            .navigationTitle("Food & Nutrition").navigationBarTitleDisplayMode(.inline)
            .fitnessScreen()
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    NavigationLink { FoodLibraryView(day: day) } label: { Label("Food library", systemImage: "books.vertical") }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { add(.unassigned) } label: { Label("Add food", systemImage: "plus.circle.fill") }
                }
            }
            .onChange(of: scenePhase) { _, phase in if phase == .active { now = .now } }
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.significantTimeChangeNotification)) { _ in now = .now }
        }
    }
    private func add(_ meal: DiaryMeal) { NotificationCenter.default.post(name: .composeFood, object: FoodLoggingRequest(day: day, meal: meal)) }
    private var dayPicker: some View { DatePicker("Diary date", selection: $day, in: ...now, displayedComponents: .date).labelsHidden().accessibilityLabel("Diary date") }
    private var previousDay: some View {
        Button { shiftDay(-1) } label: { Image(systemName: "chevron.left").frame(width: 44, height: 44) }.accessibilityLabel("Previous diary day")
    }
    private var nextDay: some View {
        Button { shiftDay(1) } label: { Image(systemName: "chevron.right").frame(width: 44, height: 44) }.accessibilityLabel("Next diary day")
            .disabled(Calendar.current.isDate(day, inSameDayAs: now))
    }
    private func shiftDay(_ offset: Int) {
        if let shifted = Calendar.current.date(byAdding: .day, value: offset, to: day) { day = min(shifted, .now) }
    }
}

private struct DiaryDayList: View {
    @Environment(ScoringPreferences.self) private var scoringPreferences
    let day: Date
    @Environment(\.modelContext) private var context
    @Environment(GoalPreferences.self) private var preferences
    @Query private var entries: [FoodEntry]
    @State private var editing: FoodEntry?
    @State private var copying: FoodEntry?
    @State private var deleting: FoodEntry?
    @State private var error: String?
    @State private var model = DashboardModel()
    @State private var collapsedMeals = Set<DiaryMeal>()
    @Environment(\.scenePhase) private var phase

    init(day: Date) {
        self.day = day
        let interval = Calendar.current.dateInterval(of: .day, for: day)
        // An invalid interval produces an empty query and an explicit unavailable
        // overview, never an arbitrary historical date or a force unwrap.
        let start = interval?.start ?? day, end = interval?.end ?? day
        _entries = Query(filter: #Predicate<FoodEntry> { $0.loggedAt >= start && $0.loggedAt < end }, sort: [SortDescriptor(\FoodEntry.loggedAt, order: .reverse)])
    }
    private var totals: NutritionTotals {
        NutritionTotals(portions: entries.filter { $0.loggedAt <= Date.now }.map { NutritionPortion(calories: $0.calories, protein: $0.proteinGrams, carbohydrates: $0.carbohydrateGrams, fat: $0.fatGrams) })
    }
    private var selectedAssessment: EnergyAssessment? {
        guard case .loaded(let nutrition) = model.state,
              Calendar.current.isDate(nutrition.window.start, inSameDayAs: day) else { return nil }
        return model.assessment(for: nutrition)
    }
    private var balanceLoading: Bool {
        if case .loading = model.state { return true }
        if case .loading = model.healthState { return true }
        return false
    }
    private var meals: [DiaryMeal] {
        let order: [DiaryMeal] = [.breakfast, .lunch, .dinner, .snacks]
        // Keep legacy/unassigned logs easy to find without assigning them a meal.
        return (entries.contains { $0.mealCategory == .unassigned } ? [.unassigned] : []) + order
    }
    var body: some View {
        List {
            Section {
                FoodOverview(totals: totals, goals: preferences.goals,
                             balance: selectedAssessment, balanceLoading: balanceLoading)
                if entries.isEmpty { Text("No intake recorded. An empty diary does not establish zero intake.").font(.caption) }
            }.listRowBackground(FitnessTheme.card)
            ForEach(meals) { meal in
                let portions = entries.filter { $0.mealCategory == meal }
                Section {
                    HStack(spacing: 12) {
                        Image(systemName: meal.symbol).font(.title2).foregroundStyle(meal.tint).frame(minWidth: 32)
                        Button {
                            if !collapsedMeals.insert(meal).inserted { collapsedMeals.remove(meal) }
                        } label: {
                          HStack {
                           VStack(alignment: .leading, spacing: 4) {
                            Text(meal.rawValue).font(.headline).foregroundStyle(.primary)
                            let subtotal = NutritionTotals(portions: portions.map { NutritionPortion(calories: $0.calories, protein: $0.proteinGrams, carbohydrates: $0.carbohydrateGrams, fat: $0.fatGrams) })
                            Text(portions.isEmpty ? "Not logged" : EnergyDisplay.kilocalories(subtotal.calories) + " kcal")
                                .font(.subheadline.monospacedDigit()).foregroundStyle(.secondary)
                           }
                           Spacer()
                           Image(systemName: collapsedMeals.contains(meal) ? "chevron.down" : "chevron.up").foregroundStyle(.secondary)
                          }.frame(maxWidth: .infinity, minHeight: 44, alignment: .leading).contentShape(Rectangle())
                        }.buttonStyle(.plain)
                         .accessibilityLabel("\(meal.rawValue), \(portions.count) \(portions.count == 1 ? "portion" : "portions")")
                         .accessibilityValue(collapsedMeals.contains(meal) ? "Collapsed" : "Expanded")
                         .accessibilityHint("Toggle meal entries")
                         .accessibilityIdentifier("diary.meal.\(meal.rawValue)")
                        Button { add(meal) } label: { Image(systemName: "plus.circle.fill").font(.title2).frame(minWidth: 44, minHeight: 44) }
                            .buttonStyle(.borderless).accessibilityLabel("Add food to \(meal.rawValue)")
                    }
                    if !collapsedMeals.contains(meal) { ForEach(portions) { entry in entryRow(entry) } }
                }.listRowBackground(FitnessTheme.card)
            }
            Section {
                Button { add(.unassigned) } label: {
                    Label("Add Food", systemImage: "plus").frame(maxWidth: .infinity, minHeight: 44).contentShape(Rectangle())
                }.buttonStyle(.borderedProminent).tint(FitnessTheme.action).foregroundStyle(.white)
                NavigationLink("Saved foods, meals & recipes") { FoodLibraryView(day: day) }
            }.listRowBackground(FitnessTheme.card)
        }
        .safeAreaInset(edge: .bottom) { Color.clear.frame(height: 24) }
        .fitnessScreen()
        .task(id: day) { await refresh() }
        .onChange(of: phase) { _, next in if next == .active { Task { await refresh() } } }
        .onChange(of: scoringPreferences.configuration) { _, _ in
            if !balanceLoading, let assessment = selectedAssessment { scoringPreferences.preserveHistoricalEstimate(assessment, calendar: .current) }
        }
        .onReceive(NotificationCenter.default.publisher(for: .nutritionDidChange)) { _ in Task { await refresh() } }
        .confirmationDialog("Delete diary entry?", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }), titleVisibility: .visible) {
            Button("Delete entry", role: .destructive) {
                if let deleting { do { try NutritionStore(context: context).delete(deleting) } catch { self.error = error.localizedDescription } }
                deleting = nil
            }
        } message: { Text("This removes the logged portion, not its saved food definition.") }
        .sheet(item: $editing) { entry in NavigationStack { EntryEditor(entry: entry) } }
        .sheet(item: $copying) { entry in NavigationStack { EntryEditor(copying: entry) { copying = nil } } }
        .nutritionError($error)
    }
    private func refresh() async {
        model.updateToday(.now, calendar: .current); model.select(day)
        await model.load(from: FoodEntryStore(context: context))
        if let assessment = selectedAssessment { scoringPreferences.preserveHistoricalEstimate(assessment, calendar: .current) }
    }
    private func add(_ meal: DiaryMeal) { NotificationCenter.default.post(name: .composeFood, object: FoodLoggingRequest(day: day, meal: meal)) }
    private func entryRow(_ entry: FoodEntry) -> some View {
        Button { editing = entry } label: {
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline) {
                    Text(entry.name).font(.headline)
                    Spacer(minLength: 8)
                    Text("\(EnergyDisplay.kilocalories(entry.calories)) kcal").font(.subheadline.monospacedDigit())
                }
                Text("\(entry.mealCategory.rawValue) · \(NutritionNumber.text(entry.quantity)) \(entry.unit.rawValue) · \(entry.loggedAt.formatted(date: .omitted, time: .shortened))")
                    .font(.caption).foregroundStyle(.secondary)
                Text("P \(entry.proteinGrams.formatted(.number.precision(.fractionLength(0...1)))) g · C \(entry.carbohydrateGrams.formatted(.number.precision(.fractionLength(0...1)))) g · F \(entry.fatGrams.formatted(.number.precision(.fractionLength(0...1)))) g")
                    .font(.caption).foregroundStyle(.secondary)
            }.frame(maxWidth: .infinity, minHeight: 44, alignment: .leading).padding(.vertical, 4).contentShape(Rectangle())
        }.buttonStyle(.plain).accessibilityHint("Edit this diary portion")
        .swipeActions { Button("Delete", role: .destructive) { deleting = entry } }
        .contextMenu {
            Button("Edit portion") { editing = entry }
            Button("Copy portion") { copying = entry }
            Menu("Move to meal") {
                ForEach(DiaryMeal.allCases) { meal in Button(meal.rawValue) {
                    do { try NutritionStore(context: context).moveEntry(id: entry.id, meal: meal) }
                    catch { self.error = error.localizedDescription }
                } }
            }
            Button("Delete entry", role: .destructive) { deleting = entry }
        }
    }
}

struct FoodOverview: View {
    @Environment(ScoringPreferences.self) private var scoringPreferences
    let totals: NutritionTotals
    let goals: NutritionGoals
    let balance: EnergyAssessment?
    var balanceLoading = false
    @Environment(\.dynamicTypeSize) private var typeSize
    private var consumed: Double? { totals.entryCount == 0 ? nil : totals.calories }
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if typeSize.isAccessibilitySize { calorieRing; calorieDetails }
            else { HStack(spacing: 18) { calorieRing; calorieDetails } }
            let columns = typeSize.isAccessibilitySize ? [GridItem(.flexible())] : Array(repeating: GridItem(.flexible(), spacing: 10), count: 3)
            LazyVGrid(columns: columns, spacing: 12) {
                MacroCompactCard(title: "Protein", amount: totals.entryCount == 0 ? nil : totals.protein, goal: goals.protein, color: FitnessTheme.protein)
                MacroCompactCard(title: "Carbs", amount: totals.entryCount == 0 ? nil : totals.carbohydrates, goal: goals.carbohydrates, color: FitnessTheme.carbs)
                MacroCompactCard(title: "Fat", amount: totals.entryCount == 0 ? nil : totals.fat, goal: goals.fat, color: FitnessTheme.fat)
            }
            if totals.entryCount > 0 {
                // Retain a single accessible combined total for quick diary review.
                if let cal = totals.calories, let p = totals.protein, let c = totals.carbohydrates, let f = totals.fat {
                    Text("Recorded total: \(EnergyDisplay.kilocalories(cal)) kcal · P \(p.formatted(.number.precision(.fractionLength(0...1)))) g · C \(c.formatted(.number.precision(.fractionLength(0...1)))) g · F \(f.formatted(.number.precision(.fractionLength(0...1)))) g")
                        .font(.caption).foregroundStyle(.secondary).accessibilityIdentifier("diary.totals")
                } else { Text("Some saved nutrition values are invalid. Review the affected entries.") }
            }
        }.padding(.vertical, 8)
    }
    private var calorieRing: some View {
        FitnessRing(value: consumed.map { EnergyDisplay.kilocalories($0) } ?? "—", unit: "kcal recorded", color: FitnessTheme.carbs,
                    fraction: GoalProgress(amount: consumed, goal: goals.calories).fraction)
            .frame(maxWidth: 170)
            .accessibilityLabel("Calories consumed, \(consumed.map { EnergyDisplay.kilocalories($0) + " kilocalories" } ?? "unavailable, no food logged")")
    }
    private var calorieDetails: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let goal = goals.calories {
                Text("Goal \(EnergyDisplay.kilocalories(goal)) kcal").font(.subheadline.bold())
                if let left = GoalProgress(amount: consumed, goal: goal).remaining {
                    Text("\(EnergyDisplay.kilocalories(abs(left))) kcal \(left < 0 ? "over goal" : "remaining")").font(.subheadline)
                }
            } else { NavigationLink("Configure goals") { GoalsEditor() }.font(.subheadline) }
            if balanceLoading { ProgressView("Reading energy").font(.caption) }
            else if let balance, let net = scoringPreferences.estimate(balance, calendar: .current).balance {
                Text("\(EnergyDisplay.balanceTitle(net)): \(EnergyDisplay.kilocalories(net)) kcal").font(.caption)
                Text(scoringPreferences.estimate(balance, calendar: .current).fallback ? "Prediction / mixed sources · unverified" : balance.window.isPartial ? "Provisional · day in progress" : "Coverage unverified").font(.caption).foregroundStyle(.secondary)
            }
            else { NavigationLink("Set up energy estimate") { ScoringSettingsView() }.font(.caption) }
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}

extension DiaryMeal {
    var symbol: String {
        switch self { case .breakfast: return "sun.max.fill"; case .lunch: return "sun.haze.fill"; case .dinner: return "moon.stars.fill"; case .snacks: return "carrot.fill"; case .unassigned: return "tray.fill" }
    }
    var tint: Color {
        switch self { case .breakfast, .lunch: return FitnessTheme.fat; case .dinner: return FitnessTheme.sleep; case .snacks: return FitnessTheme.energy; case .unassigned: return FitnessTheme.blue }
    }
}

/// One stable modal session is owned by AppNavigation. Food and recipe editors
/// maintain value drafts; only successful, validated saves touch SwiftData.
struct AddFoodFlow: View {
    let day: Date
    let meal: DiaryMeal
    init(day: Date, meal: DiaryMeal = .unassigned) { self.day = day; self.meal = meal }
    @Environment(\.dismiss) private var dismiss
    @State private var selected: FoodChoice?
    @Environment(\.modelContext) private var context
    @State private var quickID = UUID()
    @State private var quickSaved = false
    @State private var error: String?
    var body: some View {
        NavigationStack {
            FoodPicker(quickAdd: quickAdd, repeatPortion: repeatPortion) { selected = $0 }
                .safeAreaInset(edge: .top) {
                    Text("Logging to \(day.formatted(date: .abbreviated, time: .omitted)) · \(meal.rawValue)").font(.caption).padding(8)
                }
                .navigationTitle("Add food").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
                .navigationDestination(item: $selected) { choice in EntryEditor(choice: choice, day: day, meal: meal) { dismiss() } }
                .fitnessScreen()
        }.nutritionError($error)
    }
    private func quickAdd(_ choice: FoodChoice) {
        guard !quickSaved else { return }
        do {
            try NutritionStore(context: context).saveEntry(id: quickID, definition: choice.definition,
                quantity: choice.definition.referenceQuantity, unit: choice.definition.referenceUnit,
                loggedAt: DiaryDate.timestamp(for: day), sourceID: choice.id, sourceKind: choice.sourceKind, meal: meal)
            quickSaved = true; FitnessFeedback.success(); dismiss()
        } catch { self.error = error.localizedDescription }
    }
    private func repeatPortion(_ entry: FoodEntry) {
        guard !quickSaved else { return }
        do {
            try NutritionStore(context: context).repeatEntry(entry, id: quickID, loggedAt: DiaryDate.timestamp(for: day), meal: meal)
            quickSaved = true; FitnessFeedback.success(); dismiss()
        } catch { self.error = error.localizedDescription }
    }
}
