import SwiftUI
import SwiftData

struct ProgressReportView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.scenePhase) private var phase
    @State private var model = ProgressModel()
    private var taskKey: String {
        "\(model.period.rawValue)-\(model.anchor)-\(model.customStart)-\(model.customEnd)-\(model.reloadID)"
    }
    var body: some View {
        NavigationStack {
            ScrollView {
                // Reports are bounded to 90 days; eager layout keeps links and
                // accessibility elements stable when the selected range changes.
                VStack(alignment: .leading, spacing: 24) {
                    controls
                    if model.loading {
                        LoadingState(message: "Preparing report · \(model.completedDays) of \(model.requestedDays) days")
                    }
                    if let error = model.error {
                        ErrorMessage(title: "Report unavailable", message: error) { model.reloadID = UUID() }
                    } else if let report = model.report {
                        summary(report)
                    }
                }.padding()
            }
            .background(FitnessTheme.background)
            .fitnessScreen().navigationBarTitleDisplayMode(.inline).navigationTitle("Progress")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    NavigationLink { DataExportView() } label: { Label("Export local data", systemImage: "square.and.arrow.up") }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Refresh", systemImage: "arrow.clockwise") { model.reloadID = UUID() }
                }
            }
            .task(id: taskKey) {
                model.loading = true
                await model.load(context: context)
            }
            .refreshable { await model.load(context: context) }
            .onChange(of: phase) { _, next in if next == .active { model.foreground() } }
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.significantTimeChangeNotification)) { _ in model.foreground() }
            .onReceive(NotificationCenter.default.publisher(for: .nutritionDidChange)) { _ in model.reloadID = UUID() }
            .onReceive(NotificationCenter.default.publisher(for: .workoutsDidChange)) { _ in model.reloadID = UUID() }
            .onReceive(NotificationCenter.default.publisher(for: .manualWeightDidChange)) { _ in model.reloadID = UUID() }
        }
    }
    private var controls: some View {
        VStack(alignment: .leading, spacing: 12) {
            Picker("Report period", selection: $model.period) {
                ForEach(ReportPeriod.allCases) { Text($0.rawValue).tag($0) }
            }.pickerStyle(.menu).accessibilityIdentifier("progress.period")
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) { rangeButtons }
                VStack(alignment: .leading, spacing: 8) { rangeButtons }
            }
            if model.period == .custom {
                DatePicker("From", selection: $model.customStart, in: ...Date.now, displayedComponents: .date)
                DatePicker("Through", selection: $model.customEnd, in: ...Date.now, displayedComponents: .date)
                Text("Inclusive local dates, up to 90 days.").font(.footnote).foregroundStyle(.secondary)
            } else {
                DatePicker("Report date", selection: $model.anchor, in: ...Date.now, displayedComponents: .date)
                HStack {
                    Button("Previous", systemImage: "chevron.left") { model.movePeriod(by: -1) }.frame(minHeight: 44)
                    Spacer()
                    Button("Next", systemImage: "chevron.right") { model.movePeriod(by: 1) }.frame(minHeight: 44)
                        .disabled(!model.canMoveForward)
                }
            }
        }.fitnessCard()
    }
    @ViewBuilder private var rangeButtons: some View {
        ForEach([7, 30, 90], id: \.self) { count in
            Button("\(count) days") { model.selectRecentDays(count) }
                .buttonStyle(.bordered).tint(model.isRecentDays(count) ? FitnessTheme.blue : .secondary)
                .frame(minHeight: 44).accessibilityAddTraits(model.isRecentDays(count) ? .isSelected : [])
        }
    }
    @ViewBuilder private func summary(_ report: ProgressReport) -> some View {
        Text("\(report.range.start.formatted(date: .abbreviated, time: .omitted)) – \(report.range.days.last!.formatted(date: .abbreviated, time: .omitted))")
            .font(.headline).accessibilityIdentifier("progress.range")
        Text("\(report.calendar.timeZone.identifier) · Refreshed \(report.refreshed.formatted(date: .omitted, time: .shortened))").font(.caption).foregroundStyle(.secondary)
        if let message = model.connectionMessage {
            Text(message).foregroundStyle(.secondary)
            Button("Connect Apple Health", systemImage: "heart") { Task { await model.connect(context: context) } }
                .buttonStyle(.bordered).frame(minHeight: 44).disabled(model.connecting)
        }
        SectionHeading(title: "Calories over time", subtitle: "Logged intake versus estimated resting + active energy")
        EnergyHistoryChart(days: report.days, calendar: report.calendar).fitnessCard()
        Text("Gaps are unavailable data, not zero. Faded, unconnected points are today's incomplete measurements. Health energy is estimated and coverage may be incomplete even on historical days.")
            .font(.footnote).foregroundStyle(.secondary)
        let totals = report.totals
        MetricCard(title: "Recorded food calories", value: totals.calories, symbol: "fork.knife")
        Text("Food logged on \(totals.foodDays) of \(totals.days) days. Missing days do not establish zero intake; logged days may omit meals.").font(.footnote)
        if totals.foodDays >= 2, let calories = totals.calories {
            Text("Average \(EnergyDisplay.kilocalories(calories / Double(totals.foodDays))) kcal per logged day · \(totals.foodDays) days with entries")
                .font(.subheadline).foregroundStyle(.secondary)
        }
        MetricCard(title: "Matched-day estimated balance", value: totals.matchedBalance, symbol: "equal.circle")
        Text("Intake minus expenditure, using only the same \(totals.matchedClosedDays) closed days with both values. Today is excluded. Negative means estimated deficit; positive means estimated surplus.").font(.footnote).foregroundStyle(.secondary)
        SectionHeading(title: "Macros", subtitle: "Recorded portions only, in grams")
        MacroHistoryChart(days: report.days, calendar: report.calendar).fitnessCard()
        Text("Range totals · Protein \(display(totals.protein)) · Carbs \(display(totals.carbohydrates)) · Fat \(display(totals.fat))").font(.subheadline)
        SectionHeading(title: "Body weight", subtitle: "Separate Apple Health and manual sources")
        WeightHistoryChart(points: report.trend, calendar: report.calendar).fitnessCard()
        Text("Points use the latest sample per source/day. Dashed lines are a trailing seven-calendar-day mean of recorded days only (at least two days). Gaps are not filled. Short-term weight changes do not directly measure fat gain or loss.").font(.footnote).foregroundStyle(.secondary)
        NavigationLink("Weight history & manual entry") { WeightHistoryView(report: report) }.buttonStyle(.bordered).frame(minHeight: 44)
        NavigationLink("Workout frequency & history") { TrainingReportView(report: report) }.buttonStyle(.bordered).frame(minHeight: 44)
        SectionHeading(title: "Daily details", subtitle: "Inspect every underlying value and its availability")
        ForEach(report.days.reversed()) { day in
            NavigationLink { ReportDetailView(day: day, report: report) } label: {
                VStack(alignment: .leading, spacing: 6) {
                    Text(day.id.formatted(date: .complete, time: .omitted)).font(.headline)
                    Text(day.food.isEmpty ? "No food data logged" : "\(day.food.count) portions · \(day.consumed.map { EnergyDisplay.kilocalories($0) + " kcal" } ?? "Invalid calorie data")")
                    Text(day.window.isPartial ? "Day in progress" : "Historical estimate · coverage unverified").font(.caption)
                }.frame(maxWidth: .infinity, minHeight: 44, alignment: .leading).padding()
            }.buttonStyle(.plain).background(FitnessTheme.card, in: RoundedRectangle(cornerRadius: 16))
        }
    }
    private func display(_ value: Double?) -> String {
        value.map { $0.formatted(.number.precision(.fractionLength(0...1))) + " g" } ?? "Unavailable"
    }
}
