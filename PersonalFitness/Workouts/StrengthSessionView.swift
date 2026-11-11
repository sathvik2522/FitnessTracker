import SwiftUI
import SwiftData

struct StrengthSessionView: View {
    @Environment(GoalPreferences.self) private var preferences
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query private var sessions: [StrengthSession]
    @State private var model: WorkoutSessionModel
    @State private var adding = false
    @State private var managing = false
    @State private var details = false
    @State private var cancelling = false
    @State private var finished = false
    @State private var closing = false
    @State private var timerExpanded = false
    init(draft: StrengthDraft) { _model = State(initialValue: WorkoutSessionModel(draft: draft)) }
    private var active: Bool { model.draft.status == .active }

    var body: some View {
        NavigationStack {
            List {
                Section {
                  VStack(alignment: .leading, spacing: 10) {
                    Text(active ? "In progress · valid edits save immediately" : "\(model.draft.status.rawValue.capitalized) · valid edits save immediately")
                        .font(.headline).accessibilityIdentifier("workout.status")
                    Text(model.draft.start.formatted(date: .abbreviated, time: .shortened))
                    let allSets = model.draft.exercises.flatMap(\.sets)
                    let completedSets = allSets.filter(\.completed).count
                    if !allSets.isEmpty {
                        ProgressView(value: Double(completedSets), total: Double(allSets.count)) {
                            Text("\(completedSets) of \(allSets.count) sets complete").font(.subheadline)
                        }.tint(FitnessTheme.blue).accessibilityIdentifier("workout.progress")
                    } else {
                        Text("Add an exercise to begin.").font(.subheadline).foregroundStyle(.secondary)
                    }
                    Button("Edit name and dates") { details = true }.accessibilityHint("Also edit optional session RPE")
                    if let rpe = model.draft.sessionRPE { Text("Session RPE: \(NutritionNumber.text(rpe)) / 10") }
                    if !model.invalidInputs.isEmpty {
                        Text("Fix invalid set values before finishing. Unsaved text is not stored.").foregroundStyle(.red)
                    }
                  }.padding(.vertical, 4)
                }.listRowBackground(FitnessTheme.card)
                if active { restTimer }
                ForEach(model.draft.exercises) { item in
                    exerciseSection(item)
                }.listRowBackground(FitnessTheme.card)
                Section {
                    Button("Add exercise", systemImage: "plus") { adding = true }.frame(minHeight: 44)
                    if active {
                        Button("Finish workout", systemImage: "checkmark.circle.fill") {
                            if model.finish(context: context) { FitnessFeedback.success(); finished = true }
                        }.frame(minHeight: 44).disabled(!model.invalidInputs.isEmpty)
                        Button("Cancel workout", role: .destructive) { cancelling = true }.frame(minHeight: 44)
                    }
                }.listRowBackground(FitnessTheme.card)
            }
            .scrollDismissesKeyboard(.interactively)
            .fitnessScreen().navigationBarTitleDisplayMode(.inline).navigationTitle(model.draft.name)
            .workoutKeyboardToolbar()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(active ? "Close & keep active" : "Done") { if model.invalidInputs.isEmpty { dismiss() } else { closing = true } } }
                ToolbarItem(placement: .primaryAction) { Button("Exercises") { managing = true } }
            }
            .sheet(isPresented: $managing) {
                SessionExerciseManager(exercises: model.draft.exercises) { items in
                    if model.update(context: context, { $0.exercises = items }) {
                        model.invalidInputs.formIntersection(Set(items.flatMap(\.sets).map { $0.id.uuidString }))
                        return nil
                    }
                    let issue = model.error ?? "Could not save exercise order."
                    model.error = nil
                    return issue
                }
            }
            .sheet(isPresented: $adding) {
                ExercisePicker { exercise in _ = model.update(context: context) { $0.exercises.append(SessionExercise(exercise: exercise)) } }
            }
            .sheet(isPresented: $details) {
                SessionDetailsEditor(draft: model.draft) { updated in
                    if model.update(context: context, { $0 = updated }) { return nil }
                    let issue = model.error ?? "Could not save session details."
                    model.error = nil
                    return issue
                }
            }
            .confirmationDialog("Cancel this workout?", isPresented: $cancelling, titleVisibility: .visible) {
                Button("Cancel workout", role: .destructive) { if model.cancel(context: context) { dismiss() } }
            } message: { Text("The draft remains in history as cancelled and is excluded from progression.") }
            .interactiveDismissDisabled(!model.invalidInputs.isEmpty)
            .confirmationDialog("Discard invalid set text?", isPresented: $closing, titleVisibility: .visible) {
                Button("Close & keep saved sets", role: .destructive) { dismiss() }
                Button("Keep editing", role: .cancel) { }
            } message: { Text("All valid sets are already saved. Invalid, unsaved field text will be lost.") }
            .alert("Workout saved", isPresented: $finished) {
                Button("Rate effort (optional)") { details = true }
                Button("Done") { dismiss() }
            } message: {
                let sets = model.draft.exercises.flatMap(\.sets).filter(\.completed)
                Text("\(model.draft.exercises.count) exercises · \(sets.count) completed sets · \(sets.reduce(0) { $0 + $1.reps }) reps. Your workout is available in history.")
            }
            .nutritionError($model.error)
        }
    }

    private var restTimer: some View {
        Section {
            DisclosureGroup(isExpanded: $timerExpanded) {
                ViewThatFits(in: .horizontal) {
                    HStack { timerButtons }
                    VStack(alignment: .leading) { timerButtons }
                }
                Text("No background alert is scheduled.").font(.footnote).foregroundStyle(.secondary)
            } label: {
                HStack {
                    Label("Rest timer", systemImage: "timer").font(.headline)
                    Spacer()
                    TimelineView(.periodic(from: .now, by: 1)) { time in
                        let remaining = WorkoutProgression.restRemaining(until: model.draft.restEndsAt, now: time.date)
                        Text(remaining > 0 ? "\(remaining / 60):\(String(format: "%02d", remaining % 60))" : "Ready")
                            .font(.headline.monospacedDigit()).accessibilityLabel("Rest timer, \(remaining) seconds remaining")
                    }
                }.frame(minHeight: 44)
            }
        }.listRowBackground(FitnessTheme.card)
    }
    @ViewBuilder private var timerButtons: some View {
        ForEach(restChoices, id: \.self) { seconds in
            Button(seconds == preferences.restDurationSeconds ? "\(seconds) s preferred" : "\(seconds) s") {
                if model.update(context: context, { $0.restEndsAt = .now.addingTimeInterval(Double(seconds)) }) { FitnessFeedback.selection() }
            }
            .buttonStyle(.bordered).frame(minHeight: 44).accessibilityLabel("Start \(seconds) second rest")
        }
        Button("Stop") { _ = model.update(context: context) { $0.restEndsAt = nil } }.buttonStyle(.bordered).frame(minHeight: 44)
    }
    private var restChoices: [Int] {
        [preferences.restDurationSeconds, 60, 120].reduce(into: []) { choices, seconds in
            if !choices.contains(seconds) { choices.append(seconds) }
        }
    }

    private func exerciseSection(_ item: SessionExercise) -> some View {
        Section {
            if !item.exercise.notes.isEmpty { Text(item.exercise.notes).font(.subheadline).foregroundStyle(.secondary) }
            let last = WorkoutProgression.history(exerciseID: item.exercise.id,
                sessions: sessions.filter { $0.id != model.draft.id }.compactMap { try? $0.draft() }, before: model.draft.start).first
            if let last {
                Text("Last completed \(last.date.formatted(date: .abbreviated, time: .omitted)): " + last.sets.map { "\($0.reps) × \(NutritionNumber.text($0.weightKg)) kg" }.joined(separator: " · "))
                    .font(.subheadline).foregroundStyle(.secondary)
            } else { Text("No earlier completed sets for this exercise.").font(.subheadline).foregroundStyle(.secondary) }
            ForEach(Array(item.sets.enumerated()), id: \.element.id) { index, set in
                TrainingSetRow(set: set, number: index + 1, bodyweight: item.exercise.bodyweight,
                    invalid: { invalid in
                        if invalid { model.invalidInputs.insert(set.id.uuidString) }
                        else { model.invalidInputs.remove(set.id.uuidString) }
                    }) { updated in
                        model.update(context: context) { draft in
                            guard let exerciseIndex = draft.exercises.firstIndex(where: { $0.id == item.id }),
                                  let setIndex = draft.exercises[exerciseIndex].sets.firstIndex(where: { $0.id == set.id }) else { return }
                            draft.exercises[exerciseIndex].sets[setIndex] = updated
                        }
                    }
                    .swipeActions(allowsFullSwipe: false) { Button("Delete set", role: .destructive) {
                        if model.update(context: context, { draft in
                            guard let i = draft.exercises.firstIndex(where: { $0.id == item.id }) else { return }
                            draft.exercises[i].sets.removeAll { $0.id == set.id }
                        }) { model.invalidInputs.remove(set.id.uuidString) }
                    } }
            }
            Button("Add set", systemImage: "plus") {
                _ = model.update(context: context) { draft in
                    guard let i = draft.exercises.firstIndex(where: { $0.id == item.id }) else { return }
                    let last = draft.exercises[i].sets.last
                    draft.exercises[i].sets.append(TrainingSet(reps: last?.reps ?? 8, weightKg: last?.weightKg ?? 0))
                }
            }.frame(minHeight: 44).accessibilityLabel("Add set to \(item.exercise.name)")
        } header: {
            Text(item.exercise.name + (item.exercise.bodyweight ? " · bodyweight" : ""))
                .font(.headline).foregroundStyle(.primary).textCase(nil)
        }.listRowBackground(FitnessTheme.card)
    }
}

