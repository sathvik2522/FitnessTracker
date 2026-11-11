import SwiftUI
import SwiftData

struct DashboardRingButton: View {
    let kind: DashboardRingKind
    let assessment: EnergyAssessment
    let snapshot: HealthDaySnapshot?
    let day: Date
    let calendar: Calendar
    let scoring: ScoringDashboardModel
    let sleep: SleepModel
    var healthLoading = false
    @Environment(ScoringPreferences.self) private var preferences
    @Environment(\.dynamicTypeSize) private var typeSize
    private var color: Color { kind == .strain ? FitnessTheme.energy : kind == .recovery ? FitnessTheme.carbs : FitnessTheme.sleep }
    var body: some View {
        let reading = scoring.loading || sleep.loading || healthLoading
        let values: (StrainEstimate?, RecoveryEstimate) = reading || preferences.error != nil
            ? (nil, RecoveryScoring.combine([], partial: true))
            : scoring.estimates(day: day, snapshot: snapshot, sleep: sleep.nights.first, configuration: preferences.configuration, calendar: calendar)
        let energy = preferences.estimate(assessment, calendar: calendar)
        let state = preferences.error == nil
            ? DashboardRingState.wellness(kind, strain: values.0, recovery: values.1, energy: energy, loading: reading)
            : DashboardRingState(value: "Review", unit: "", title: kind.rawValue, status: "Check settings")
        let fraction = kind == .strain ? values.0?.score.map { $0 / 100 } : kind == .recovery ? values.1.score.map { $0 / 100 } : energy.progressFraction
        NavigationLink {
            RingDetailView(kind: kind, assessment: assessment, snapshot: snapshot, day: day, calendar: calendar, scoring: scoring, sleep: sleep)
        } label: {
            VStack(spacing: 7) {
                FitnessRing(value: state.value, unit: state.unit, color: color, fraction: reading || preferences.error != nil ? nil : fraction)
                    .frame(maxWidth: typeSize.isAccessibilitySize ? 160 : .infinity)
                Text(state.title).font(.subheadline.weight(.semibold)).multilineTextAlignment(.center)
                if kind == .balance { Text(energy.progressFraction == nil ? "Intake / expenditure" : energy.progressLabel).font(.caption2).foregroundStyle(.secondary).multilineTextAlignment(.center) }
                Text(state.status).font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
            }.frame(maxWidth: .infinity, alignment: .top).contentShape(Rectangle())
        }.buttonStyle(.plain).accessibilityAddTraits(.isButton)
            .accessibilityLabel("\(state.title), \(state.value) \(state.unit), \(state.status). \(kind == .balance ? energy.progressLabel : "Progress out of 100"). View inputs and setup")
            .accessibilityIdentifier("ring.\(kind == .balance ? "balance" : kind.rawValue.lowercased())")
    }
}

