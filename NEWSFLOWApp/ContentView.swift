import SwiftUI

struct ContentView: View {
    var body: some View {
        TabView {
            TimelineView()
                .tabItem { Label("Flöde", systemImage: "text.alignleft") }
            SourcesView()
                .tabItem { Label("Källor", systemImage: "dot.radiowaves.left.and.right") }
            SavedView()
                .tabItem { Label("Sparat", systemImage: "bookmark") }
            SettingsView()
                .tabItem { Label("Inställningar", systemImage: "slider.horizontal.3") }
        }
        .tint(NEWSFLOWTheme.accent)
    }
}
