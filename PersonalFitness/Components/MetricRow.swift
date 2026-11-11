import SwiftUI

struct MetricRow: View {
    let title: String
    let value: Double?
    var unit = "kcal"
    let symbol: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label {
                Text(title).fixedSize(horizontal: false, vertical: true)
            } icon: {
                Image(systemName: symbol)
            }
            .font(.subheadline)
            .foregroundStyle(.primary)
            if let value {
                Text("\(unit == "kcal" ? EnergyDisplay.kilocalories(value) : value.formatted(.number.precision(.fractionLength(unit == "g" || unit == "kg" ? 1 : 0)))) \(unit)")
                    .font(.title2.weight(.semibold))
                    .monospacedDigit()
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text("Unavailable")
                    .font(.headline)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 6)
        .accessibilityElement(children: .combine)
    }
}
