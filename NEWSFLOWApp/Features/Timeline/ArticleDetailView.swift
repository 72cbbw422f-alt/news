import SwiftUI
import SwiftData

struct ArticleDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorScheme) private var colorScheme
    @Bindable var article: ArticleRecord

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

                if let summary = article.summary, !summary.isEmpty {
                    Text(summary)
                        .font(.system(.body, design: .serif))
                        .lineSpacing(6)
                        .foregroundStyle(NEWSFLOWTheme.primaryText(colorScheme))
                } else {
                    ContentUnavailableView("Ingen artikeltext", systemImage: "doc.text", description: Text("Källan tillhandahåller ingen sammanfattning. Öppna originalartikeln för att läsa vidare."))
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
