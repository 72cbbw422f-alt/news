import SwiftUI

struct SettingsView: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        NavigationStack {
            List {
                Section("Läsupplevelse") {
                    Label("Utseende följer systemet", systemImage: "circle.lefthalf.filled")
                    Label("Lokal lagring", systemImage: "internaldrive")
                    Label("RSS och Atom", systemImage: "dot.radiowaves.left.and.right")
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
        }
    }
}
