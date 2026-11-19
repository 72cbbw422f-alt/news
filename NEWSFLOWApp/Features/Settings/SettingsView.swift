import SwiftUI
import SwiftData
import UniformTypeIdentifiers
import NEWSFLOWCore

struct SettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorScheme) private var colorScheme
    @Query(sort: \\FeedSourceRecord.title) private var sources: [FeedSourceRecord]
    @State private var isImportingOPML = false
    @State private var isExportingOPML = false
    @State private var exportDocument = OPMLDocument(data: Data())
    @State private var statusMessage: String?

    var body: some View {
        NavigationStack {
            List {
                Section("Läsupplevelse") {
                    Label("Utseende följer systemet", systemImage: "circle.lefthalf.filled")
                    Label("Lokal lagring", systemImage: "internaldrive")
                    Label("RSS och Atom", systemImage: "dot.radiowaves.left.and.right")
                }
                Section {
                    Button {
                        isImportingOPML = true
                    } label: {
                        Label("Importera OPML", systemImage: "square.and.arrow.down")
                    }
                    .disabled(false)

                    Button {
                        prepareOPMLExport()
                    } label: {
                        Label("Exportera prenumerationer", systemImage: "square.and.arrow.up")
                    }
                    .disabled(sources.isEmpty)

                    Text("Flytta dina RSS-prenumerationer mellan NEWSFLOW och andra läsappar. Mappstrukturen följer med.")
                        .font(.footnote)
                        .foregroundStyle(NEWSFLOWTheme.secondaryInk)
                } header: {
                    Text("Prenumerationer")
                } footer: {
                    Text("\(sources.count) källor i biblioteket")
                }

                Section("Om NEWSFLOW") {
                    LabeledContent("Version", value: "0.1.0 · Foundation")
                    LabeledContent("Plattform", value: "iOS 17 eller senare")
                    Link(destination: URL(string: "https://github.com/72cbbw422f-alt/news")!) {
                        Label("Projekt på GitHub", systemImage: "chevron.left.forwardslash.chevron.right")
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(NEWSFLOWTheme.pageBackground(colorScheme))
            .navigationTitle("Inställningar")
            .fileImporter(
                isPresented: $isImportingOPML,
                allowedContentTypes: [.xml],
                allowsMultipleSelection: false,
                onCompletion: importOPML
            )
            .fileExporter(
                isPresented: $isExportingOPML,
                document: exportDocument,
                contentType: .xml,
                defaultFilename: "NEWSFLOW-prenumerationer",
                onCompletion: { result in
                    if case .failure(let error) = result {
                        statusMessage = "Exporten misslyckades: \\(error.localizedDescription)"
                    }
                }
            )
            .alert("Prenumerationer", isPresented: Binding(
                get: { statusMessage != nil },
                set: { if !$0 { statusMessage = nil } }
            )) {
                Button("OK") { statusMessage = nil }
            } message: {
                Text(statusMessage ?? "")
            }
        }
    }

    private func prepareOPMLExport() {
        let subscriptions = sources.compactMap { source -> OPMLSubscription? in
            guard let feedURL = URL(string: source.feedURLString) else { return nil }
            let websiteURL = source.websiteURLString.flatMap(URL.init(string:))
            let folderPath = source.folderName?
                .split(separator: "/")
                .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty } ?? []
            return OPMLSubscription(
                title: source.title,
                feedURL: feedURL,
                websiteURL: websiteURL,
                folderPath: folderPath
            )
        }
        exportDocument = OPMLDocument(data: OPMLCodec.export(subscriptions))
        isExportingOPML = true
    }

    private func importOPML(result: Result<[URL], Error>) {
        do {
            let urls = try result.get()
            guard let url = urls.first else { return }
            let didAccess = url.startAccessingSecurityScopedResource()
            defer { if didAccess { url.stopAccessingSecurityScopedResource() } }

            let subscriptions = try OPMLCodec.parse(data: Data(contentsOf: url))
            var knownURLs = Set(sources.map { $0.feedURLString.lowercased() })
            var addedCount = 0

            for subscription in subscriptions {
                let feedURL = subscription.feedURL.absoluteString
                guard knownURLs.insert(feedURL.lowercased()).inserted else { continue }
                let folderName = subscription.folderPath.isEmpty
                    ? nil
                    : subscription.folderPath.joined(separator: " / ")
                let source = FeedSourceRecord(
                    title: subscription.title,
                    feedURLString: feedURL,
                    websiteURLString: subscription.websiteURL?.absoluteString,
                    folderName: folderName
                )
                modelContext.insert(source)
                addedCount += 1
            }

            try modelContext.save()
            statusMessage = addedCount == 0
                ? "Inga nya källor att importera. Dubbletter hoppades över."
                : "\\(addedCount) källor importerades. Uppdatera dem under fliken Källor för att hämta artiklar."
        } catch {
            statusMessage = "Importen misslyckades: \\(error.localizedDescription)"
        }
    }
}

private struct OPMLDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.xml] }
    var data: Data

    init(data: Data) {
        self.data = data
    }

    init(configuration: ReadConfiguration) throws {
        data = configuration.file.regularFileContents ?? Data()
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}
