import SwiftUI
import SwiftData

struct TimelineView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \ArticleRecord.firstSeenAt, order: .reverse) private var articles: [ArticleRecord]
    @Query(sort: \FeedSourceRecord.title) private var sources: [FeedSourceRecord]
    @Environment(\.colorScheme) private var colorScheme

    private var unreadCount: Int { articles.filter { !$0.isRead }.count }

    var body: some View {
        NavigationStack {
            Group {
                if articles.isEmpty {
                    ContentUnavailableView {
                        Label("Ditt flöde väntar", systemImage: "text.alignleft")
                    } description: {
                        Text("Lägg till dina första RSS-källor så samlas artiklarna här.")
                    } actions: {
                        NavigationLink("Hantera källor") { SourcesView() }
                            .buttonStyle(.borderedProminent)
                            .tint(NEWSFLOWTheme.accent)
                    }
                } else {
                    List {
                        Section {
                            ForEach(articles) { article in
                                NavigationLink {
                                    ArticleDetailView(article: article)
                                } label: {
                                    ArticleRow(article: article)
                                }
                                .listRowBackground(NEWSFLOWTheme.surface(colorScheme))
                            }
                        } header: {
                            HStack {
                                Text("SENASTE")
                                Spacer()
                                Text("\(unreadCount) olästa")
                                    .textCase(nil)
                                    .foregroundStyle(NEWSFLOWTheme.secondaryInk)
                            }
                        }
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                }
            }
            .background(NEWSFLOWTheme.pageBackground(colorScheme))
            .navigationTitle("NEWSFLOW")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        for article in articles { article.isRead = true }
                        try? modelContext.save()
                    } label: {
                        Image(systemName: "checkmark.circle")
                    }
                    .disabled(unreadCount == 0)
                    .accessibilityLabel("Markera alla som lästa")
                }
            }
        }
    }
}

struct ArticleRow: View {
    let article: ArticleRecord
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 6) {
                Circle()
                    .fill(article.isRead ? Color.clear : NEWSFLOWTheme.accent)
                    .frame(width: 7, height: 7)
                Text(article.source?.title ?? "Okänd källa")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(NEWSFLOWTheme.secondaryInk)
                Spacer()
                if article.isSaved {
                    Image(systemName: "bookmark.fill")
                        .font(.caption)
                        .foregroundStyle(NEWSFLOWTheme.accent)
                }
                Text(article.publishedAt ?? article.firstSeenAt, style: .relative)
                    .font(.caption2)
                    .foregroundStyle(NEWSFLOWTheme.secondaryInk)
            }
            Text(article.title)
                .font(.system(.body, design: .serif).weight(article.isRead ? .regular : .semibold))
                .foregroundStyle(NEWSFLOWTheme.primaryText(colorScheme))
                .fixedSize(horizontal: false, vertical: true)
            if let summary = article.summary, !summary.isEmpty {
                Text(summary)
                    .font(.subheadline)
                    .foregroundStyle(NEWSFLOWTheme.secondaryInk)
                    .lineLimit(2)
            }
        }
        .padding(.vertical, 7)
        .accessibilityElement(children: .combine)
    }
}
