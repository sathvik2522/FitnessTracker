import SwiftUI
import SwiftData
import UIKit

@main
@MainActor
struct PersonalFitnessApp: App {
    private let persistence: Result<ModelContainer, Error>

    init() {
        #if DEBUG
        // UI tests use a unique temporary disk store, never the personal store.
        let arguments = ProcessInfo.processInfo.arguments
        if let index = arguments.firstIndex(of: "--nutrition-ui-test-store"),
           arguments.indices.contains(index + 1), let id = UUID(uuidString: arguments[index + 1]) {
            // Deterministic UI automation: avoid simulator animation-quiescence
            // waits. Normal launches never enter this isolated DEBUG-only path.
            UIView.setAnimationsEnabled(false)
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("NutritionUITest-\(id.uuidString).sqlite")
            persistence = Result { try AppPersistence.makeContainer(url: url) }
            return
        }
        #endif
        persistence = Result { try AppPersistence.makeContainer() }
    }

    var body: some Scene {
        WindowGroup {
            switch persistence {
            case .success(let container):
                #if DEBUG
                if ProcessInfo.processInfo.arguments.contains("--nutrition-ui-test-store") && !ProcessInfo.processInfo.arguments.contains("--with-offline-catalog") {
                    AppNavigation().modelContainer(container)
                } else { CatalogLoadingView(container: container) }
                #else
                CatalogLoadingView(container: container)
                #endif
            case .failure:
                ErrorMessage(title: "Local storage unavailable",
                             message: "PersonalFitness could not open its local data. Close and reopen the app. Your store has not been reset.")
                    .padding()
            }
        }
    }
}
