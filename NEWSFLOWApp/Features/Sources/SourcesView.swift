import SwiftUI
import SwiftData
import NEWSFLOWCore

struct SourcesView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \FeedSourceRecord.title) private var sources: [FeedSourceRecord]
    @Environment(\.colorScheme) private var colorScheme
    @State private var showingAddFeed = false
    @State private var refreshingIDs: Set<UUID> = []

    var body: some View {
        NavigationStack {
            Group {
                if sources.isEmpty {
                    ContentUnavailableView {
                        Label("Inga källor ännu", systemImage: "dot.radiowaves.left.and.right")
                    } description: {
                        Text("Lägg till en RSS- eller Atom-adress för att börja bygga ditt flöde.")
                    } actions: {
                        Button("Lägg till källa") { showingAddFeed = true }
                            .buttonStyle(.borderedProminent)
                            .tint(NEWSFLOWTheme.accent)
                    }
                } else {
                    List {
                        ForEach(sources) { source in
                            HStack(spacing: 12) {
                                Image(systemName: "dot.radiowaves.left.and.right")
                                    .font(.title3)
                                    .foregroundStyle(NEWSFLOWTheme.accent)
                                    .frame(width: 38, height: 38)
                                    .background(NEWSFLOWTheme.accent.opacity(0.10), in: RoundedRectangle(cornerRadius: 11))
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(source.title).font(.headline)
                                    Text(source.feedURLString)
                                        .font(.caption)
                                        .foregroundStyle(NEWSFLOWTheme.secondaryInk)
                                        .lineLimit(1)
                                    if let error = source.lastError {
                                        Text(error).font(.caption2).foregroundStyle(.red).lineLimit(2)
                                    } else if let date = source.lastSuccessAt {
                                        Text("Uppdaterad \(date, style: .relative)")
                                            .font(.caption2)
                                            .foregroundStyle(NEWSFLOWTheme.secondaryInk)
                                    }
                                }
                                Spacer()
                                if refreshingIDs.contains(source.id) {
                                    ProgressView()
                                } else {
                                    Button {
                                        Task { await refresh(source) }
                                    } label: {
                                        Image(systemName: "arrow.clockwise")
                                    }
                                    .accessibilityLabel("Uppdatera \(source.title)")
                                }
                            }
                            .padding(.vertical, 5)
                            .listRowBackground(NEWSFLOWTheme.surface(colorScheme))
                        }
                        .onDelete(perform: deleteSources)
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                }
            }
            .background(NEWSFLOWTheme.pageBackground(colorScheme))
            .navigationTitle("Källor")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showingAddFeed = true } label: { Image(systemName: "plus") }
                        .accessibilityLabel("Lägg till källa")
                }
                ToolbarItem(placement: .topBarLeading) {
                    if !sources.isEmpty {
                        EditButton()
                    }
                }
            }
            .sheet(isPresented: $showingAddFeed) {
                AddFeedSheet()
            }
        }
    }

    private func deleteSources(at offsets: IndexSet) {
        for index in offsets { modelContext.delete(sources[index]) }
        try? modelContext.save()
    }

    @MainActor
    private func refresh(_ record: FeedSourceRecord) async {
        guard let source = record.domain else { return }
        refreshingIDs.insert(record.id)
        defer { refreshingIDs.remove(record.id) }
        record.lastAttemptAt = .now
        do {
            let result = try await FeedRefreshService().refresh(source: source)
            let existing = record.articles.map(\.domain)
            let merged = ArticleMerger.merge(existing: existing, incoming: result.articles)
            let existingByID = Dictionary(uniqueKeysWithValues: record.articles.map { ($0.id, $0) })
            for article in merged {
                if let stored = existingByID[article.id] {
                    stored.apply(article)
                } else {
                    let stored = ArticleRecord(domain: article, source: record)
                    modelContext.insert(stored)
                    record.articles.append(stored)
                }
            }
            if let title = result.sourceTitle, !title.isEmpty { record.title = title }
            record.websiteURLString = result.websiteURL?.absoluteString ?? record.websiteURLString
            record.lastSuccessAt = result.fetchedAt
            record.lastError = nil
            try modelContext.save()
        } catch {
            record.lastError = error.localizedDescription
            try? modelContext.save()
        }
    }
}

private struct AddFeedSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @State private var address = ""
    @State private var isAdding = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("RSS- eller Atom-adress") {
                    TextField("https://exempel.se/feed.xml", text: $address)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }
                Section {
                    Text("NEWSFLOW hämtar flödet och sparar artiklarna lokalt på enheten.")
                        .font(.footnote)
                        .foregroundStyle(NEWSFLOWTheme.secondaryInk)
                }
                if let errorMessage {
                    Section {
                        Text(errorMessage).foregroundStyle(.red)
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(NEWSFLOWTheme.pageBackground(colorScheme))
            .navigationTitle("Lägg till källa")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Avbryt") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        Task { await addFeed() }
                    } label: {
                        if isAdding { ProgressView() } else { Text("Lägg till") }
                    }
                    .disabled(isAdding || address.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }

    @MainActor
    private func addFeed() async {
        let trimmed = address.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed), FeedSource.validatedHTTPURL(url) else {
            errorMessage = "Ange en giltig adress som börjar med http:// eller https://."
            return
        }

        isAdding = true
        errorMessage = nil
        defer { isAdding = false }

        let source = FeedSource(title: url.host ?? "Ny källa", feedURL: url)
        do {
            let result = try await FeedRefreshService().refresh(source: source)
            let record = FeedSourceRecord(domain: FeedSource(
                id: source.id,
                title: result.sourceTitle ?? source.title,
                feedURL: source.feedURL,
                websiteURL: result.websiteURL
            ))
            record.lastAttemptAt = result.fetchedAt
            record.lastSuccessAt = result.fetchedAt
            modelContext.insert(record)
            for article in result.articles {
                let articleRecord = ArticleRecord(domain: article, source: record)
                modelContext.insert(articleRecord)
                record.articles.append(articleRecord)
            }
            try modelContext.save()
            dismiss()
        } catch {
            errorMessage = "Kunde inte läsa flödet: \(error.localizedDescription)"
        }
    }
}
