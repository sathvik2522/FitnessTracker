import SwiftUI
import Charts

struct EnergyHistoryChart: View {
    let days: [ReportDay]
    var calendar: Calendar = .current
    @State private var selection: Date?
    @State private var inspectedDate: Date?
    private var points: [ReportChartPoint] { ReportSeries.points(days, metrics: [.consumed, .expenditure]) }
    var body: some View {
        if points.isEmpty {
            EmptyState(title: "No calorie history available", message: "Log food or connect Apple Health. Missing values are not plotted as zero.", symbol: "chart.xyaxis.line")
        } else {
            VStack(alignment: .leading, spacing: 12) {
            Chart(points) { point in
                if !point.partial {
                    LineMark(x: .value("Day", point.day), y: .value("kcal", point.value),
                             series: .value("Continuous segment", "\(point.metric.rawValue)-\(point.segment)"))
                        .foregroundStyle(by: .value("Metric", point.metric.rawValue))
                }
                PointMark(x: .value("Day", point.day), y: .value("kcal", point.value))
                    .foregroundStyle(by: .value("Metric", point.metric.rawValue))
                    .opacity(point.partial ? 0.55 : 1)
                    .accessibilityLabel("\(point.day.formatted(date: .abbreviated, time: .omitted)), \(point.metric.rawValue)\(point.partial ? ", day in progress" : "")")
                    .accessibilityValue("\(EnergyDisplay.kilocalories(point.value)) kilocalories")
            }
            .chartForegroundStyleScale(domain: ["Logged intake", "Estimated expenditure"], range: [FitnessTheme.blue, FitnessTheme.energy])
            .chartYScale(domain: .automatic(includesZero: true))
            .chartXAxis {
                AxisMarks(values: .stride(by: .day, count: max(1, (days.count + 3) / 4))) { _ in
                    AxisGridLine(); AxisTick(); AxisValueLabel(format: .dateTime.month(.abbreviated).day())
                }
            }
            .chartXSelection(value: $selection)
            .onChange(of: selection) { _, value in if let value { inspectedDate = value } }
            .environment(\.calendar, calendar)
            .frame(height: 240)
            .accessibilityLabel("Logged calories and estimated expenditure history")
            .accessibilityIdentifier("progress.energyChart")
            ChartDayDetails(selection: inspectedDate, points: points, calendar: calendar, unit: "kcal", identifier: "progress.energySelection")
            }
        }
    }
}

struct MacroHistoryChart: View {
    let days: [ReportDay]
    var calendar: Calendar = .current
    @State private var selection: Date?
    @State private var inspectedDate: Date?
    private var points: [ReportChartPoint] { ReportSeries.points(days, metrics: [.protein, .carbohydrates, .fat]) }
    var body: some View {
        if points.isEmpty { Text("No logged macro values in this range.").foregroundStyle(.secondary) }
        else {
            VStack(alignment: .leading, spacing: 12) {
            Chart(points) { point in
                BarMark(x: .value("Day", point.day, unit: .day), y: .value("Grams", point.value))
                    .position(by: .value("Macro", point.metric.rawValue))
                    .foregroundStyle(by: .value("Macro", point.metric.rawValue))
                    .opacity(point.partial ? 0.55 : 1)
                    .accessibilityLabel("\(point.day.formatted(date: .abbreviated, time: .omitted)), \(point.metric.rawValue)\(point.partial ? ", day in progress" : "")")
                    .accessibilityValue("\(point.value.formatted(.number.precision(.fractionLength(0...1)))) grams")
            }.chartForegroundStyleScale(domain: ["Protein", "Carbohydrates", "Fat"], range: [FitnessTheme.protein, FitnessTheme.carbs, FitnessTheme.fat])
                .chartXAxis {
                    AxisMarks(values: .stride(by: .day, count: max(1, (days.count + 3) / 4))) { _ in
                        AxisGridLine(); AxisTick(); AxisValueLabel(format: .dateTime.month(.abbreviated).day())
                    }
                }
                .chartXSelection(value: $selection).environment(\.calendar, calendar)
                .onChange(of: selection) { _, value in if let value { inspectedDate = value } }
                .frame(height: 240).accessibilityLabel("Logged macro history")
            ChartDayDetails(selection: inspectedDate, points: points, calendar: calendar, unit: "g", identifier: "progress.macroSelection")
            }
        }
    }
}

