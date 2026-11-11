import SwiftUI
import SwiftData

struct ExerciseLibraryView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \ExerciseRecord.name) private var exercises: [ExerciseRecord]
    @State private var search = ""
    @State private var visibleLimit = 50
    private var matchingExercises: [ExerciseRecord] { exercises.filter { $0.matchesLibrary(search) } }
    @State private var creating = false
    @State private var deleting: ExerciseRecord?
    @State private var error: String?
    var body: some View {
        List {
            if !exercises.contains(where: { $0.libraryVisible }) {
                EmptyState(title: "Your exercise library", message: "Add exercises with their names, bodyweight setting and optional training notes.", symbol: "dumbbell")
            }
            if !exercises.contains(where: { $0.libraryVisible }) { Button("Add starter exercises") { addStarters() }.frame(minHeight: 44) }
            if !search.isEmpty && !exercises.contains(where: { $0.matchesLibrary(search) }) { ContentUnavailableView.search(text: search) }
            ForEach(Array(matchingExercises.prefix(visibleLimit))) { exercise in
                NavigationLink { ExerciseDetailView(record: exercise) } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(exercise.name)
                        Text(exercise.librarySourceLabel).font(.caption).foregroundStyle(.secondary)
                    }.padding(.vertical, 8)
                }
                    .swipeActions {
                        Button("Delete", role: .destructive) {
                            deleting = exercise
                        }
                    }
            }
            if matchingExercises.count > visibleLimit { Button("Show more exercises") { visibleLimit += 50 }.frame(minHeight: 44) }
            Text("Deleting or editing library exercises never rewrites routine or session snapshots.").font(.footnote).foregroundStyle(.secondary)
        }
        .fitnessScreen().navigationBarTitleDisplayMode(.inline).navigationTitle("Exercises")
        .searchable(text: $search, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search exercises")
        .onChange(of: search) { _, _ in visibleLimit = 50 }
        .toolbar { Button("New exercise", systemImage: "plus") { creating = true } }
        .sheet(isPresented: $creating) { ExerciseEditor() }
        .confirmationDialog("Delete exercise?", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } })) {
            Button("Delete exercise", role: .destructive) {
                if let item = deleting {
                    do { try WorkoutStore(context: context).delete(item) }
                    catch { self.error = error.localizedDescription }
                }
                deleting = nil
            }
        } message: { Text("Existing routine and workout snapshots remain unchanged.") }
        .nutritionError($error)
    }
    private func addStarters() {
        do { try WorkoutStore(context: context).addStarterExercises() }
        catch { self.error = error.localizedDescription }
    }
}

struct ExerciseEditor: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var exercise: ExerciseSnapshot
    @State private var error: String?
    private let editing: Bool
    @State private var original: ExerciseSnapshot
    private let onSaved: ((ExerciseSnapshot) -> Void)?
    @State private var cancelling = false
    @State private var saved = false
    init(exercise: ExerciseSnapshot? = nil, onSaved: ((ExerciseSnapshot) -> Void)? = nil) {
        editing = exercise != nil
        let initial = exercise ?? ExerciseSnapshot(name: "")
        _original = State(initialValue: initial)
        self.onSaved = onSaved
        _exercise = State(initialValue: initial)
    }
    var body: some View {
        NavigationStack {
            Form {
                Section("Exercise") {
                    TextField("Exercise name", text: $exercise.name)
                    Toggle("Bodyweight exercise", isOn: $exercise.bodyweight)
                    TextField("Equipment (optional)", text: Binding(get: { exercise.equipment ?? "" }, set: { exercise.equipment = $0 }))
                    TextField("Movement type (optional)", text: Binding(get: { exercise.movementType ?? "" }, set: { exercise.movementType = $0 }))
                    TextField("Category (optional)", text: $exercise.category)
                    TextField("Muscle group (optional)", text: $exercise.muscleGroup)
                    TextField("Notes (optional)", text: $exercise.notes, axis: .vertical)
                }
                Text("Weights are logged in kilograms. For bodyweight exercises, enter only extra external load; your body mass is not inferred.").font(.footnote).foregroundStyle(.secondary)
            }
            .fitnessScreen().navigationBarTitleDisplayMode(.inline).navigationTitle(editing ? "Edit exercise" : "New exercise")
            .workoutKeyboardToolbar()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { if exercise != original { cancelling = true } else { dismiss() } } }
                ToolbarItem(placement: .confirmationAction) { Button("Save") {
                    do { guard !saved else { return }; try WorkoutStore(context: context).saveExercise(exercise); saved = true; onSaved?(exercise); dismiss() }
                    catch { self.error = error.localizedDescription }
                } }
            }
            .confirmDiscardChanges(dirty: exercise != original && !saved, requested: $cancelling) { dismiss() }
            .nutritionError($error)
        }
    }
}

