import SwiftUI
import WidgetKit

private let appGroup = "group.com.gbssathvik.PersonalFitness"
private let snapshotKey = "widgetSnapshot.v1"

private enum DataState: String, Codable { case current, partial, unavailable }
private enum PrivacyMode: String, Codable { case showValues, hideValues }
private struct Metric: Codable { let score: Double?; let state: DataState; let sourceLabel: String }
private struct Nutrition: Codable { let consumedCalories: Double?; let calorieGoal: Double?; let state: DataState }
private struct Workout: Codable { let name: String; let completedSets: Int; let plannedSets: Int?; let startedAt: Date }
private struct Snapshot: Codable {
    let schemaVersion: Int; let generatedAt: Date; let localDayStart: Date; let timeZoneIdentifier: String
    let privacy: PrivacyMode; let recovery: Metric; let strain: Metric; let nutrition: Nutrition; let activeWorkout: Workout?
}

private struct Entry: TimelineEntry {
    let date: Date
    let snapshot: Snapshot?
    var isStale: Bool {
        guard let snapshot else { return true }
        let partial = snapshot.recovery.state == .partial || snapshot.strain.state == .partial || snapshot.nutrition.state == .partial
        return date.timeIntervalSince(snapshot.generatedAt) > (partial ? 2 * 60 * 60 : 24 * 60 * 60)
    }
    var hidesValues: Bool { snapshot?.privacy != .showValues }
}

private struct Provider: TimelineProvider {
    func placeholder(in context: Context) -> Entry { Entry(date: .now, snapshot: Self.sample) }
    func getSnapshot(in context: Context, completion: @escaping (Entry) -> Void) { completion(load(at: .now) ?? placeholder(in: context)) }
    func getTimeline(in context: Context, completion: @escaping (Timeline<Entry>) -> Void) {
        let entry = load(at: .now) ?? Entry(date: .now, snapshot: nil)
        let refresh = entry.snapshot.map { max(.now.addingTimeInterval(15 * 60), $0.generatedAt.addingTimeInterval(2 * 60 * 60)) }
            ?? .now.addingTimeInterval(60 * 60)
        completion(Timeline(entries: [entry], policy: .after(refresh)))
    }
    private func load(at date: Date) -> Entry? {
        guard let data = UserDefaults(suiteName: appGroup)?.data(forKey: snapshotKey),
              let snapshot = try? JSONDecoder().decode(Snapshot.self, from: data),
              snapshot.schemaVersion == 1, snapshot.generatedAt <= date.addingTimeInterval(5 * 60) else { return nil }
        return Entry(date: date, snapshot: snapshot)
    }
    static let sample = Snapshot(schemaVersion: 1, generatedAt: .now, localDayStart: .now,
        timeZoneIdentifier: TimeZone.current.identifier, privacy: .showValues,
        recovery: Metric(score: 78, state: .current, sourceLabel: "PersonalFitness recovery estimate"),
        strain: Metric(score: 54, state: .partial, sourceLabel: "PersonalFitness activity-load estimate"),
        nutrition: Nutrition(consumedCalories: 1240, calorieGoal: 2200, state: .partial),
        activeWorkout: Workout(name: "Upper Body", completedSets: 7, plannedSets: 14, startedAt: .now.addingTimeInterval(-1800)))
}

private enum Kind { case recovery, strain, nutrition, overview, workout }

