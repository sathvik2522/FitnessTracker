import SwiftUI

struct HealthMetricCard: View {
    let title: String
    let reading: HealthReading<Double>
    var unit = "kcal"
    let symbol: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            MetricCard(title: title, value: reading.value, unit: unit, symbol: symbol)
            if let issue = reading.issue {
                Label(issue.rawValue, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .accessibilityLabel("\(title) query failed. \(issue.rawValue)")
            }
        }
    }
}