struct RingDetailView: View {
    let kind: DashboardRingKind
    let assessment: EnergyAssessment
    let snapshot: HealthDaySnapshot?
    let day: Date
    let calendar: Calendar
    let scoring: ScoringDashboardModel
    let sleep: SleepModel
    @Environment(\.modelContext) private var context
    @Environment(ScoringPreferences.self) private var preferences
    var body: some View {
        let values = scoring.estimates(day: day, snapshot: snapshot, sleep: sleep.nights.first, configuration: preferences.configuration, calendar: calendar)
        let energy = preferences.estimate(assessment, calendar: calendar)
        List {
            if scoring.loading || sleep.loading { LoadingState(message: "Reading scoring inputs") }
            if let error = scoring.error ?? preferences.error { ErrorMessage(title: "Review scoring inputs", message: error) }
            if let issue = scoring.historyIssue { Text(issue).font(.footnote) }
            if kind == .strain { strainDetails(values.0) }
            else if kind == .recovery { recoveryDetails(values.1) }
            else { energyDetails(energy) }
            Section("Settings and source window") {
                NavigationLink("Scoring & expenditure settings") { ScoringSettingsView() }
                Text("Selected local day: \(assessment.window.start.formatted(date: .abbreviated, time: .shortened)) through \(assessment.window.end.formatted(date: .abbreviated, time: .shortened)) · \(assessment.window.timeZoneIdentifier)")
                Text("Today's activity and energy are incomplete. Historical Health coverage is not certified; later synchronization can change Health estimates. Closed-day predictions are preserved at first calculation; scoring settings can change Strain/Recovery. Missing samples may mean no data, hidden read access or delayed sync.")
            }.font(.footnote)
        }.navigationTitle(kind == .balance ? "Estimated balance" : kind.rawValue).fitnessScreen()
    }
    @ViewBuilder private func strainDetails(_ strain: StrainEstimate?) -> some View {
        Section("Activity-load estimate") {
            if let value = strain, let score = value.score, let observed = value.load.value, let unit = value.load.unit {
                Text("\(score.formatted(.number.precision(.fractionLength(0)))) / 100").font(.largeTitle.bold()).accessibilityIdentifier("strain.score")
                Text(value.provisional ? "Provisional activity estimate" : "Personalized load indicator")
                LabeledContent("Observed load", value: "\(observed.formatted(.number.precision(.fractionLength(0...1)))) \(unit.rawValue)")
                if let target = value.target { LabeledContent("Display target", value: target.formatted(.number.precision(.fractionLength(0...1)))) }
                Text("Target: \(value.personalized ? "personal median" : "configured provisional value") × target scale. \(value.historyDays) eligible positive prior days. 100 × min(1, daily load / target); 100 is scale saturation, not a physiological limit.")
                ForEach(value.load.notes, id: \.self) { Text($0).font(.footnote) }
            } else {
                Text("Start logging activity").font(.headline)
                Text("Finish a workout, log cardio, or connect Apple Health from Today. A zero score requires an actual recorded zero, not an empty query.")
            }
            if let issue = snapshot?.workouts.issue { Text("Health workout read: " + issue.rawValue).font(.footnote) }
            if let issue = snapshot?.active.issue { Text("Health activity fallback: " + issue.rawValue).font(.footnote) }
            Button("Open training log") { NotificationCenter.default.post(name: .openWorkoutLog, object: nil) }.frame(minHeight: 44)
            Text("Session load = completed duration in minutes × optional session RPE (0–10). If any usable session lacks RPE, the whole day's workout load uses duration-only minutes instead. With no usable workouts, active energy or steps can provide a separate activity fallback. Modes are never added. Manual records take precedence over possibly matching Health workout representations; this does not delete records or modify energy.")
            Text("This is a transparent engineering estimate of activity/training load. It is not WHOOP/Bevel strain, a clinical measure, or a health/injury threshold.")
        }
    }
    @ViewBuilder private func recoveryDetails(_ recovery: RecoveryEstimate) -> some View {
        Section("Wellness estimate") {
            if let score = recovery.score {
                Text("\(score.formatted(.number.precision(.fractionLength(0)))) / 100").font(.largeTitle.bold()).accessibilityIdentifier("recovery.score")
                Text(recovery.provisional ? "Provisional · limited or partial signals" : "All four signals eligible · heuristic estimate")
                Text("\(recovery.eligible.count) contributing signals. Each eligible configured weight is divided by their total; missing signals contribute nothing and are not penalized.")
            } else { Text("Build your baseline").font(.headline); Text("Enable recorded sleep, or optionally connect HRV and resting heart rate. No default recovery score is invented.") }
            Text("A wellness-oriented estimate, not a measure of readiness, sleep quality, overtraining, illness or injury risk. Initial weights and mappings are product heuristics, not clinically validated constants.")
        }
        ForEach(recovery.components) { component in
            Section(component.id) {
                if let value = component.score {
                    LabeledContent("Component score", value: value.formatted(.number.precision(.fractionLength(0...1))))
                    if component.weight > 0 && recovery.eligibleWeight > 0 {
                        LabeledContent("Effective weight", value: (100 * component.weight / recovery.eligibleWeight).formatted(.number.precision(.fractionLength(0...1))) + "%")
                    } else { Text("Excluded: configured weight is zero.") }
                } else { Text("Building baseline / not eligible") }
                if let recent = component.recent { LabeledContent("Recent value", value: recent.formatted(.number.precision(.fractionLength(0...2)))) }
                if let baseline = component.baseline { LabeledContent("Baseline / target", value: baseline.formatted(.number.precision(.fractionLength(0...2)))) }
                Text(component.detail).font(.footnote)
                if let window = component.baselineWindow { Text("Baseline: \(window.start.formatted(date: .abbreviated, time: .shortened)) – \(window.end.formatted(date: .abbreviated, time: .shortened))").font(.caption) }
                if let window = component.recentWindow { Text("Recent: \(window.start.formatted(date: .abbreviated, time: .shortened)) – \(window.end.formatted(date: .abbreviated, time: .shortened))").font(.caption) }
                if component.id == "HRV SDNN" { Text("Units: milliseconds, SDNN (not RMSSD). Score = clamp(50 + slope × (recent / baseline − 1), 0, 100). Measurement timing and context can change HRV.").font(.footnote) }
                if component.id == "Resting heart rate" { Text("Units: beats/minute. Score = clamp(100 − penalty × max(0, recent − baseline), 0, 100). A single elevated measurement does not diagnose poor recovery.").font(.footnote) }
            }
        }
        Section("Optional Health connections") {
            if !sleep.requested {
                Button("Enable sleep insights") { Task { await sleep.connect(day: day, calendar: calendar) } }.disabled(sleep.connecting || !sleep.available)
            }
            Text("HRV SDNN and resting heart rate are a separate, optional read request used for personal baselines. No raw heart samples are saved to the diary, exported or sent over the network.")
            Button(scoring.recoveryRequested ? "Review HRV & resting HR access" : "Enable HRV & resting heart rate") {
                Task { await scoring.connect(day: day, context: context, calendar: calendar) }
            }.disabled(scoring.requesting || !scoring.healthAvailable).frame(minHeight: 44)
            if let issue = scoring.readings.hrv.issue { Text("HRV: " + issue.rawValue) }
            if let issue = scoring.readings.restingHR.issue { Text("Resting heart rate: " + issue.rawValue) }
            Text("Request completion does not prove that read access was granted. Manage individual reads in Apple Health or Settings. Queries never show a permission sheet. Sleep window: local previous noon to selected-day noon, clipped to now; overlaps count once and conflicting/invalid records are excluded from recovery.")
            NavigationLink("View recorded sleep & context") { ScrollView { SleepOverview(day: day).padding() }.navigationTitle("Sleep & context").fitnessScreen() }
        }.font(.footnote)
    }
    @ViewBuilder private func energyDetails(_ energy: DashboardEnergyEstimate) -> some View {
        Section("Logged intake versus estimated expenditure") {
            MetricRow(title: EnergyDisplay.balanceTitle(energy.balance), value: energy.balance, symbol: "equal.circle")
            MetricRow(title: "Calories consumed", value: energy.consumed, symbol: "fork.knife")
            MetricRow(title: "Resting energy (Health)", value: assessment.balance.resting, symbol: "bed.double")
            MetricRow(title: "Active energy (Health)", value: assessment.balance.active, symbol: "flame")
            if let component = energy.record.resting {
                MetricRow(title: (energy.record.explicitDailyEstimate == nil ? "Resting used · " : "Resting observed separately · ") + (component.predicted ? "predicted" : "Health"), value: component.kcal, symbol: "bed.double")
                Text(component.source.rawValue).font(.caption)
            }
            if let component = energy.record.active {
                MetricRow(title: (energy.record.explicitDailyEstimate == nil ? "Active used · " : "Active observed separately · ") + (component.predicted ? "predicted" : "Health"), value: component.kcal, symbol: "flame")
                Text(component.source.rawValue).font(.caption)
            }
            MetricRow(title: "Estimated total expenditure", value: energy.expenditure, symbol: "sum")
            Text(energy.progressLabel + ". Ring arc is logged intake divided by expenditure for this window, capped at 100%; it is not a percentage deficit or fat change.")
            Text("Calculated: " + energy.record.calculatedAt.formatted(date: .abbreviated, time: .shortened))
            Text(energy.source)
            ForEach(energy.record.inputIssues, id: \.self) { Text($0).font(.footnote) }
            if let profile = energy.record.profile {
                Text("Prediction inputs: age \(profile.age.formatted()), height \(profile.heightCM.formatted()) cm, selected weight \(profile.weightKG.formatted()) kg; \(profile.parameter.rawValue) coefficient; activity multiplier \(profile.multiplier.map { $0.formatted() } ?? "not configured").").font(.footnote)
            }
            if energy.fallback { Text("Prediction / mixed-source estimate. Inspect the component sources. An independent explicit total is never added to Health components.") }
            Text("Preferred expenditure = valid Health resting + active energy over the same window. Balance = logged intake − expenditure. Negative means estimated deficit; positive means surplus. An empty diary is unknown intake. Today's result is provisional; a historical diary may omit meals.")
            Text("This does not directly measure fat gain/loss. No workout, machine calories or calorie-intake goal is added to expenditure. Progress energy charts retain their Health-only series; a configured Today/Food fallback is not backfilled into them.")
            if energy.consumed == nil { Button("Log food for this date") { NotificationCenter.default.post(name: .openFoodDiary, object: day) } }
        }
    }
}
