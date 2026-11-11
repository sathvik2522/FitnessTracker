import SwiftUI
import SwiftData

struct FoodLibraryView: View {
    var day: Date = .now
    @State private var logging: FoodChoice?
    @State private var deletingFood: SavedFood?
    @State private var deletingMeal: SavedMeal?
    @Environment(\.modelContext) private var context
    @Query(sort: \SavedFood.name) private var foods: [SavedFood]
    @Query(sort: \SavedMeal.name) private var meals: [SavedMeal]
    @State private var search = ""
    @State private var visibleLimit = 50
    private var matchingFoods: [SavedFood] { foods.filter { $0.matchesLibrary(search) } }
    @State private var savedMessage: String?
    @State private var newFood = false
    @State private var newMeal: MealKind?
    @State private var editFood: SavedFood?
    @State private var editMeal: SavedMeal?
    @State private var error: String?

    var body: some View {
        List {
            if let savedMessage { Label(savedMessage, systemImage: "checkmark.circle").foregroundStyle(.primary) }
            if !search.isEmpty && !foods.contains(where: { $0.matchesLibrary(search) })
                && !meals.contains(where: { $0.name.localizedStandardContains(search) }) {
                ContentUnavailableView.search(text: search)
            }
            Section { Text("Log to \(day.formatted(date: .abbreviated, time: .omitted)) · tap a saved item to edit its definition.").font(.footnote) }
            Section("Saved foods") {
                ForEach(Array(matchingFoods.prefix(visibleLimit))) { food in
                    Button { editFood = food } label: {
                        LibraryLabel(name: food.name, definition: try? food.definition())
                    }
                    .buttonStyle(.plain)
                    .swipeActions {
                        Button("Delete", role: .destructive) { deletingFood = food }
                        Button("Log") { select(food) }.tint(.accentColor)
                    }
                    Button("Log \(food.name)") { select(food) }.frame(minHeight: 44)
                }
                if matchingFoods.count > visibleLimit { Button("Show more foods") { visibleLimit += 50 }.frame(minHeight: 44) }
                if !foods.contains(where: { $0.libraryVisible }) { Text("Create your first food using the plus menu.").foregroundStyle(.secondary) }
            }
            ForEach(MealKind.allCases) { kind in
                Section(kind == .meal ? "Saved meals" : "Recipes") {
                    ForEach(meals.filter { $0.kind == kind && (search.isEmpty || $0.name.localizedStandardContains(search)) }) { meal in
                        Button { editMeal = meal } label: {
                            LibraryLabel(name: meal.name, definition: try? meal.definition())
                        }
                        .buttonStyle(.plain)
                        .swipeActions { Button("Delete", role: .destructive) { deletingMeal = meal } }
                        Button("Log \(meal.name)") {
                            do { logging = FoodChoice(id: meal.id, definition: try meal.definition(), sourceKind: meal.kind.rawValue) }
                            catch { self.error = error.localizedDescription }
                        }.frame(minHeight: 44)
                    }
                }
            }
            Section {
                Text("Library edits never rewrite diary entries. Ingredient nutrition is saved when selected; replace an ingredient to adopt an updated food definition.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
        .fitnessScreen()
        .navigationTitle("Food library")
        .searchable(text: $search, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search foods, meals and recipes")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button("New food", systemImage: "fork.knife") { newFood = true }
                    Button("New meal", systemImage: "square.stack") { newMeal = .meal }
                    Button("New recipe", systemImage: "list.bullet.rectangle") { newMeal = .recipe }
                } label: { Label("Create library item", systemImage: "plus") }
            }
        }
        .sheet(isPresented: $newFood) { FoodEditor() }
        .sheet(item: $newMeal) { MealEditor(kind: $0) }
        .sheet(item: $editFood) { FoodEditor(food: $0) }
        .sheet(item: $editMeal) { MealEditor(meal: $0) }
        .sheet(item: $logging) { choice in NavigationStack { EntryEditor(choice: choice, day: day) { logging = nil } } }
        .confirmationDialog("Delete saved food?", isPresented: Binding(get: { deletingFood != nil }, set: { if !$0 { deletingFood = nil } })) {
            Button("Delete saved food", role: .destructive) { if let item = deletingFood { remove(item) }; deletingFood = nil }
        } message: { Text("Past diary entries and ingredient snapshots will stay unchanged.") }
        .confirmationDialog("Delete saved meal?", isPresented: Binding(get: { deletingMeal != nil }, set: { if !$0 { deletingMeal = nil } })) {
            Button("Delete saved meal", role: .destructive) { if let item = deletingMeal { remove(item) }; deletingMeal = nil }
        } message: { Text("Past diary entries will stay unchanged.") }
        .onChange(of: foods.map(\.name)) { old, new in revealLibraryChange(name: new.first { !old.contains($0) }) }
        .onChange(of: meals.map(\.name)) { old, new in revealLibraryChange(name: new.first { !old.contains($0) }) }
        .onChange(of: search) { _, _ in visibleLimit = 50 }
        .nutritionError($error)
    }

    private func revealLibraryChange(name: String?) {
        // Reveal a newly saved/renamed item even beyond the first catalog page.
        // The old search must not make a successful save appear lost.
        search = name ?? ""
        savedMessage = "Library updated. Existing diary snapshots are unchanged."
    }

    private func select(_ food: SavedFood) {
        do { logging = FoodChoice(id: food.id, definition: try food.definition(), sourceKind: "food") }
        catch { self.error = error.localizedDescription }
    }

    private func remove<T: PersistentModel>(_ item: T) {
        do { try NutritionStore(context: context).delete(item) }
        catch { self.error = error.localizedDescription }
    }
}

private struct LibraryLabel: View {
    let name: String
    let definition: FoodDefinition?
    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(definition?.displayName ?? name).font(.headline).foregroundStyle(.primary)
            if let definition {
                Text("\(EnergyDisplay.kilocalories(definition.nutrients.calories)) kcal per \(NutritionNumber.text(definition.referenceQuantity)) \(definition.referenceUnit.rawValue)")
                    .font(.subheadline).foregroundStyle(.secondary)
                Text("Protein \(NutritionNumber.text(definition.nutrients.protein)) g · Carbs \(NutritionNumber.text(definition.nutrients.carbohydrates)) g · Fat \(NutritionNumber.text(definition.nutrients.fat)) g")
                    .font(.caption).foregroundStyle(.primary)
                if let origin = definition.catalog {
                    Text("\(origin.source == "usda-sr-legacy" ? "USDA SR Legacy" : origin.source) · \(origin.userModified ? "personally edited" : "generic ingredient") · \(origin.license)").font(.caption).foregroundStyle(.secondary)
                }
                if let serving = definition.sourceServings?.first {
                    Text("Source portion: \(serving.label)").font(.caption).foregroundStyle(.secondary)
                }
            } else { Text("Saved nutrition unavailable; review or delete this item.").font(.caption).foregroundStyle(.secondary) }
        }
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

struct FoodPicker: View {
    var foodsOnly = false
    var quickAdd: ((FoodChoice) -> Void)? = nil
    var repeatPortion: ((FoodEntry) -> Void)? = nil
    let choose: (FoodChoice) -> Void
    @Query(sort: [SortDescriptor(\SavedFood.useCount, order: .reverse), SortDescriptor(\SavedFood.name)]) private var foods: [SavedFood]
    @Query(sort: [SortDescriptor(\SavedMeal.lastUsedAt, order: .reverse)]) private var meals: [SavedMeal]
    @Query(sort: \FoodEntry.loggedAt, order: .reverse) private var diaryEntries: [FoodEntry]
    @AppStorage("personalFitness.favoriteFoods.v1", store: GoalPreferences.currentDefaults) private var favoriteStorage = ""
    @State private var search = ""
    @State private var visibleLimit = 50
    @State private var scope: FoodSearchScope = .all
    private var matchingFoods: [SavedFood] {
        foods.compactMap { food -> (SavedFood, Int)? in
            guard food.libraryVisible, let definition = try? food.definition(),
                  let score = FoodSearchRanking.score(name: definition.name, aliases: definition.aliases ?? [], query: search) else { return nil }
            if scope == .meals { return nil }
            if scope == .custom && definition.catalog != nil { return nil }
            if scope == .recent && food.lastUsedAt == nil { return nil }
            if scope == .frequent && food.useCount == 0 { return nil }
            if scope == .favorites && !favoriteIDs.contains(food.id) { return nil }
            return (food, score)
        }.sorted { a, b in
            if a.1 != b.1 { return a.1 < b.1 }
            if scope == .recent { return (a.0.lastUsedAt ?? .distantPast) > (b.0.lastUsedAt ?? .distantPast) }
            if a.0.useCount != b.0.useCount { return a.0.useCount > b.0.useCount }
            return a.0.name.localizedStandardCompare(b.0.name) == .orderedAscending
        }.map { $0.0 }
    }
    @State private var creating = false
    @State private var creatingMeal: MealKind?
    @State private var pendingChoice: FoodChoice?
    @State private var savedMessage: String?
    @State private var error: String?

