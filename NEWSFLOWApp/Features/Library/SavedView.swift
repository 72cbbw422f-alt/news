import SwiftUI
import SwiftData

struct SavedView: View {
    @Query(sort: \ArticleRecord.firstSeenAt, order: .reverse) private var articles: [ArticleRecord]
    @Environment(\.colorScheme) private var colorScheme

    private var savedArticles: [ArticleRecord] { articles.filter(\.isSaved) }

    var body: some View {
        NavigationStack {
            Group {
                if savedArticles.isEmpty {
                    ContentUnavailableView(
                        "Inget sparat ännu",
                        systemImage: "bookmark",
                        description: Text("Spara artiklar från läsvyn så hittar du dem här.")
                    )
                } else {
                    List(savedArticles) { article in
                        NavigationLink {
                            ArticleDetailView(article: article)
                        } label: {
                            ArticleRow(article: article)
                        }
                        .listRowBackground(NEWSFLOWTheme.surface(colorScheme))
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                }
            }
            .background(NEWSFLOWTheme.pageBackground(colorScheme))
            .navigationTitle("Sparat")
        }
    }
}