private struct WidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: Entry
    let kind: Kind
    var body: some View {
        Group {
            if let snapshot = entry.snapshot { content(snapshot) }
            else { unavailable("Open PersonalFitness to prepare today’s widget.") }
        }
        .containerBackground(for: .widget) { Color(.systemBackground) }
        .privacySensitive()
        .widgetURL(URL(string: "personalfitness://widget/\(destination)"))
        .accessibilityElement(children: .combine)
    }
    @ViewBuilder private func content(_ snapshot: Snapshot) -> some View {
        if entry.isStale { unavailable("Last updated \(snapshot.generatedAt.formatted(.relative(presentation: .named))). Open the app to refresh.") }
        else if entry.hidesValues { unavailable("Values hidden. Enable widget values in PersonalFitness settings.") }
        else {
            switch kind {
            case .recovery: metric(title: "Recovery", metric: snapshot.recovery, color: .green)
            case .strain: metric(title: "Activity load", metric: snapshot.strain, color: .orange)
            case .nutrition: nutrition(snapshot.nutrition, updated: snapshot.generatedAt)
            case .overview: overview(snapshot)
            case .workout: workout(snapshot.activeWorkout, updated: snapshot.generatedAt)
            }
        }
    }
    private func metric(title: String, metric: Metric, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(title, systemImage: title == "Recovery" ? "heart.fill" : "bolt.fill").font(.headline).foregroundStyle(color)
            if let score = metric.score {
                Gauge(value: score, in: 0...100) { Text(title) } currentValueLabel: { Text(score.formatted(.number.precision(.fractionLength(0)))).font(.title2.bold()) }
                    .gaugeStyle(.accessoryCircularCapacity).tint(color)
            } else { Text("Unavailable").font(.title3.bold()) }
            if family != .accessoryCircular { Text(metric.state == .partial ? "Partial data" : metric.sourceLabel).font(.caption).foregroundStyle(.secondary).lineLimit(2) }
        }
    }
    private func nutrition(_ value: Nutrition, updated: Date) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Nutrition", systemImage: "fork.knife").font(.headline).foregroundStyle(.blue)
            if let consumed = value.consumedCalories {
                Text("\(Int(consumed.rounded())) kcal").font(.title2.bold())
                if let goal = value.calorieGoal { ProgressView(value: min(consumed / goal, 1)).tint(.blue); Text("of \(Int(goal.rounded())) kcal").font(.caption).foregroundStyle(.secondary) }
            } else { Text("No food logged").font(.subheadline) }
            timestamp(updated, partial: value.state == .partial)
        }
    }
    private func overview(_ value: Snapshot) -> some View {
        HStack(spacing: 16) {
            compactMetric("Recovery", value.recovery.score, .green)
            compactMetric("Load", value.strain.score, .orange)
            VStack(alignment: .leading) { Text("Nutrition").font(.caption); Text(value.nutrition.consumedCalories.map { "\(Int($0.rounded())) kcal" } ?? "No data").font(.headline) }
        }
    }
    private func compactMetric(_ title: String, _ score: Double?, _ color: Color) -> some View {
        VStack { Text(title).font(.caption); Text(score.map { Int($0.rounded()).description } ?? "—").font(.title2.bold()).foregroundStyle(color) }
    }
    private func workout(_ value: Workout?, updated: Date) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Label("Active workout", systemImage: "dumbbell.fill").font(.headline).foregroundStyle(.purple)
            if let value { Text(value.name).font(.title3.bold()).lineLimit(2); Text("\(value.completedSets) of \(value.plannedSets.map(String.init) ?? "—") sets complete").font(.subheadline); Text(value.startedAt, style: .timer).font(.caption.monospacedDigit()) }
            else { Text("No active workout").font(.subheadline); timestamp(updated, partial: false) }
        }
    }
    private func timestamp(_ date: Date, partial: Bool) -> some View { Text("\(partial ? "Partial · " : "")Updated \(date.formatted(date: .omitted, time: .shortened))").font(.caption2).foregroundStyle(.secondary) }
    private func unavailable(_ message: String) -> some View { VStack(alignment: .leading, spacing: 8) { Image(systemName: "leaf.fill").foregroundStyle(.green); Text("PersonalFitness").font(.headline); Text(message).font(.caption).foregroundStyle(.secondary).lineLimit(4) }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading) }
    private var destination: String { switch kind { case .recovery: "recovery"; case .strain: "strain"; case .nutrition: "nutrition"; case .overview: "today"; case .workout: "workout" } }
}

private struct RecoveryWidget: Widget {
    var body: some WidgetConfiguration { StaticConfiguration(kind: "PersonalFitness.Recovery", provider: Provider()) { WidgetView(entry: $0, kind: .recovery) }.configurationDisplayName("Recovery").description("Your latest explainable recovery estimate.").supportedFamilies([.systemSmall, .accessoryCircular, .accessoryRectangular]) }
}
private struct StrainWidget: Widget {
    var body: some WidgetConfiguration { StaticConfiguration(kind: "PersonalFitness.Strain", provider: Provider()) { WidgetView(entry: $0, kind: .strain) }.configurationDisplayName("Activity Load").description("Today’s observed activity-load estimate.").supportedFamilies([.systemSmall, .accessoryCircular, .accessoryRectangular]) }
}
private struct NutritionWidget: Widget {
    var body: some WidgetConfiguration { StaticConfiguration(kind: "PersonalFitness.Nutrition", provider: Provider()) { WidgetView(entry: $0, kind: .nutrition) }.configurationDisplayName("Nutrition").description("Calories logged against your optional goal.").supportedFamilies([.systemSmall, .accessoryRectangular]) }
}
private struct OverviewWidget: Widget {
    var body: some WidgetConfiguration { StaticConfiguration(kind: "PersonalFitness.Overview", provider: Provider()) { WidgetView(entry: $0, kind: .overview) }.configurationDisplayName("Daily Overview").description("Recovery, activity load, and nutrition together.").supportedFamilies([.systemMedium]) }
}
private struct WorkoutWidget: Widget {
    var body: some WidgetConfiguration { StaticConfiguration(kind: "PersonalFitness.Workout", provider: Provider()) { WidgetView(entry: $0, kind: .workout) }.configurationDisplayName("Active Workout").description("Progress for a reliably saved active strength workout.").supportedFamilies([.systemSmall, .systemMedium, .accessoryRectangular]) }
}

@main struct PersonalFitnessWidgets: WidgetBundle {
    var body: some Widget {
        RecoveryWidget()
        StrainWidget()
        NutritionWidget()
        OverviewWidget()
        WorkoutWidget()
    }
}
