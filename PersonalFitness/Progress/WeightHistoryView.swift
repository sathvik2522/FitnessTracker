import SwiftUI
import SwiftData

struct WeightHistoryView: View {
    let report: ProgressReport
    @Environment(\.modelContext) private var context
    @Query private var manual: [ManualWeight]
    @State private var adding = false
    @State private var editing: WeightObservation?
    @State private var deleting: WeightObservation?
    @State private var error: String?
    init(report: ProgressReport) {
        self.report = report
        let start = report.calendar.date(byAdding: .day, value: -6, to: report.range.start)!, end = report.range.end
        _manual = Query(filter: #Predicate<ManualWeight> { $0.date >= start && $0.date < end }, sort: \ManualWeight.date, order: .reverse)
    }
    private var observations: [WeightObservation] {
        (manual.map(\.observation).filter { $0.date <= .now } + (report.healthWeights.value ?? [])).sorted { $0.date > $1.date }
    }
    var body: some View {
        List {
            Section("Weight trend · kilograms") {
                WeightHistoryChart(points: WeightTrend.points(observations, calendar: report.calendar).filter { $0.day >= report.range.start && $0.day < report.range.end }, calendar: report.calendar)
                Text("Latest measurement per source/day; dashed mean uses recorded days in the trailing seven calendar days. Sources stay separate and absent days are not filled. Weight fluctuations are not direct measurements of fat gain or loss.").font(.footnote).foregroundStyle(.secondary)
            }
            Section("Apple Health read state") {
                switch report.healthWeights {
                case .value(let weights): Text("\(weights.filter { $0.date >= report.range.start && $0.date < report.range.end }.count) readable samples in this range. This does not establish complete coverage.")
                case .unavailable: Text("No readable samples. Data may be absent, Apple Health may be disconnected, or read access may be off.")
                case .failed(let issue): Text(issue.rawValue).foregroundStyle(.red)
                }
            }
            Section("Samples in selected range") {
                if observations.filter({ $0.date >= report.range.start }).isEmpty { Text("No weights recorded in this range.").foregroundStyle(.secondary) }
                ForEach(observations.filter { $0.date >= report.range.start }, id: \.id) { sample in
                    if sample.origin == .manual {
                        Button { editing = sample } label: { row(sample) }.buttonStyle(.plain)
                            .accessibilityHint("Edit this app's manual weight entry")
                            .swipeActions { Button("Delete", role: .destructive) {
                                deleting = sample
                            } }
                    } else { row(sample) }
                }
            }
            Text("Manual entries stay on this iPhone and are never written to Apple Health. Health samples are read-only. Matching manual/Health weights are not merged or averaged together.").font(.footnote).foregroundStyle(.secondary)
        }
        .safeAreaInset(edge: .bottom) { Color.clear.frame(height: 72) }
        .fitnessScreen().navigationBarTitleDisplayMode(.inline).navigationTitle("Weight history")
        .toolbar { Button("Add manual weight", systemImage: "plus") { adding = true } }
        .confirmationDialog("Delete manual weight?", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }), titleVisibility: .visible) {
            Button("Delete weight", role: .destructive) {
                if let sample = deleting {
                    do { try ProgressStore(context: context).deleteWeight(id: sample.id) }
                    catch { self.error = error.localizedDescription }
                }
                deleting = nil
            }
        } message: { Text("This removes only the local manual record. Apple Health is unchanged.") }
        .sheet(isPresented: $adding) { ManualWeightEditor(day: report.range.days.last!) }
        .sheet(item: $editing) { ManualWeightEditor(observation: $0, day: $0.date) }
        .nutritionError($error)
    }
    private func row(_ value: WeightObservation) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("\(value.kilograms.formatted(.number.precision(.fractionLength(0...2)))) kg").font(.headline)
            Text(value.origin.rawValue)
            Text(value.date.formatted(date: .abbreviated, time: .shortened)).foregroundStyle(.secondary)
        }.frame(maxWidth: .infinity, minHeight: 44, alignment: .leading).padding(.vertical, 4)
            .contentShape(Rectangle()).accessibilityElement(children: .combine)
    }
}

struct ManualWeightEditor: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var id: UUID
    @State private var date: Date
    @State private var weight: String
    @State private var original: String?
    @State private var cancelling = false
    @State private var saved = false
    private var fingerprint: String { "\(date.timeIntervalSince1970)|\(weight)" }
    private var dirty: Bool { original != nil && original != fingerprint && !saved }
    @State private var error: String?
    init(observation: WeightObservation? = nil, day: Date) {
        _id = State(initialValue: observation?.id ?? UUID())
        _date = State(initialValue: observation?.date ?? (try? DiaryDate.timestamp(for: day)) ?? day)
        _weight = State(initialValue: observation.map { NutritionNumber.text($0.kilograms) } ?? "")
    }
    var body: some View {
        NavigationStack {
            Form {
                Section("Manual · stored only in this app") {
                    DatePicker("Measured at", selection: $date, in: ...Date.now)
                    NutritionNumericField(title: "Body weight (kg)", text: $weight)
                    Text("This does not change Apple Health. Editing preserves the date unless you explicitly change it.").font(.footnote).foregroundStyle(.secondary)
                }
            }.fitnessScreen().navigationBarTitleDisplayMode(.inline).navigationTitle("Manual weight")
                .workoutKeyboardToolbar()
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancel") { if dirty { cancelling = true } else { dismiss() } } }
                    ToolbarItem(placement: .confirmationAction) { Button("Save") {
                        do {
                            guard !saved else { return }
                            try ProgressStore(context: context).saveWeight(WeightObservation(id: id, date: date,
                                kilograms: NutritionNumber.parse(weight), origin: .manual))
                            saved = true
                            dismiss()
                        } catch { self.error = error.localizedDescription }
                    } }
                }
                .onAppear { if original == nil { original = fingerprint } }
                .confirmDiscardChanges(dirty: dirty, requested: $cancelling) { dismiss() }
                .nutritionError($error)
        }
    }
}
