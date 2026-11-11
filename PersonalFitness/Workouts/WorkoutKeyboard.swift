import SwiftUI

/// Decimal pads have no Return key. A safe-area action strip keeps dismissal
/// reachable without relying on the keyboard ToolbarItem host's sizing.
private struct KeyboardDismissal: ViewModifier {
    @State private var visible = false
    func body(content: Content) -> some View {
        content
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if visible {
                    HStack {
                        Spacer()
                        Button("Done editing") {
                            UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                        }.frame(minHeight: 44)
                    }.padding(.horizontal).background(.bar)
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { _ in visible = true }
            .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in visible = false }
    }
}
extension View {
    func workoutKeyboardToolbar() -> some View { modifier(KeyboardDismissal()) }
}
