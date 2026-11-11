import SwiftUI
import SwiftData
import Charts

struct DailySleepCard: View {
    let model: SleepModel
    let day: Date
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Sleep", systemImage: "moon.zzz.fill").font(.headline).foregroundStyle(FitnessTheme.sleep)
                Spacer()
                NavigationLink("Details") { ScrollView { SleepOverview(day: day).padding() }.navigationTitle("Sleep & context").fitnessScreen() }
            }
            if model.loading || model.connecting { LoadingState(message: "Reading sleep") }
            if let issue = model.error { ErrorMessage(title: "Sleep unavailable", message: issue) }
            if !model.available { Text("Apple Health sleep is unavailable on this device.") }
            else if !model.requested {
                Text("Optional recorded sleep. Recovery details explain duration targets and other eligible signals.").font(.subheadline)
                Button("Enable sleep insights") { Task { await model.connect(day: day) } }
                    .buttonStyle(.bordered).frame(minHeight: 44).disabled(model.connecting)
            } else if let night = model.nights.first {
                Text(night.summary.asleepSeconds.map { "\(Int($0 / 3600)) h \(Int($0 / 60) % 60) min" } ?? "Unavailable")
                    .font(.system(.title, design: .rounded).bold()).monospacedDigit()
                if let first = night.summary.asleepIntervals.first, let last = night.summary.asleepIntervals.last {
                    Text("First recorded asleep \(first.start.formatted(date: .omitted, time: .shortened)) · Last asleep end \(last.end.formatted(date: .omitted, time: .shortened))").font(.caption)
                    Chart(Array(night.summary.asleepIntervals.enumerated()), id: \.offset) { _, interval in
                        RectangleMark(xStart: .value("Start", interval.start), xEnd: .value("End", interval.end), y: .value("State", "Asleep"))
                            .foregroundStyle(FitnessTheme.sleep.gradient)
                            .accessibilityLabel("Recorded asleep interval")
                            .accessibilityValue("\(interval.start.formatted(date: .abbreviated, time: .shortened)) to \(interval.end.formatted(date: .abbreviated, time: .shortened))")
                    }.chartXAxis { AxisMarks(values: .automatic(desiredCount: 3)) }.chartYAxis(.hidden)
                        .frame(height: 75)
                    Text("Union of recorded asleep intervals; no stages or awake gaps are inferred.").font(.caption).foregroundStyle(.secondary)
                }
                Text("Query: \(night.window.start.formatted(date: .abbreviated, time: .shortened)) – \(night.window.end.formatted(date: .abbreviated, time: .shortened)) · \(TimeZone.current.identifier)")
                    .font(.caption).accessibilityIdentifier("sleep.window")
                if !night.summary.sources.isEmpty { Text("Sources: " + night.summary.sources.joined(separator: ", ")).font(.caption) }
                if night.window.isPartial { Text("Sleep window still open; more data may arrive.").font(.caption) }
                if night.summary.conflictingStates || night.summary.invalidSamples {
                    Text("Conflicting or invalid records: duration is provisional, comparisons withheld.").font(.caption)
                }
                if let observation = model.observation { Text(observation).font(.subheadline) }
            } else { Text("No readable sleep samples. Access may be off or data may arrive later.") }
        }.fitnessCard()
    }
}

struct RecentTrainingCard: View {
    let day: Date
    @Query(sort: \StrengthSession.start, order: .reverse) private var strength: [StrengthSession]
    @Query(sort: \CardioSession.start, order: .reverse) private var cardio: [CardioSession]
    private var bounds: DateInterval? {
        guard let end = Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: day)),
              let start = Calendar.current.date(byAdding: .day, value: -7, to: end) else { return nil }
        return DateInterval(start: start, end: end)
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Recent training", systemImage: "dumbbell.fill").font(.headline)
                Spacer()
                Button("View all") { NotificationCenter.default.post(name: .openWorkoutLog, object: nil) }.frame(minHeight: 44)
            }
            Text("Local logs · seven days ending on the selected date").font(.caption).foregroundStyle(.secondary)
            if let bounds {
                let sessions = strength.filter { $0.start >= bounds.start && $0.start < bounds.end }
                let sessionsCardio = cardio.filter { $0.start >= bounds.start && $0.start < bounds.end }
                if sessions.isEmpty && sessionsCardio.isEmpty { Text("No local training recorded in this window.").font(.subheadline) }
                ForEach(Array(sessions.prefix(3))) { item in
                    LabeledContent(item.name, value: item.statusRaw.capitalized)
                    Text(item.start.formatted(date: .abbreviated, time: .shortened)).font(.caption)
                }
                ForEach(Array(sessionsCardio.prefix(3))) { item in
                    Text(item.activityRaw).font(.subheadline.bold())
                    if let draft = try? item.draft() { CardioSummary(draft: draft) }
                    else { Text("Saved details unavailable") }
                }
            } else { Text("Date window unavailable") }
            Text("Manual estimates remain separate from Apple Health energy.").font(.caption).foregroundStyle(.secondary)
        }.fitnessCard()
    }
}