struct ExercisePicker: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @State private var pending: ExerciseSnapshot?
    @Query(sort: \ExerciseRecord.name) private var exercises: [ExerciseRecord]
    @State private var search = ""
    @State private var visibleLimit = 50
    private var matchingExercises: [ExerciseRecord] { exercises.filter { $0.matchesLibrary(search) } }
    @State private var creating = false
    @State private var error: String?
    let choose: (ExerciseSnapshot) -> Void
    var body: some View {
        NavigationStack {
            List {
                if !exercises.contains(where: { $0.libraryVisible }) {
                    Text("Create your own exercise or install editable starter exercises.")
                    Button("Add starter exercises") {
                        do { try WorkoutStore(context: context).addStarterExercises() }
                        catch { self.error = error.localizedDescription }
                    }
                }
                if !search.isEmpty && !exercises.contains(where: { $0.matchesLibrary(search) }) { ContentUnavailableView.search(text: search) }
                ForEach(Array(matchingExercises.prefix(visibleLimit))) { exercise in
                    Button {
                        do { choose(try exercise.snapshot()); dismiss() }
                        catch { self.error = error.localizedDescription }
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(exercise.name).font(.body.weight(.medium))
                            if let details = try? exercise.snapshot() {
                                let metadata = [details.muscleGroup, details.equipment ?? ""].filter { !$0.isEmpty }.joined(separator: " · ")
                                if !metadata.isEmpty { Text(metadata).font(.caption).foregroundStyle(.secondary) }
                            }
                        }.frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                    }
                    .accessibilityLabel(exercise.name)
                    .accessibilityHint("Selects this exercise")
                }
                if matchingExercises.count > visibleLimit { Button("Show more exercises") { visibleLimit += 50 }.frame(minHeight: 44) }
            }
            .searchable(text: $search, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search exercises")
        .onChange(of: search) { _, _ in visibleLimit = 50 }
            .fitnessScreen().navigationBarTitleDisplayMode(.inline).navigationTitle("Add exercise")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("New exercise") { creating = true } }
            }
            .sheet(isPresented: $creating, onDismiss: {
                if let pending { choose(pending); self.pending = nil; dismiss() }
            }) { ExerciseEditor { pending = $0 } }
            .nutritionError($error)
        }
    }
}

private struct ExerciseDetailView: View {
    let record: ExerciseRecord
    @Query(sort: \StrengthSession.start, order: .reverse) private var sessions: [StrengthSession]
    @State private var editing = false
    var body: some View {
        List {
            if let exercise = try? record.snapshot() {
                Section("Exercise details") {
                    if exercise.bodyweight { Text("Bodyweight + optional external load") }
                    if let equipment = exercise.equipment, !equipment.isEmpty { Text("Equipment: \(equipment)") }
                    if let movement = exercise.movementType, !movement.isEmpty { Text("Movement: \(movement)") }
                    if !exercise.category.isEmpty { Text(exercise.category) }
                    if !exercise.muscleGroup.isEmpty { Text(exercise.muscleGroup) }
                    if !exercise.notes.isEmpty { Text(exercise.notes) }
                    if let muscles = exercise.secondaryMuscles, !muscles.isEmpty { Text("Secondary muscles: " + muscles.joined(separator: ", ")) }
                }
                if let instructions = exercise.instructions, !instructions.isEmpty {
                    Section("Source instructions") {
                        ForEach(Array(instructions.enumerated()), id: \.offset) { index, text in Text("\(index + 1). \(text)") }
                    }
                }
                if let origin = exercise.catalog {
                    Section("Catalog source") {
                        Text(origin.attribution)
                        Text("\(origin.license) · \(origin.recordID) · \(origin.release)").font(.caption)
                        Text(origin.quality).font(.footnote)
                        if origin.userModified { Text("Personally edited. Source text and personal notes remain separate.") }
                    }
                }
                let history = WorkoutProgression.history(exerciseID: exercise.id, sessions: sessions.compactMap { try? $0.draft() })
                Section("Progression · completed sets only") {
                    if history.isEmpty { Text("No completed sets yet.").foregroundStyle(.secondary) }
                    ForEach(history) { performance in
                        VStack(alignment: .leading, spacing: 8) {
                            Text(performance.date.formatted(date: .abbreviated, time: .shortened)).font(.headline)
                            Text("\(performance.sets.count) sets · \(performance.totalReps) reps · best load \(NutritionNumber.text(performance.bestWeightKg)) kg")
                            Text("External volume: \(NutritionNumber.text(performance.externalVolumeKg)) kg·reps").foregroundStyle(.secondary)
                            Text(performance.sets.map { "\($0.reps) × \(NutritionNumber.text($0.weightKg)) kg" }.joined(separator: " · ")).font(.subheadline)
                        }.padding(.vertical, 4)
                    }
                }
                Text("Volume counts external load × reps, excluding body mass. Different exercises or equipment are not directly comparable.").font(.footnote).foregroundStyle(.secondary)
            } else { Text("This exercise definition could not be read.") }
        }
        .fitnessScreen().navigationBarTitleDisplayMode(.inline).navigationTitle(record.name)
        .toolbar { Button("Edit exercise") { editing = true } }
        .sheet(isPresented: $editing) {
            if let exercise = try? record.snapshot() { ExerciseEditor(exercise: exercise) }
        }
    }
}
