import SwiftUI
import UIKit

// System colors retain contrast in light and dark appearances.
enum FitnessStyle {
    static let spacing: CGFloat = 16
    static let cornerRadius: CGFloat = 20
}

enum FitnessFeedback {
    static func success() {
        guard !UIAccessibility.isReduceMotionEnabled else { return }
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }
    static func selection() {
        guard !UIAccessibility.isReduceMotionEnabled else { return }
        UISelectionFeedbackGenerator().selectionChanged()
    }
}

struct SectionHeading: View {
    let title: String
    var subtitle: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.title3.bold()).accessibilityAddTraits(.isHeader)
            if let subtitle {
                Text(subtitle).font(.subheadline).foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct MetricCard: View {
    let title: String
    let value: Double?
    var unit = "kcal"
    let symbol: String

    var body: some View {
        MetricRow(title: title, value: value, unit: unit, symbol: symbol)
            .padding(FitnessStyle.spacing)
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .background(FitnessTheme.card,
                        in: RoundedRectangle(cornerRadius: FitnessStyle.cornerRadius))
    }
}

struct EmptyState: View {
    let title: String
    let message: String
    let symbol: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(title, systemImage: symbol).font(.headline)
                .fixedSize(horizontal: false, vertical: true)
            Text(message).font(.subheadline).foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(FitnessStyle.spacing)
        .background(FitnessTheme.card,
                    in: RoundedRectangle(cornerRadius: FitnessStyle.cornerRadius))
        .accessibilityElement(children: .combine)
    }
}

struct LoadingState: View {
    var message = "Loading your daily summary"

    var body: some View {
        ProgressView(message)
            .frame(maxWidth: .infinity)
            .padding(32)
            .accessibilityLabel(message)
    }
}

struct ActionButton: View {
    let title: String
    let symbol: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: symbol)
                .padding(.vertical, 6)
                .frame(minHeight: 32)
        }
        .buttonStyle(.borderedProminent).tint(FitnessTheme.action).foregroundStyle(.white)
    }
}

struct ErrorMessage: View {
    let title: String
    let message: String
    var retry: (() -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            EmptyState(title: title, message: message, symbol: "exclamationmark.triangle")
            if let retry {
                ActionButton(title: "Try again", symbol: "arrow.clockwise", action: retry)
            }
        }
        .accessibilityElement(children: .contain)
    }
}

/// Sheet swipes cannot silently drop a dirty draft; Cancel explains the choice.
private struct DiscardChangesModifier: ViewModifier {
    let dirty: Bool
    @Binding var requested: Bool
    let discard: () -> Void
    func body(content: Content) -> some View {
        content
            .interactiveDismissDisabled(dirty)
            .alert("Discard unsaved changes?", isPresented: $requested) {
                Button("Discard changes", role: .destructive, action: discard)
                Button("Keep editing", role: .cancel) { }
            } message: { Text("Only this unsaved draft will be discarded. Previously saved records remain.") }
    }
}

extension View {
    func confirmDiscardChanges(dirty: Bool, requested: Binding<Bool>, discard: @escaping () -> Void) -> some View {
        modifier(DiscardChangesModifier(dirty: dirty, requested: requested, discard: discard))
    }
}

/// Deterministic value comparison for Codable draft collections, never storage.
func draftFingerprint<T: Encodable>(_ value: T) -> String {
    let encoder = JSONEncoder(); encoder.outputFormatting = .sortedKeys
    return (try? encoder.encode(value).base64EncodedString()) ?? "unreadable"
}