private struct TrainingSetRow: View {
    let set: TrainingSet
    let number: Int
    let bodyweight: Bool
    let invalid: (Bool) -> Void
    let save: (TrainingSet) -> Bool
    @State private var reps: String
    @State private var weight: String
    @State private var completed: Bool
    @State private var issue: String?
    @Environment(\.dynamicTypeSize) private var dynamicType
    init(set: TrainingSet, number: Int, bodyweight: Bool, invalid: @escaping (Bool) -> Void, save: @escaping (TrainingSet) -> Bool) {
        self.set = set; self.number = number; self.bodyweight = bodyweight; self.invalid = invalid; self.save = save
        _reps = State(initialValue: String(set.reps))
        _weight = State(initialValue: NutritionNumber.text(set.weightKg))
        _completed = State(initialValue: set.completed)
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Set \(number)").font(.headline)
                Spacer()
                Toggle("Set \(number) completed", isOn: $completed)
                    .labelsHidden().accessibilityLabel("Set \(number) completed").frame(minHeight: 44)
            }
            if dynamicType.isAccessibilitySize {
                NutritionNumericField(title: "Reps", text: $reps)
                NutritionNumericField(title: bodyweight ? "Extra weight (kg)" : "Weight (kg)", text: $weight)
            } else {
                HStack(alignment: .top, spacing: 12) {
                    setField("Reps", text: $reps)
                    setField(bodyweight ? "Extra weight (kg)" : "Weight (kg)", text: $weight)
                }
            }
            if let issue { Text(issue).font(.footnote).foregroundStyle(.red) }
        }
        .padding(.vertical, 8)
        .onChange(of: reps) { _, _ in persist() }
        .onChange(of: weight) { _, _ in persist() }
        .onChange(of: completed) { _, _ in persist() }
    }
    private func setField(_ title: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption).foregroundStyle(.secondary).accessibilityHidden(true)
            TextField(title, text: text, prompt: Text("Required"))
                .keyboardType(.decimalPad).monospacedDigit()
                .padding(.horizontal, 10).frame(minHeight: 44)
                .background(FitnessTheme.raised, in: RoundedRectangle(cornerRadius: 10))
                .accessibilityLabel(title)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
    private func persist() {
        do {
            let repsNumber = try NutritionNumber.parse(reps)
            guard (0...9999).contains(repsNumber), repsNumber.rounded() == repsNumber else { throw TrainingError.sets }
            var updated = set
            updated.reps = Int(repsNumber)
            updated.weightKg = try NutritionNumber.parse(weight)
            updated.completed = completed
            try updated.validate()
            guard save(updated) else { invalid(true); return }
            issue = nil
            invalid(false)
        } catch { issue = error.localizedDescription; invalid(true) }
    }
}

