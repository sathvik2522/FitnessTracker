import SwiftUI
import SwiftData

struct SleepOverview: View {
    let day: Date
    @Environment(\.scenePhase) private var scenePhase
    @State private var model = SleepModel()
    @State private var history = false
    @Query private var sessions: [StrengthSession]
    @Query private var cardio: [CardioSession]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeading(title: "Sleep & training context", subtitle: "Sleep ending on the selected day · local noon-to-noon window")
            if !model.available {
                Text("Apple Health sleep is unavailable on this device.")
            } else if !model.requested {
                Text("Optional: read sleep from Apple Health. Missing samples never mean zero sleep.")
                Button("Enable sleep insights") { Task { await model.connect(day: day) } }
                    .buttonStyle(.bordered).frame(minHeight: 44).disabled(model.connecting)
            } else {
                if model.loading { LoadingState(message: "Reading recent sleep") }
                if let night = model.nights.first { nightSummary(night) }
                if let observation = model.observation { Text(observation).font(.subheadline) }
                DisclosureGroup("Recent sleep history", isExpanded: $history) {
                    ForEach(model.nights) { night in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(night.day.formatted(date: .abbreviated, time: .omitted)).font(.headline)
                            nightSummary(night)
                        }.padding(.vertical, 6)
                    }
                }
                Button("Refresh sleep") { Task { await model.load(day: day) } }.frame(minHeight: 44)
                Button("Review sleep access") { Task { await model.connect(day: day) } }.frame(minHeight: 44).disabled(model.connecting)
            }
            if model.connecting { LoadingState(message: "Waiting for sleep access request") }
            if let error = model.error { ErrorMessage(title: "Sleep unavailable", message: error) }
            trainingContext
            Text("Recorded sleep is an estimate and may be incomplete or hidden by permissions. In-bed time is separate from sleep. Overlapping asleep stages/sources are counted once. This is descriptive context, not a recovery score or medical readiness assessment.")
                .font(.footnote).foregroundStyle(.primary)
        }
        .task(id: day) { await model.load(day: day) }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.significantTimeChangeNotification)) { _ in
            Task { await model.load(day: day) }
        }
        .onChange(of: scenePhase) { _, phase in if phase == .active { Task { await model.load(day: day) } } }
    }

    @ViewBuilder private func nightSummary(_ night: SleepNight) -> some View {
        Text("Time asleep: \(duration(night.summary.asleepSeconds))").font(.headline)
        Text("\(night.window.start.formatted(date: .abbreviated, time: .shortened)) – \(night.window.end.formatted(date: .abbreviated, time: .shortened)) · \(TimeZone.current.identifier)")
            .font(.caption).foregroundStyle(.secondary)
        if !night.summary.sources.isEmpty {
            Text("Sources: " + night.summary.sources.joined(separator: ", ")).font(.caption)
        }
        Text("Time in bed: \(duration(night.summary.inBedSeconds))")
        if night.window.isPartial { Text("This sleep window is still open; more data may arrive.").font(.caption) }
        if night.summary.conflictingStates || night.summary.invalidSamples {
            Text("Sleep records conflict or contain invalid intervals. Duration is provisional; comparative insights are withheld.").font(.caption)
        }
    }
    private func duration(_ seconds: Double?) -> String {
        guard let seconds else { return "Unavailable" }
        let minutes = Int(seconds / 60)
        return "\(minutes / 60) h \(minutes % 60) min"
    }
    private var trainingContext: some View {
        let dates = sessions.filter { $0.statusRaw == "completed" }.map(\.start) + cardio.map(\.start)
        let counts = TrainingFrequency(dates: dates, day: day, calendar: .current)
        return Text("Completed local training logs: \(counts.recent) in the last 7 days; \(counts.previous) in the preceding 7. These are manual-log counts, not proof of total activity. Health workout records and estimated energy remain separate on Dashboard.")
            .font(.subheadline)
    }
}
