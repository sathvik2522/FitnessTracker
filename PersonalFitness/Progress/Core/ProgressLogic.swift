import Foundation

enum ReportPeriod: String, CaseIterable, Identifiable {
    case day = "Day", week = "Week", month = "Month", custom = "Custom"
    var id: String { rawValue }
}

enum ReportError: String, LocalizedError {
    case dates = "Choose valid dates in order, ending no later than today."
    case length = "Choose at most 90 local calendar days per report."
    case weight = "Enter a finite body weight greater than zero, in kilograms."
    var errorDescription: String? { rawValue }
}

struct ReportRange: Equatable {
    let start: Date
    let end: Date // Exclusive next midnight, including today's available window.
    let days: [Date]
    init(period: ReportPeriod, anchor: Date, customStart: Date, customEnd: Date,
         now: Date, calendar: Calendar) throws {
        guard [anchor, customStart, customEnd, now].allSatisfy({ $0.timeIntervalSince1970.isFinite }) else { throw ReportError.dates }
        let today = calendar.startOfDay(for: now)
        let first: Date, last: Date
        if period == .custom {
            first = calendar.startOfDay(for: customStart)
            last = calendar.startOfDay(for: customEnd)
        } else {
            guard anchor <= now, let interval = calendar.dateInterval(of: period == .day ? .day : period == .week ? .weekOfYear : .month, for: anchor) else { throw ReportError.dates }
            first = interval.start
            last = min(today, calendar.date(byAdding: .day, value: -1, to: interval.end)!)
        }
        guard first <= last, last <= today, let end = calendar.date(byAdding: .day, value: 1, to: last) else { throw ReportError.dates }
        var days: [Date] = []
        var cursor = first
        while cursor < end {
            guard days.count < 90 else { throw ReportError.length }
            days.append(cursor)
            guard let next = calendar.date(byAdding: .day, value: 1, to: cursor), next > cursor else { throw ReportError.dates }
            cursor = next
        }
        start = first; self.end = end; self.days = days
    }
}

struct ReportFood: Identifiable {
    let id: UUID
    let date: Date
    let name: String
    let portion: NutritionPortion
}

struct ReportDay: Identifiable {
    var id: Date { window.start }
    let window: LocalDayWindow
    let food: [ReportFood]
    let nutrition: NutritionTotals
    let assessment: EnergyAssessment
    var consumed: Double? { nutrition.entryCount > 0 ? nutrition.calories : nil }
    var protein: Double? { nutrition.entryCount > 0 ? nutrition.protein : nil }
    var carbohydrates: Double? { nutrition.entryCount > 0 ? nutrition.carbohydrates : nil }
    var fat: Double? { nutrition.entryCount > 0 ? nutrition.fat : nil }

    init(window: LocalDayWindow, food: [ReportFood], aggregates: [EnergyAggregate]) {
        self.window = window
        self.food = food.filter { $0.date >= window.start && $0.date < window.end }
        nutrition = NutritionTotals(portions: self.food.map(\.portion))
        assessment = EnergyReconciliation.assess(window: window,
            food: FoodEnergy(reading: nutrition.entryCount == 0 ? .missing : nutrition.calories.map(CalorieReading.value) ?? .failed, window: window),
            aggregates: aggregates)
    }
}

/// Food totals cover logged days only. Energy balance uses the same subset of
/// closed days with both intake and expenditure, rather than subtracting totals
/// from different coverage periods. Closed days can still have unverified data.
struct ReportTotals {
    let days: Int
    let foodDays: Int
    let calories: Double?
    let protein: Double?
    let carbohydrates: Double?
    let fat: Double?
    let matchedClosedDays: Int
    let matchedIntake: Double?
    let matchedExpenditure: Double?
    var matchedBalance: Double? {
        guard let matchedIntake, let matchedExpenditure else { return nil }
        let value = matchedIntake - matchedExpenditure
        return value.isFinite ? value : nil
    }
    init(_ reports: [ReportDay]) {
        days = reports.count
        let logged = reports.filter { !$0.food.isEmpty }
        foodDays = logged.count
        calories = Self.sum(logged.map(\.consumed))
        protein = Self.sum(logged.map(\.protein))
        carbohydrates = Self.sum(logged.map(\.carbohydrates))
        fat = Self.sum(logged.map(\.fat))
        let matched = reports.filter { !$0.window.isPartial && $0.assessment.balance.net != nil }
        matchedClosedDays = matched.count
        matchedIntake = Self.sum(matched.map(\.consumed))
        matchedExpenditure = Self.sum(matched.map { $0.assessment.balance.expenditure })
    }
    private static func sum(_ values: [Double?]) -> Double? {
        guard !values.isEmpty, values.allSatisfy({ $0 != nil }) else { return nil }
        let total = values.compactMap { $0 }.reduce(0, +)
        return total.isFinite ? total : nil
    }
}