    private var frequent: [SavedFood] { search.isEmpty && scope == .all ? Array(foods.filter { $0.useCount > 0 && $0.libraryVisible }.prefix(5)) : [] }
    private var recent: [SavedMeal] { search.isEmpty && scope == .all ? Array(meals.filter { $0.lastUsedAt != nil }.prefix(5)) : [] }
    private var favoriteIDs: Set<UUID> { Set(favoriteStorage.split(separator: ",").compactMap { UUID(uuidString: String($0)) }) }
    private var recentPortions: [FoodEntry] {
        guard repeatPortion != nil, search.isEmpty, scope == .all || scope == .recent else { return [] }
        var result: [FoodEntry] = []
        for entry in diaryEntries where entry.loggedAt <= .now {
            if !result.contains(where: { $0.sourceID == entry.sourceID && $0.sourceKind == entry.sourceKind && $0.name == entry.name && $0.quantity == entry.quantity && $0.unitRaw == entry.unitRaw && $0.referenceSnapshot == entry.referenceSnapshot && $0.calories == entry.calories && $0.proteinGrams == entry.proteinGrams && $0.carbohydrateGrams == entry.carbohydrateGrams && $0.fatGrams == entry.fatGrams }) {
                result.append(entry)
                if result.count == 5 { break }
            }
        }
        return result
    }

