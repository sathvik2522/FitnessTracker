import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct LocalExportDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }
    var data: Data
    init(data: Data) { self.data = data }
    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else { throw CocoaError(.fileReadCorruptFile) }
        _ = try LocalDataExport.decode(data)
        self.data = data
    }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}

struct DataExportView: View {
    @Environment(\.modelContext) private var context
    @State private var preparing = false
    @State private var exporting = false
    @State private var document: LocalExportDocument?
    @State private var error: String?
    @State private var success: String?
    @State private var count = 0
    var body: some View {
        Form {
            Section("Save a copy") {
                Button("Export local data", systemImage: "square.and.arrow.up") { prepare() }
                    .frame(minHeight: 44).disabled(preparing || exporting)
                    .accessibilityIdentifier("data.export")
                if preparing { LoadingState(message: "Preparing local export") }
                else if exporting { Label("Opening Files", systemImage: "doc.badge.arrow.up").font(.footnote).accessibilityIdentifier("data.export.opening") }
                if let success { Label(success, systemImage: "checkmark.circle").accessibilityIdentifier("data.export.success") }
                Text("The file contains personal records and is not encrypted by PersonalFitness. Choose a private location in Files.")
                    .font(.footnote).foregroundStyle(.secondary)
                Text("In-app restore is not available. Keep the app installed to retain its live database.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            Section("Protect your local records") {
                Text("Export food entries, saved foods and meals, exercises, routines, strength sets, cardio logs, manual weight history and personal goal/appearance preferences as a versioned JSON file.")
                Text("Also includes scoring configuration, preserved expenditure predictions with component totals and sources, optional workout RPE and any manually entered age/height/weight/equation profile so estimates can be reproduced. This can be sensitive; choose a private storage location.")
                Text("Includes active workouts and archived catalog items. Raw Apple Health samples, sleep records, HRV/resting-heart-rate readings and permissions are excluded. A saved mixed-source expenditure prediction may include derived Health resting/active totals.")
            }
            if let error { Section { ErrorMessage(title: "Export unavailable", message: error) } }
        }
        .fitnessScreen().navigationBarTitleDisplayMode(.inline).navigationTitle("Export local data")
        .fileExporter(isPresented: $exporting, document: document, contentType: .json,
                      defaultFilename: "PersonalFitness-\(Date.now.formatted(.iso8601.year().month().day().dateSeparator(.dash)))") { result in
            switch result {
            case .success: success = "Saved export containing \(count) records. Check the file in Files."
            case .failure(let issue): error = issue.localizedDescription
            }
        }
    }
    private func prepare() {
        guard !preparing else { return }
        preparing = true; success = nil; error = nil
        Task {
            defer { preparing = false }
            do {
                let snapshot = try LocalDataExport.capture(context: context)
                let data = try await Task.detached(priority: .userInitiated) { try snapshot.encoded() }.value
                count = snapshot.recordCount
                document = LocalExportDocument(data: data)
                exporting = true
            } catch { self.error = error.localizedDescription }
        }
    }
}