enum WeightOrigin: String, Codable, CaseIterable, Identifiable, Sendable {
    case health = "Apple Health", manual = "Manual · this app"
    var id: String { rawValue }
}

struct WeightObservation: Identifiable, Equatable, Sendable {
    let id: UUID
    let date: Date
    let kilograms: Double
    let origin: WeightOrigin
    func validated(now: Date = .now) throws -> Self {
        guard kilograms.isFinite, kilograms > 0 else { throw ReportError.weight }
        guard date.timeIntervalSince1970.isFinite, date <= now else { throw ReportError.dates }
        return self
    }
}

struct WeightTrendPoint: Identifiable {
    var id: String { "\(origin.rawValue)-\(day.timeIntervalSince1970)" }
    let day: Date
    let kilograms: Double
    let origin: WeightOrigin
    let mean: Double?
    let recordedDays: Int
    let segment: Int
}

enum WeightTrend {
    /// Latest sample for each source/day. Sources are never pooled or weighted by sample count.
    static func points(_ observations: [WeightObservation], calendar: Calendar) -> [WeightTrendPoint] {
        var seen = Set<String>()
        let unique = observations.filter { $0.kilograms.isFinite && $0.kilograms > 0 && seen.insert("\($0.origin.rawValue)-\($0.id)").inserted }
        var result: [WeightTrendPoint] = []
        for origin in WeightOrigin.allCases {
            let grouped = Dictionary(grouping: unique.filter { $0.origin == origin }) { calendar.startOfDay(for: $0.date) }
            let latest = grouped.compactMapValues { $0.max { $0.date < $1.date } }
            let days = latest.keys.sorted()
            var previous: Date?
            var segment = 0
            for day in days {
                if let previous, calendar.date(byAdding: .day, value: 1, to: previous) != day { segment += 1 }
                let beginning = calendar.date(byAdding: .day, value: -6, to: day)!
                let values = days.filter { $0 >= beginning && $0 <= day }.compactMap { latest[$0]?.kilograms }
                // Divide before summing to avoid overflow for valid finite inputs.
                let mean = values.reduce(0) { $0 + $1 / Double(values.count) }
                result.append(WeightTrendPoint(day: day, kilograms: latest[day]!.kilograms, origin: origin,
                    mean: values.count >= 2 && mean.isFinite ? mean : nil, recordedDays: values.count, segment: segment))
                previous = day
            }
        }
        return result.sorted { $0.day < $1.day }
    }
}

enum ReportMetric: String, CaseIterable {
    case consumed = "Logged intake", expenditure = "Estimated expenditure", protein = "Protein", carbohydrates = "Carbohydrates", fat = "Fat"
    func value(_ day: ReportDay) -> Double? {
        switch self {
        case .consumed: return day.consumed
        case .expenditure: return day.assessment.balance.expenditure
        case .protein: return day.protein
        case .carbohydrates: return day.carbohydrates
        case .fat: return day.fat
        }
    }
}
struct ReportChartPoint: Identifiable {
    var id: String { "\(metric.rawValue)-\(day.timeIntervalSince1970)" }
    let day: Date
    let value: Double
    let metric: ReportMetric
    let partial: Bool
    let segment: Int
}
enum ReportSeries {
    static func points(_ days: [ReportDay], metrics: [ReportMetric]) -> [ReportChartPoint] {
        metrics.flatMap { metric in
            var segment = 0
            return days.sorted { $0.id < $1.id }.compactMap { day -> ReportChartPoint? in
                guard let value = metric.value(day) else { segment += 1; return nil }
                return ReportChartPoint(day: day.id, value: value, metric: metric, partial: day.window.isPartial, segment: segment)
            }
        }
    }
}

/// A chart selection belongs to a local calendar day; never snap across gaps.
enum ReportSelection {
    static func values<T>(on selected: Date?, from values: [T], calendar: Calendar,
                          day: (T) -> Date) -> [T] {
        guard let selected, selected.timeIntervalSince1970.isFinite else { return [] }
        return values.filter { calendar.isDate(day($0), inSameDayAs: selected) }
    }
}