private struct SessionDetailsEditor: View {
    @Environment(\.dismiss) private var dismiss
    @State var draft: StrengthDraft
    let save: (StrengthDraft) -> String?
    @State private var error: String?
    @State private var original: String?
    @State private var cancelling = false
    private var fingerprint: String { draftFingerprint(draft) }
    private var dirty: Bool { original != nil && original != fingerprint }
    var body: some View {
        NavigationStack {
            Form {
                TextField("Workout name", text: $draft.name)
                DatePicker("Started at", selection: $draft.start, in: ...Date.now)
                if draft.end != nil {
                    DatePicker("Finished at", selection: Binding(get: { draft.end! }, set: { draft.end = $0 }), in: ...Date.now)
                }
                Text("Editing details preserves the session's status and exercise snapshots.").font(.footnote)
                Section("Session effort") { SessionRPEField(value: $draft.sessionRPE) }
            }
            .fitnessScreen().navigationBarTitleDisplayMode(.inline).navigationTitle("Session details")
            .onAppear { if original == nil { original = fingerprint } }
            .confirmDiscardChanges(dirty: dirty, requested: $cancelling) { dismiss() }
            .nutritionError($error)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { if dirty { cancelling = true } else { dismiss() } } }
                ToolbarItem(placement: .confirmationAction) { Button("Save") {
                    if let issue = save(draft) { error = issue } else { dismiss() }
                } }
            }
        }
    }
}


private struct SessionExerciseManager: View {
    @Environment(\.dismiss) private var dismiss
    @State var exercises: [SessionExercise]
    let save: ([SessionExercise]) -> String?
    @State private var error: String?
    @State private var original: String?
    @State private var cancelling = false
    private var fingerprint: String { draftFingerprint(exercises) }
    private var dirty: Bool { original != nil && original != fingerprint }
    var body: some View {
        NavigationStack {
            List {
                Section("Drag to reorder; minus to remove") {
                    ForEach(exercises) { item in
                        Text(item.exercise.name).frame(minHeight: 44)
                    }
                    .onMove { exercises.move(fromOffsets: $0, toOffset: $1) }
                    .onDelete { exercises.remove(atOffsets: $0) }
                }
            }
            .environment(\.editMode, .constant(.active))
            .fitnessScreen().navigationBarTitleDisplayMode(.inline).navigationTitle("Session exercises")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { if dirty { cancelling = true } else { dismiss() } } }
                ToolbarItem(placement: .confirmationAction) { Button("Save") {
                    if let issue = save(exercises) { error = issue } else { dismiss() }
                } }
            }
            .onAppear { if original == nil { original = fingerprint } }
            .confirmDiscardChanges(dirty: dirty, requested: $cancelling) { dismiss() }
            .nutritionError($error)
        }
    }
}
