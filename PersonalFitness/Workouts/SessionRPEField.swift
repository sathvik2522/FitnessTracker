import SwiftUI

struct SessionRPEField: View {
    @Binding var value: Double?
    private var choices: [Double] {
        var result = (0...10).map(Double.init)
        if let value, value.isFinite, (0...10).contains(value), !result.contains(value) { result.append(value) }
        return result.sorted()
    }
    var body: some View {
        Picker("Session RPE (optional)", selection: $value) {
            Text("Not rated").tag(Double?.none)
            ForEach(choices, id: \.self) { number in
                Text(NutritionNumber.text(number) + (number == 0 ? " · no effort" : number == 10 ? " · maximal effort" : ""))
                    .tag(Double?(number))
            }
        }.accessibilityIdentifier("session.rpe").frame(minHeight: 44)
        Text("Rate the whole session's perceived effort from 0 to 10. Optional; no rating is inferred from sets, calories or exercise type. You can edit it later.")
            .font(.footnote).foregroundStyle(.secondary)
    }
}
