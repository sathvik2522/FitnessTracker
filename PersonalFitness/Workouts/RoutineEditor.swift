import SwiftUI
import SwiftData

struct RoutineEditor: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var id: UUID
    private let unreadable: Bool
    @State private var name: String
    @State private var exercises: [SessionExercise]
    @State private var adding = false
    @State private var saved = false
    @State private var error: String?
    @State private var original: String?
    @State private var cancelling = false
    private var fingerprint: String { name + draftFingerprint(exercises) }
    private var dirty: Bool { original != nil && original != fingerprint }

    init(routine: WorkoutRoutine? = nil) {
        _id = State(initialValue: routine?.id ?? UUID())
        let items = try? routine?.exercises()
        unreadable = routine != nil && items == nil
        _name = State(initialValue: routine?.name ?? "")
        _exercises = State(initialValue: items ?? [])
    }
    var body: some View {
        NavigationStack {
            List {
                Section("Routine name") { TextField("Routine name", text: $name) }
                Section("Exercises · drag in Edit mode") {
                    ForEach($exercises) { $item in
                        VStack(alignment: .leading, spacing: 8) {
                            Text(item.exercise.name).font(.headline)
                            Stepper("\(item.sets.count) starting sets", value: Binding(
                                get: { item.sets.count }, set: { count in
                                    if count > item.sets.count { item.sets.append(TrainingSet()) }
                                    else { item.sets.removeLast() }
                                }), in: 1...20)
                            ForEach($item.sets) { $set in
                                Stepper("Target reps: \(set.reps)", value: $set.reps, in: 1...9999)
                                HStack {
                                    Text("Target external kg")
                                    TextField("Target weight (kg)", value: $set.weightKg, format: .number)
                                        .keyboardType(.decimalPad).multilineTextAlignment(.trailing)
                                        .accessibilityLabel("Target weight (kg)")
                                }
                            }
                            TextField("Routine exercise notes", text: $item.exercise.notes, axis: .vertical)
                        }.padding(.vertical, 4)
                    }
                    .onDelete { exercises.remove(atOffsets: $0) }
                    .onMove { exercises.move(fromOffsets: $0, toOffset: $1) }
                    Button("Add exercise", systemImage: "plus") { adding = true }.frame(minHeight: 44)
                }
                Text("Routines keep exercise snapshots. Remove and re-add an exercise to adopt library changes. Starting sets are editable in the session.").font(.footnote).foregroundStyle(.secondary)
                if unreadable { Text("This routine could not be read. It has not been changed.") }
            }
            .fitnessScreen().navigationBarTitleDisplayMode(.inline).navigationTitle("Workout routine")
            .workoutKeyboardToolbar()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { if dirty { cancelling = true } else { dismiss() } } }
                ToolbarItem(placement: .primaryAction) { EditButton() }
                ToolbarItem(placement: .confirmationAction) { Button("Save") {
                    do { guard !saved else { return }; try WorkoutStore(context: context).saveRoutine(id: id, name: name, exercises: exercises); saved = true; dismiss() }
                    catch { self.error = error.localizedDescription }
                }.disabled(unreadable || saved) }
            }
            .sheet(isPresented: $adding) { ExercisePicker { exercises.append(SessionExercise(exercise: $0)) } }
            .onAppear { if original == nil { original = fingerprint } }
            .confirmDiscardChanges(dirty: dirty, requested: $cancelling) { dismiss() }
            .nutritionError($error)
        }
    }
}
