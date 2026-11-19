import SwiftUI
import SwiftData

@main
struct NEWSFLOWApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                .modelContainer(for: [FeedSourceRecord.self, ArticleRecord.self])
        }
    }
}
