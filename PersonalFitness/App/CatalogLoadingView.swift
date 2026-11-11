import SwiftUI
import SwiftData

/// The app stays responsive during the background import. A failure permits
/// retry or access to existing records; it never resets the personal container.
struct CatalogLoadingView: View {
    let container: ModelContainer
    @State private var ready = false
    @State private var loading = false
    @State private var error: String?
    var body: some View {
        Group {
            if ready { AppNavigation().modelContainer(container) }
            else {
                VStack(spacing: 20) {
                    if loading { LoadingState(message: "Preparing offline food and exercise libraries") }
                    if let error {
                        ErrorMessage(title: "Offline libraries unavailable", message: error)
                        Button("Retry library import") { Task { await load() } }.buttonStyle(.borderedProminent).tint(FitnessTheme.action).foregroundStyle(.white)
                        Button("Use existing records") { ready = true }.frame(minHeight: 44)
                    }
                    Text("Everything stays on this iPhone. Imports preserve your personal entries and workout history.").font(.footnote)
                }.padding()
            }
        }
        .task { if !ready && !loading { await load() } }
    }
    @MainActor private func load() async {
        guard !loading else { return }
        loading = true; error = nil
        defer { loading = false }
        do {
            let urls = try ["foods-v1", "exercises-v1"].map { name in
                guard let url = Bundle.main.url(forResource: name, withExtension: "json", subdirectory: "Catalogs") else { throw CatalogError.missingResource }
                return url
            }
            // The ModelActor must be initialized here, off the main actor, so
            // its context's executor cannot inherit the UI executor.
            _ = try await Task.detached(priority: .userInitiated) {
                try await CatalogImporter(modelContainer: container).run(urls: urls)
            }.value
            ready = true
        } catch { self.error = error.localizedDescription }
    }
}
