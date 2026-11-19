import SwiftUI
import SwiftData

struct TimelineView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \\ArticleRecord.firstSeenAt, order: .reverse) private var articles: [ArticleRecord]
    @Environment(\.colorScheme) private var colorScheme
    @State private var searchText = ""
    @State private var scope: TimelineScope = .all

    private var unreadCount: Int { articles.filter { !$0.isRead }.count }

    private var filteredArticles: [ArticleRecord] {
        articles.filter { article in
            let matchesScope: Bool
            switch scope {
            case .all: matchesScope = true
            case .unread: matchesScope = !article.isRead
            case .saved: matchesScope = article.isSaved
            }
            guard matchesScope else { return false }
            let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !query.isEmpty else { return true }
            return article.title.localizedCaseInsensitiveContains(query)
                || (article.summary?.localizedCaseInsensitiveContains(query) ?? false)
                || (article.author?.localizedCaseInsensitiveContains(query) ?? false)
                || (article.source?.title.localizedCaseInsensitiveContains(query) ?? false)
        }
    }

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
                            Picker("Visa", selection: $scope) {
                                ForEach(TimelineScope.allCases) { option in
                                    Text(option.title).tag(option)
                                }
                            }
                            .pickerStyle(.segmented)
                            .listRowBackground(Color.clear)
                        }

                        Section {
                            if filteredArticles.isEmpty {
                                ContentUnavailableView.search(text: searchText.isEmpty ? scope.emptySearchTerm : searchText)
                                    .listRowBackground(Color.clear)
                            } else {
                                ForEach(filteredArticles) { article in
                                    NavigationLink {
                                        ArticleDetailView(article: article)
                                    } label: {
                                        ArticleRow(article: article)
                                    }
                                    .listRowBackground(NEWSFLOWTheme.surface(colorScheme))
                                }
                            }
                        } header: {
                            HStack {
                                Text(scope.sectionTitle)
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
            .searchable(text: $searchText, prompt: "Sök artiklar och källor")
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

private enum TimelineScope: String, CaseIterable, Identifiable {
    case all
    case unread
    case saved

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: "Alla"
        case .unread: "Olästa"
        case .saved: "Sparade"
        }
    }

    var sectionTitle: String {
        switch self {
        case .all: "SENASTE"
        case .unread: "OLÄSTA"
        case .saved: "SPARADE"
        }
    }

    var emptySearchTerm: String {
        switch self {
        case .all: "artiklar"
        case .unread: "olästa artiklar"
        case .saved: "sparade artiklar"
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
