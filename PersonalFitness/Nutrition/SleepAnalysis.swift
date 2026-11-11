import Foundation

/// Sleep is attributed to the day of waking using local noon-to-noon windows.
/// This intentionally includes sleep across midnight without 24-hour arithmetic.
struct SleepWindow: Equatable, Sendable {
    let start: Date
    let end: Date
    let isPartial: Bool
    init?(day: Date, now: Date, calendar: Calendar) {
        guard day.timeIntervalSince1970.isFinite, now.timeIntervalSince1970.isFinite else { return nil }
        let midnight = calendar.startOfDay(for: day)
        guard midnight <= now,
              let noon = calendar.date(bySettingHour: 12, minute: 0, second: 0, of: midnight),
              let start = calendar.date(byAdding: .day, value: -1, to: noon), start < now else { return nil }
        self.start = start; end = min(noon, now); isPartial = now < noon
    }
}

struct SleepRecord: Identifiable, Sendable {
    enum Kind: Sendable { case asleep, inBed, awake }
    let id: UUID
    let start: Date
    let end: Date
    let kind: Kind
    var sourceName: String? = nil
}

struct SleepSummary: Sendable {
    let asleepSeconds: Double?
    let inBedSeconds: Double?
    let conflictingStates: Bool
    let invalidSamples: Bool
    var sources: [String] = []
    var asleepIntervals: [DateInterval] = []
}

enum SleepAnalysis {
    /// Union intervals, not sample durations: unspecified sleep, stages, repeated
    /// sources and in-bed records must never each add another night of sleep.
    /// Conflicting awake/asleep records are flagged; no source priority is guessed.
    static func summarize(_ records: [SleepRecord], in window: SleepWindow) -> SleepSummary {
        let valid = records.filter { $0.start.timeIntervalSince1970.isFinite && $0.end.timeIntervalSince1970.isFinite && $0.end > $0.start }
        func intervals(_ kind: SleepRecord.Kind) -> [DateInterval] {
            var seen = Set<UUID>()
            return valid.filter { $0.kind == kind && seen.insert($0.id).inserted }.compactMap {
                let start = max(window.start, $0.start), end = min(window.end, $0.end)
                return end > start ? DateInterval(start: start, end: end) : nil
            }.sorted { $0.start < $1.start }
        }
        func unionDuration(_ values: [DateInterval]) -> Double? {
            guard var merged = values.first else { return nil }
            var total = 0.0
            for value in values.dropFirst() {
                if value.start <= merged.end { merged = DateInterval(start: merged.start, end: max(merged.end, value.end)) }
                else { total += merged.duration; merged = value }
            }
            return total + merged.duration
        }
        let sources = Set(valid.filter { $0.start < window.end && $0.end > window.start }
            .compactMap(\.sourceName).filter { !$0.isEmpty }).sorted()
        let asleep = intervals(.asleep), awake = intervals(.awake)
        var mergedAsleep: [DateInterval] = []
        for value in asleep {
            if let last = mergedAsleep.last, value.start <= last.end {
                mergedAsleep[mergedAsleep.count - 1] = DateInterval(start: last.start, end: max(last.end, value.end))
            } else { mergedAsleep.append(value) }
        }
        let conflict = asleep.contains { a in awake.contains { max(a.start, $0.start) < min(a.end, $0.end) } }
        return SleepSummary(asleepSeconds: unionDuration(asleep), inBedSeconds: unionDuration(intervals(.inBed)),
                            conflictingStates: conflict, invalidSamples: valid.count != records.count, sources: sources, asleepIntervals: mergedAsleep)
    }

    static func observation(current: SleepSummary, previous: [SleepSummary]) -> String? {
        guard !current.conflictingStates, !current.invalidSamples, let duration = current.asleepSeconds,
              duration.isFinite, duration >= 0 else { return nil }
        let values = previous.filter { !$0.conflictingStates && !$0.invalidSamples }.compactMap(\.asleepSeconds)
            .filter { $0.isFinite && $0 >= 0 }
        guard values.count >= 3 else { return nil }
        let mean = values.reduce(0) { $0 + $1 / Double(values.count) }
        guard mean.isFinite else { return nil }
        let difference = duration - mean
        if abs(difference) < 60 {
            return "Recorded sleep was within one minute of your average across \(values.count) prior recorded nights."
        }
        let minutes = (abs(difference) / 60).rounded(.towardZero).formatted(.number.precision(.fractionLength(0)))
        return "Recorded sleep was \(minutes) minutes \(difference < 0 ? "shorter" : "longer") than your average across \(values.count) prior recorded nights."
    }
}
