import SwiftUI

/// Dark-first navy surfaces with explicit light counterparts; foreground text
/// remains semantic. Chart/accent colors never carry meaning without a label.
enum FitnessTheme {
    static func accent(_ name: String) -> Color {
        switch name { case "mint": return surface(0x42E1B0, 0x087955); case "violet": return surface(0xB9A3FF, 0x6344BB); case "orange": return surface(0xFFB05B, 0xA24C00); default: return blue }
    }
    static func surface(_ dark: UInt32, _ light: UInt32) -> Color {
        Color(uiColor: UIColor { traits in
            let value = traits.userInterfaceStyle == .dark ? dark : light
            return UIColor(red: CGFloat((value >> 16) & 255) / 255,
                           green: CGFloat((value >> 8) & 255) / 255,
                           blue: CGFloat(value & 255) / 255, alpha: 1)
        })
    }
    static var background: Color { UserDefaults.standard.string(forKey: "personalFitness.appearance") == "black" ? .black : surface(0x070F1D, 0xEFF3F9) }
    static let card = surface(0x111E31, 0xFFFFFF)
    static let raised = surface(0x192A43, 0xE4EBF5)
    static let blue = surface(0x70B4FF, 0x145CC0)
    static let action = Color(red: 0.08, green: 0.39, blue: 0.89)
    static let protein = surface(0xBA96FF, 0x6C34BA)
    static let carbs = surface(0x35DDA4, 0x087955)
    static let fat = surface(0xFFCE58, 0x8A5A00)
    static let energy = surface(0xFFAA48, 0xA24C00)
    static let sleep = surface(0xA699FF, 0x6344BB)
}

private struct FitnessSurface: ViewModifier {
    func body(content: Content) -> some View {
        content.padding(16).frame(maxWidth: .infinity, alignment: .leading)
            .background {
                RoundedRectangle(cornerRadius: 22).fill(LinearGradient(colors: [FitnessTheme.raised, FitnessTheme.card], startPoint: .topLeading, endPoint: .bottomTrailing))
                    .overlay { RoundedRectangle(cornerRadius: 22).strokeBorder(.primary.opacity(0.06)) }
            }
    }
}
extension View {
    func fitnessCard() -> some View { modifier(FitnessSurface()) }
    func fitnessScreen() -> some View {
        scrollContentBackground(.hidden).background(FitnessTheme.background)
            .toolbarBackground(FitnessTheme.background, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
    }
}

struct FitnessProgressBar: View {
    let progress: GoalProgress
    let color: Color
    var body: some View {
        Capsule().fill(FitnessTheme.raised)
            .overlay(alignment: .leading) {
                if let fraction = progress.fraction {
                    Capsule().fill(color.gradient).scaleEffect(x: fraction, y: 1, anchor: .leading)
                }
            }.frame(height: 7).accessibilityHidden(true)
    }
}

struct FitnessRing: View {
    let value: String
    var unit = ""
    let color: Color
    var fraction: Double? = nil
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        Circle().stroke(FitnessTheme.raised, lineWidth: 7)
            .overlay {
                if let fraction, fraction.isFinite {
                    Circle().trim(from: 0, to: min(1, max(0, fraction)))
                        .stroke(color.gradient, style: StrokeStyle(lineWidth: 7, lineCap: .round))
                        .rotationEffect(.degrees(-90)).animation(reduceMotion ? nil : .easeOut(duration: 0.45), value: fraction)
                // Missing inputs leave an empty track, not decorative progress.
                }
            }
            .overlay {
                VStack(spacing: 2) {
                    Text(value).font(.system(.title2, design: .rounded).weight(.bold))
                        .monospacedDigit().lineLimit(1).minimumScaleFactor(0.5)
                    if !unit.isEmpty { Text(unit).font(.caption2).foregroundStyle(.secondary) }
                }.padding(10)
            }
            .padding(4).aspectRatio(1, contentMode: .fit)
            .accessibilityElement(children: .ignore).accessibilityLabel(value + " " + unit)
    }
}

struct MacroProgressRow: View {
    let title: String
    let amount: Double?
    let goal: Double?
    let color: Color
    var unit = "g"
    private var progress: GoalProgress { GoalProgress(amount: amount, goal: goal) }
    private func display(_ value: Double) -> String {
        unit == "kcal" || unit == "steps" ? EnergyDisplay.kilocalories(value) : value.formatted(.number.precision(.fractionLength(0...1)))
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Circle().fill(color).frame(width: 7, height: 7).accessibilityHidden(true)
                Text(title).font(.subheadline.weight(.medium))
                Spacer(minLength: 4)
                Text(amount.map { display($0) + " " + unit } ?? "Unavailable")
                    .font(.subheadline.monospacedDigit())
            }
            if let goal = progress.goal {
                HStack {
                    Text("Goal \(display(goal)) \(unit)")
                    Spacer()
                    if let remaining = progress.remaining {
                        Text("\(display(abs(remaining))) \(unit) \(remaining < 0 ? "over" : "left")")
                    }
                }.font(.caption).foregroundStyle(.secondary)
                FitnessProgressBar(progress: progress, color: color)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

struct NutritionSummaryCard: View {
    let totals: NutritionTotals
    let goals: NutritionGoals
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Label("Nutrition", systemImage: "fork.knife").font(.headline)
            if [goals.calories, goals.protein, goals.carbohydrates, goals.fat].allSatisfy({ $0 == nil }) {
                Text("Set goals to track progress.").font(.caption).foregroundStyle(.secondary)
            }
            MacroProgressRow(title: "Calories consumed", amount: totals.entryCount == 0 ? nil : totals.calories,
                             goal: goals.calories, color: FitnessTheme.blue, unit: "kcal")
                .accessibilityIdentifier("dashboard.calories")
            MacroProgressRow(title: "Protein", amount: totals.entryCount == 0 ? nil : totals.protein, goal: goals.protein, color: FitnessTheme.protein)
                .accessibilityIdentifier("dashboard.protein")
            MacroProgressRow(title: "Carbohydrates", amount: totals.entryCount == 0 ? nil : totals.carbohydrates, goal: goals.carbohydrates, color: FitnessTheme.carbs)
            MacroProgressRow(title: "Fat", amount: totals.entryCount == 0 ? nil : totals.fat, goal: goals.fat, color: FitnessTheme.fat)
        }.fitnessCard()
    }
}

struct MacroCompactCard: View {
    let title: String
    let amount: Double?
    let goal: Double?
    let color: Color
    private var progress: GoalProgress { GoalProgress(amount: amount, goal: goal) }
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.caption.weight(.semibold)).foregroundStyle(color)
            Text(amount.map { $0.formatted(.number.precision(.fractionLength(0...1))) + " g" } ?? "—")
                .font(.headline.monospacedDigit()).lineLimit(1).minimumScaleFactor(0.65)
            if let goal {
                Text("of " + goal.formatted(.number.precision(.fractionLength(0...1))) + " g")
                    .font(.caption2).foregroundStyle(.secondary)
                FitnessProgressBar(progress: progress, color: color)
            }
        }.padding(10).frame(maxWidth: .infinity, alignment: .leading)
            .background(FitnessTheme.raised, in: RoundedRectangle(cornerRadius: 14))
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\(title), \(amount.map { NutritionNumber.text($0) + " grams" } ?? "unavailable"), \(goal.map { "goal " + NutritionNumber.text($0) + " grams" } ?? "no configured goal")")
    }
}
