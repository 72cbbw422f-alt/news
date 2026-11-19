import SwiftUI
import SwiftData

struct ArticleDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorScheme) private var colorScheme
    @Bindable var article: ArticleRecord
    @State private var isLoadingFullText = false
    @State private var extractionMessage: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text(article.source?.title ?? "NEWSFLOW")
                    .font(.caption.weight(.bold))
                    .textCase(.uppercase)
                    .tracking(1.2)
                    .foregroundStyle(NEWSFLOWTheme.accent)

                Text(article.title)
                    .font(.system(size: 31, weight: .semibold, design: .serif))
                    .foregroundStyle(NEWSFLOWTheme.primaryText(colorScheme))
                    .fixedSize(horizontal: false, vertical: true)

                HStack {
                    if let author = article.author { Text(author) }
                    if let date = article.publishedAt {
                        Text(date, style: .date)
                    }
                }
                .font(.caption)
                .foregroundStyle(NEWSFLOWTheme.secondaryInk)

                Divider()

                if let fullText = article.fullText, !fullText.isEmpty {
                    Text(fullText)
                        .font(.system(.body, design: .serif))
                        .lineSpacing(7)
                        .foregroundStyle(NEWSFLOWTheme.primaryText(colorScheme))
                        .textSelection(.enabled)
                    Label("Sparad för offlineläsning", systemImage: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(NEWSFLOWTheme.secondaryInk)
                } else {
                    if let summary = article.summary, !summary.isEmpty {
                        Text(summary)
                            .font(.system(.body, design: .serif))
                            .lineSpacing(6)
                            .foregroundStyle(NEWSFLOWTheme.primaryText(colorScheme))
                    } else {
                        ContentUnavailableView("Ingen artikeltext", systemImage: "doc.text", description: Text("Källan tillhandahåller ingen sammanfattning. Försök hämta artikeltext eller öppna originalkällan."))
                    }

                    Button {
                        Task { await fetchFullText() }
                    } label: {
                        HStack {
                            if isLoadingFullText { ProgressView().tint(.white) }
                            else { Image(systemName: "text.page") }
                            Text(isLoadingFullText ? "Hämtar artikeltext…" : "Hämta fullständig artikeltext")
                        }
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(NEWSFLOWTheme.accent)
                    .disabled(isLoadingFullText || article.canonicalURLString == nil)

                    if let extractionMessage {
                        Text(extractionMessage)
                            .font(.caption)
                            .foregroundStyle(NEWSFLOWTheme.secondaryInk)
                    }
                }

                if let rawURL = article.canonicalURLString, let url = URL(string: rawURL) {
                    Link(destination: url) {
                        Label("Läs hos originalkällan", systemImage: "arrow.up.right")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(NEWSFLOWTheme.accent)
                }
            }
            .padding(22)
            .frame(maxWidth: 680, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .background(NEWSFLOWTheme.pageBackground(colorScheme))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button {
                    article.isSaved.toggle()
                    try? modelContext.save()
                } label: {
                    Image(systemName: article.isSaved ? "bookmark.fill" : "bookmark")
                }
                .accessibilityLabel(article.isSaved ? "Ta bort bokmärke" : "Spara artikel")
                if let rawURL = article.canonicalURLString, let url = URL(string: rawURL) {
                    ShareLink(item: url) {
                        Image(systemName: "square.and.arrow.up")
                    }
                }
            }
        }
        .onAppear {
            article.isRead = true
            try? modelContext.save()
        }
    }
}
    
    @MainActor
    private func fetchFullText() async {
        guard let rawURL = article.canonicalURLString,
              let url = URL(string: rawURL),
              FeedSource.validatedHTTPURL(url) else {
            extractionMessage = "Artikeln saknar en giltig webbadress."
            return
        }

        isLoadingFullText = true
        extractionMessage = nil
        defer { isLoadingFullText = false }

        do {
            let client = FeedHTTPClient(maximumResponseBytes: 3 * 1_024 * 1_024, timeout: 20)
            let data = try await client.fetch(url)
            guard let text = ArticleTextExtractor.extract(from: data) else {
                extractionMessage = "NEWSFLOW hittade ingen tydlig artikeltext. Prova originalkällan."
                return
            }
            article.fullText = text
            try modelContext.save()
        } catch {
            extractionMessage = "Det gick inte att hämta artikeln just nu. Kontrollera anslutningen eller öppna originalkällan."
        }
    }

