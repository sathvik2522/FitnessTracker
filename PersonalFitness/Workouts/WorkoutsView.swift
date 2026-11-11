import SwiftUI
import SwiftData

struct WorkoutsView: View {
    @Binding private var launchAction: TrainingAction?
    init(launchAction: Binding<TrainingAction?> = .constant(nil)) { _launchAction = launchAction }
    @Environment(\.modelContext) private var context
    @Query(sort: \StrengthSession.start, order: .reverse) private var sessions: [StrengthSession]
    @Query(sort: \CardioSession.start, order: .reverse) private var cardio: [CardioSession]
    @Query(sort: \WorkoutRoutine.name) private var routines: [WorkoutRoutine]
    @State private var selectedSession: StrengthDraft?
    @State private var selectedCardio: CardioDraft?
    @State private var editRoutine: WorkoutRoutine?
    @State private var newRoutine = false
    @State private var newCardio = false
    @State private var stairs = false
    @State private var error: String?
    @State private var confirmingDeletion = false
    @State private var deleteAction: (() throws -> Void)?
    private var hasActive: Bool { sessions.contains { $0.statusRaw == "active" } }
    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(alignment: .leading, spacing: 10) {
                        Label(hasActive ? "Workout in progress" : "Ready to train?", systemImage: "dumbbell.fill").font(.title3.bold())
                        Text(hasActive ? "Your saved workout is ready to resume." : "Start a workout or choose a saved routine below.").foregroundStyle(.secondary)
                        ViewThatFits(in: .horizontal) {
                            HStack { trainingActions }
                            VStack(alignment: .leading) { trainingActions }
                        }
                    }.padding(.vertical, 6)
                    .listRowBackground(FitnessTheme.card)
                }
                Section("Strength training") {
                    ForEach(sessions.filter { $0.statusRaw == "active" }) { session in
                        Button { open(session) } label: {
                            Label("Resume \(session.name)", systemImage: "play.circle.fill").font(.headline).padding(.vertical, 8)
                        }
                    }
                    Button("Start empty workout", systemImage: "plus.circle") { start() }.frame(minHeight: 44).disabled(hasActive)
                    if hasActive { Text("Resume or cancel your active workout before starting another.").font(.footnote) }
                    NavigationLink("Exercise library & progression") { ExerciseLibraryView() }.frame(minHeight: 44)
                }.listRowBackground(FitnessTheme.card)
                Section("Saved routines") {
                    if routines.isEmpty { Text("Save a routine for quick access here.").foregroundStyle(.secondary) }
                    ForEach(routines) { routine in
                        VStack(alignment: .leading, spacing: 10) {
                            Text(routine.name).font(.headline)
                            Text((try? routine.exercises().count).map { "\($0) exercises" } ?? "Saved routine details unavailable").font(.caption).foregroundStyle(.secondary)
                            ViewThatFits(in: .horizontal) {
                                HStack { routineActions(routine) }
                                VStack(alignment: .leading) { routineActions(routine) }
                            }
                        }
                        .accessibilityElement(children: .contain)
                        .swipeActions { Button("Delete", role: .destructive) { remove(routine) } }
                    }
                    Button("New routine", systemImage: "plus") { newRoutine = true }.frame(minHeight: 44)
                }.listRowBackground(FitnessTheme.card)
                Section("Cardio") {
                    Button("Log stair climber", systemImage: "figure.stair.stepper") { stairs = true }.frame(minHeight: 44)
                }.listRowBackground(FitnessTheme.card)
                Section("Strength history · tap to edit") {
                    if sessions.filter({ $0.statusRaw != "active" }).isEmpty { Text("No finished or cancelled sessions yet.").foregroundStyle(.secondary) }
                    ForEach(sessions.filter { $0.statusRaw != "active" }) { session in
                        Button { open(session) } label: {
                            VStack(alignment: .leading, spacing: 6) {
                                Text(session.name).font(.headline)
                                Text("\(session.statusRaw.capitalized) · \(session.start.formatted(date: .abbreviated, time: .shortened))").font(.subheadline).foregroundStyle(.secondary)
                            }.frame(maxWidth: .infinity, minHeight: 44, alignment: .leading).contentShape(Rectangle())
                        }.buttonStyle(.plain)
                        .swipeActions { Button("Delete", role: .destructive) { remove(session) } }
                    }
                }
                .listRowBackground(FitnessTheme.card)
                Section("Cardio history · tap to edit") {
                    if cardio.isEmpty { Text("No manual cardio logged yet.").foregroundStyle(.secondary) }
                    ForEach(cardio) { session in
                        Button {
                            do { selectedCardio = try session.draft() } catch { self.error = error.localizedDescription }
                        } label: {
                            VStack(alignment: .leading, spacing: 6) {
                                Text(session.activityRaw).font(.headline)
                                if let draft = try? session.draft() { CardioSummary(draft: draft) }
                                else { Text("Saved details unavailable").foregroundStyle(.secondary) }
                            }.frame(maxWidth: .infinity, minHeight: 44, alignment: .leading).contentShape(Rectangle())
                        }.buttonStyle(.plain)
                        .swipeActions { Button("Delete", role: .destructive) { remove(session) } }
                    }
                }
                .listRowBackground(FitnessTheme.card)
                Text("Manual logs stay separate from Apple Health. Possible time/activity matches are labeled on the dashboard; no records are silently merged. Manual calories never change expenditure.").font(.footnote).foregroundStyle(.secondary)
            }
            .fitnessScreen().navigationBarTitleDisplayMode(.inline).navigationTitle("Training")
            .onChange(of: launchAction, initial: true) { _, action in
                guard let action else { return }
                launchAction = nil
                switch action {
                case .strength:
                    if let active = sessions.first(where: { $0.statusRaw == "active" }) { open(active) }
                    else { start() }
                case .cardio: newCardio = true
                case .stairs: stairs = true
                }
            }
            .sheet(item: $selectedSession) { StrengthSessionView(draft: $0) }
            .sheet(item: $selectedCardio) { CardioEditor(draft: $0) }
            .sheet(item: $editRoutine) { RoutineEditor(routine: $0) }
            .sheet(isPresented: $newRoutine) { RoutineEditor() }
            .sheet(isPresented: $newCardio) { CardioEditor() }
            .sheet(isPresented: $stairs) { CardioEditor(stairsOnly: true) }
            .confirmationDialog("Delete this saved training item?", isPresented: $confirmingDeletion, titleVisibility: .visible) {
                Button("Delete", role: .destructive) {
                    do { try deleteAction?() } catch { self.error = error.localizedDescription }
                    deleteAction = nil
                }
                Button("Keep", role: .cancel) { deleteAction = nil }
            } message: { Text("Only the selected item is removed. Deleting a routine does not delete its past workout snapshots.") }
            .nutritionError($error)
        }
    }
    private func start(_ routine: WorkoutRoutine? = nil) {
        do { selectedSession = try WorkoutStore(context: context).start(routine: routine); FitnessFeedback.success() }
        catch { self.error = error.localizedDescription }
    }
    @ViewBuilder private var trainingActions: some View {
        Button(hasActive ? "Resume workout" : "Start workout", systemImage: hasActive ? "play.fill" : "plus") {
            if let active = sessions.first(where: { $0.statusRaw == "active" }) { open(active) } else { start() }
        }.buttonStyle(.borderedProminent).frame(minHeight: 44)
        Button("Log cardio", systemImage: "figure.run") { newCardio = true }.buttonStyle(.bordered).frame(minHeight: 44)
    }
    @ViewBuilder private func routineActions(_ routine: WorkoutRoutine) -> some View {
        Button("Start routine") { start(routine) }.disabled(hasActive).buttonStyle(.borderedProminent).frame(minHeight: 44)
        Button("Edit") { editRoutine = routine }.buttonStyle(.bordered).frame(minHeight: 44)
        Menu("More", systemImage: "ellipsis") {
            Button("Duplicate routine", systemImage: "square.on.square") { duplicate(routine) }
        }.frame(minHeight: 44)
    }
    private func duplicate(_ routine: WorkoutRoutine) {
        do { try WorkoutStore(context: context).duplicateRoutine(routine); FitnessFeedback.success() }
        catch { self.error = error.localizedDescription }
    }
    private func open(_ session: StrengthSession) {
        do { selectedSession = try session.draft() }
        catch { self.error = error.localizedDescription }
    }
    private func remove<T: PersistentModel>(_ item: T) {
        deleteAction = { try WorkoutStore(context: context).delete(item) }
        confirmingDeletion = true
    }
}

struct CardioSummary: View {
    let draft: CardioDraft
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("\(draft.start.formatted(date: .abbreviated, time: .shortened)) · \(NutritionNumber.text(draft.durationSeconds / 60)) min")
            if let distance = draft.distanceKm { Text("Distance: \(NutritionNumber.text(distance)) km") }
            if let incline = draft.inclinePercent { Text("Incline: \(NutritionNumber.text(incline))%") }
            if let resistance = draft.resistance { Text("Level / resistance: \(NutritionNumber.text(resistance))") }
            if let floors = draft.floors { Text("Floors: \(NutritionNumber.text(floors))") }
            if let calories = draft.reportedCalories { Text("\(draft.calorieSource.rawValue): \(EnergyDisplay.kilocalories(calories)) kcal (user-entered)") }
            if !draft.notes.isEmpty { Text(draft.notes) }
        }.font(.subheadline).foregroundStyle(.secondary)
    }
}