    var body: some View {
        List {
            Section {
                ScrollView(.horizontal) {
                    HStack {
                        ForEach(FoodSearchScope.allCases.filter { !foodsOnly || $0 != .meals }) { option in
                            Button(option.rawValue) { scope = option; visibleLimit = 50 }
                                .buttonStyle(.bordered).tint(scope == option ? FitnessTheme.blue : .secondary)
                                .accessibilityAddTraits(scope == option ? .isSelected : [])
                                .frame(minHeight: 44)
                        }
                    }
                }
            }.listRowBackground(FitnessTheme.card)
            if !recentPortions.isEmpty {
                Section("Recent portions") {
                    ForEach(recentPortions) { entry in
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(entry.name).font(.headline)
                                Text("\(NutritionNumber.text(entry.quantity)) \(entry.unit.rawValue) · \(EnergyDisplay.kilocalories(entry.calories)) kcal")
                                    .font(.caption).foregroundStyle(.secondary)
                            }.frame(maxWidth: .infinity, alignment: .leading)
                            Button { repeatPortion?(entry) } label: { Image(systemName: "plus.circle.fill").font(.title2).frame(width: 44, height: 44) }
                                .buttonStyle(.borderless).accessibilityLabel("Repeat portion")
                                .accessibilityValue("\(entry.name), \(NutritionNumber.text(entry.quantity)) \(entry.unit.rawValue)")
                                .accessibilityHint("Add \(entry.name), \(NutritionNumber.text(entry.quantity)) \(entry.unit.rawValue), with its original nutrition")
                                .accessibilityIdentifier("food.repeat.\(entry.id.uuidString)")
                        }
                    }
                }.listRowBackground(FitnessTheme.card)
            }
            if let savedMessage { Label(savedMessage, systemImage: "checkmark.circle").foregroundStyle(.primary) }
            if !search.isEmpty && !foods.contains(where: { $0.matchesLibrary(search) })
                && (foodsOnly || !meals.contains(where: { $0.name.localizedStandardContains(search) })) {
                ContentUnavailableView.search(text: search)
            }
            if !frequent.isEmpty {
                Section("Frequent foods") {
                    ForEach(frequent) { food in foodRow(food, quick: true) }
                }.listRowBackground(FitnessTheme.card)
            }
            Section(scope == .recent ? "Recent foods" : scope == .favorites ? "Favorite foods" : scope == .custom ? "Custom foods" : "Saved foods") {
                if matchingFoods.isEmpty && scope != .meals { Text(scope == .favorites ? "No favorites yet. Use the star beside a food to save it here." : "No foods in this filter. Search the library or create a food.").font(.subheadline).foregroundStyle(.secondary) }
                ForEach(Array(matchingFoods.filter { food in !frequent.contains(where: { $0.id == food.id }) }.prefix(visibleLimit))) { food in foodRow(food, quick: false) }
                if matchingFoods.count > visibleLimit { Button("Show more foods") { visibleLimit += 50 }.frame(minHeight: 44) }
            }.listRowBackground(FitnessTheme.card)
            if !foodsOnly && (scope == .all || scope == .meals || scope == .recent) {
                if !recent.isEmpty {
                    Section("Recently used meals & recipes · quick add one serving") {
                        ForEach(recent) { meal in mealRow(meal, quick: true) }
                    }.listRowBackground(FitnessTheme.card)
                }
                Section("Meals & recipes") {
                    ForEach(meals.filter { meal in
                        (search.isEmpty || meal.name.localizedStandardContains(search)) && (scope != .recent || meal.lastUsedAt != nil) && !recent.contains(where: { $0.id == meal.id })
                    }) { meal in mealRow(meal, quick: false) }
                }.listRowBackground(FitnessTheme.card)
            }
            if !foodsOnly {
                Section {
                    Menu("Create meal or recipe") {
                        Button("New meal") { creatingMeal = .meal }
                        Button("New recipe") { creatingMeal = .recipe }
                    }.frame(minHeight: 44)
                }.listRowBackground(FitnessTheme.card)
            }
            if !foods.contains(where: { $0.libraryVisible }) && (foodsOnly || meals.isEmpty) {
                EmptyState(title: "Build your food library", message: "Create a food from its label or your own nutrition values. No internet connection is needed.", symbol: "fork.knife")
                Button("Create first food") { creating = true }
            }
        }
        .fitnessScreen()
        .searchable(text: $search, placement: .navigationBarDrawer(displayMode: .always), prompt: foodsOnly ? "Search saved foods" : "Search foods, meals and recipes")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) { Button("Create food") { creating = true } }
        }
        .sheet(item: $creatingMeal, onDismiss: continueSelection) { kind in
            MealEditor(kind: kind) { choice, log in
                savedMessage = "Saved \(choice.definition.name) to library."
                if log { pendingChoice = choice }
            }
        }
        .sheet(isPresented: $creating, onDismiss: continueSelection) {
            FoodEditor(continuationTitle: foodsOnly ? "Save & use ingredient" : "Save & log") { choice, continueFlow in
                savedMessage = foodsOnly ? "Saved \(choice.definition.name). Select it as an ingredient." : "Saved \(choice.definition.name) to library. Select it to log a portion."
                search = ""
                if continueFlow { pendingChoice = choice }
            }
        }
        .onChange(of: search) { _, _ in visibleLimit = 50 }
        .onChange(of: scope) { _, _ in visibleLimit = 50 }
        .nutritionError($error)
    }

    private func continueSelection() {
        if let choice = pendingChoice { pendingChoice = nil; choose(choice) }
    }

    private func foodRow(_ food: SavedFood, quick: Bool) -> some View {
        pickerRow(name: food.name, definition: try? food.definition(), quick: quick, favoriteID: food.id) {
            FoodChoice(id: food.id, definition: try food.definition(), sourceKind: "food")
        }
    }
    private func mealRow(_ meal: SavedMeal, quick: Bool) -> some View {
        pickerRow(name: meal.name, definition: try? meal.definition(), quick: quick) {
            FoodChoice(id: meal.id, definition: try meal.definition(), sourceKind: meal.kind.rawValue)
        }
    }
    private func pickerRow(name: String, definition: FoodDefinition?, quick: Bool, favoriteID: UUID? = nil,
                           choice: @escaping () throws -> FoodChoice) -> some View {
        HStack {
            Button {
                do { choose(try choice()) } catch { self.error = error.localizedDescription }
            } label: {
                VStack(alignment: .leading, spacing: 4) {
                    Text(definition?.displayName ?? name).font(.headline).foregroundStyle(.primary)
                    if let definition {
                        Text("\(EnergyDisplay.kilocalories(definition.nutrients.calories)) kcal · \(NutritionNumber.text(definition.referenceQuantity)) \(definition.referenceUnit.rawValue)")
                            .font(.caption).foregroundStyle(.secondary)
                    } else { Text("Nutrition unavailable").font(.caption).foregroundStyle(.secondary) }
                }.frame(maxWidth: .infinity, minHeight: 44, alignment: .leading).contentShape(Rectangle())
            }
                .buttonStyle(.plain)
            if let favoriteID {
                Button {
                    var ids = favoriteIDs
                    if !ids.insert(favoriteID).inserted { ids.remove(favoriteID) }
                    favoriteStorage = ids.map(\.uuidString).sorted().joined(separator: ",")
                } label: { Image(systemName: favoriteIDs.contains(favoriteID) ? "star.fill" : "star").frame(width: 44, height: 44) }
                    .buttonStyle(.borderless)
                    .accessibilityLabel("\(favoriteIDs.contains(favoriteID) ? "Remove" : "Add") \(name) \(favoriteIDs.contains(favoriteID) ? "from" : "to") favorites")
            }
            if quick, let quickAdd, let definition {
                Button {
                    do { quickAdd(try choice()) } catch { self.error = error.localizedDescription }
                } label: { Image(systemName: "plus.circle.fill").frame(width: 44, height: 44) }
                .buttonStyle(.borderless)
                .accessibilityLabel("Quick add \(name), \(NutritionNumber.text(definition.referenceQuantity)) \(definition.referenceUnit.rawValue)")
            }
        }
    }
}
