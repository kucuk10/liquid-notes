import SwiftUI
import SwiftData

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var showCreationDialog = false

    var body: some View {
        Group {
            #if os(macOS)
            SidebarView()
            #else
            if horizontalSizeClass == .regular {
                SidebarView()
            } else {
                tabInterface
            }
            #endif
        }
        .toolbar {
            #if os(macOS)
            ToolbarItemGroup(placement: .primaryAction) {
                Button(action: { showCreationDialog = true }) {
                    Image(systemName: "square.and.pencil")
                }
                Button(action: {}) {
                    Image(systemName: "gearshape")
                }
            }
            #else
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button(action: { showCreationDialog = true }) {
                    Image(systemName: "square.and.pencil")
                }
                Button(action: {}) {
                    Image(systemName: "gearshape")
                }
            }
            #endif
        }
        .confirmationDialog("New Notepad", isPresented: $showCreationDialog) {
            ForEach(NotepadType.allCases) { type in
                Button { createNote(type) } label: {
                    Label(type.rawValue, systemImage: type.systemImageName)
                }
            }
            Button("Cancel", role: .cancel) { }
        }
    }

    private var tabInterface: some View {
        TabView {
            RecentsView()
                .tabItem { Label("Recents", systemImage: "clock") }
            NoteListsView()
                .tabItem { Label("Lists", systemImage: "folder") }
            SearchView()
                .tabItem { Label("Search", systemImage: "magnifyingglass") }
        }
    }

    private func createNote(_ type: NotepadType) {
        let newNote = Notepad(title: "", type: type)
        modelContext.insert(newNote)
    }
}