struct WeightHistoryChart: View {
    let points: [WeightTrendPoint]
    var calendar: Calendar = .current
    @State private var selection: Date?
    @State private var inspectedDate: Date?
    var body: some View {
        if points.isEmpty {
            EmptyState(title: "No weight samples", message: "Read available Apple Health weights or add a manual entry. No weight is inferred from calories.", symbol: "scalemass")
        } else {
            VStack(alignment: .leading, spacing: 12) {
            ForEach(WeightOrigin.allCases) { origin in
                let source = points.filter { $0.origin == origin }.sorted { $0.day < $1.day }
                if let first = source.first, let last = source.last {
                    if source.count >= 2 {
                        Text("\(origin.rawValue): \(NutritionNumber.text(first.kilograms)) → \(NutritionNumber.text(last.kilograms)) kg · \(source.count) recorded days")
                            .font(.caption).foregroundStyle(.secondary)
                    } else {
                        Text("\(origin.rawValue): \(NutritionNumber.text(first.kilograms)) kg · one recorded day; more history needed for a trend")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            Chart(points) { point in
                PointMark(x: .value("Day", point.day), y: .value("kg", point.kilograms))
                    .foregroundStyle(by: .value("Source", point.origin.rawValue))
                    .accessibilityLabel("\(point.day.formatted(date: .abbreviated, time: .omitted)), \(point.origin.rawValue)")
                    .accessibilityValue("\(point.kilograms.formatted(.number.precision(.fractionLength(0...2)))) kilograms")
                if let mean = point.mean {
                    LineMark(x: .value("Day", point.day), y: .value("7-day mean kg", mean),
                        series: .value("Source segment", "\(point.origin.rawValue)-\(point.segment)"))
                        .foregroundStyle(by: .value("Source", point.origin.rawValue))
                        .lineStyle(StrokeStyle(lineWidth: 2, dash: [5, 3]))
                        .accessibilityLabel("7-day recorded-day mean, \(point.origin.rawValue), \(point.recordedDays) recorded days")
                        .accessibilityValue("\(mean.formatted(.number.precision(.fractionLength(0...2)))) kilograms")
                }
            }.chartYScale(domain: .automatic(includesZero: false))
                .chartXAxis { AxisMarks(values: .automatic(desiredCount: 4)) }
                .chartXSelection(value: $selection).environment(\.calendar, calendar)
                .onChange(of: selection) { _, value in if let value { inspectedDate = value } }
                .frame(height: 260).accessibilityLabel("Body-weight history by source")
                .accessibilityIdentifier("progress.weightChart")
            if let selection = inspectedDate {
                let selected = ReportSelection.values(on: selection, from: points, calendar: calendar, day: \.day)
                VStack(alignment: .leading, spacing: 4) {
                    Text(selection.formatted(date: .abbreviated, time: .omitted)).font(.subheadline.bold())
                    if selected.isEmpty { Text("No recorded weight on this day.") }
                    ForEach(selected) { point in
                        Text("\(point.origin.rawValue): \(point.kilograms.formatted(.number.precision(.fractionLength(0...2)))) kg")
                    }
                }.font(.caption).accessibilityElement(children: .combine)
            } else { Text("Drag across the chart to inspect a day.").font(.caption).foregroundStyle(.secondary) }
            }
        }
    }
}

struct ExerciseProgressCharts: View {
    let history: [ExercisePerformance]
    @State private var selection: Date?
    @State private var inspectedDate: Date?
    var body: some View {
        Text("Best external load (kg)").font(.headline)
        Chart(history.sorted { $0.date < $1.date }) { point in
            LineMark(x: .value("Session", point.date), y: .value("External kg", point.bestWeightKg))
            PointMark(x: .value("Session", point.date), y: .value("External kg", point.bestWeightKg))
        }.chartXSelection(value: $selection).onChange(of: selection) { _, value in if let value { inspectedDate = value } }.frame(height: 200).accessibilityLabel("Best external load per completed session, kilograms")
        Text("Completed repetitions").font(.headline)
        Chart(history.sorted { $0.date < $1.date }) { point in
            BarMark(x: .value("Session", point.date), y: .value("Completed reps", point.totalReps))
        }.chartXSelection(value: $selection).onChange(of: selection) { _, value in if let value { inspectedDate = value } }.frame(height: 200).accessibilityLabel("Total completed reps per session")
        if let selection = inspectedDate {
            let selected = ReportSelection.values(on: selection, from: history, calendar: .current, day: \.date)
            if selected.isEmpty { Text("No completed session on \(selection.formatted(date: .abbreviated, time: .omitted)).").font(.caption) }
            ForEach(selected) { point in
                Text("\(point.date.formatted(date: .abbreviated, time: .shortened)) · \(NutritionNumber.text(point.bestWeightKg)) kg · \(point.totalReps) reps")
                    .font(.caption)
            }
        } else { Text("Drag across a chart to inspect a day.").font(.caption).foregroundStyle(.secondary) }
    }
}

private struct ChartDayDetails: View {
    let selection: Date?
    let points: [ReportChartPoint]
    let calendar: Calendar
    let unit: String
    let identifier: String
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
        if let selection {
            let selected = ReportSelection.values(on: selection, from: points, calendar: calendar, day: \.day)
                Text(selection.formatted(date: .abbreviated, time: .omitted)).font(.subheadline.bold())
                if selected.isEmpty { Text("No recorded values on this day.") }
                ForEach(selected) { point in
                    Text("\(point.metric.rawValue): \(point.value.formatted(.number.precision(.fractionLength(0...1)))) \(unit)\(point.partial ? " · day in progress" : "")")
                }
        } else { Text("Drag across the chart to inspect a day.").font(.caption).foregroundStyle(.secondary) }
        }.font(.caption).accessibilityElement(children: .combine).accessibilityIdentifier(identifier)
    }
}
