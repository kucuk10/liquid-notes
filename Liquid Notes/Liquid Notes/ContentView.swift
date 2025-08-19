import SwiftUI
import SwiftData

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var showCreationDialog = false

    var body: some View {
        TabView {
            RecentsView()
                .tabItem { Label("Recents", systemImage: "clock") }
            NoteListsView()
                .tabItem { Label("Lists", systemImage: "folder") }
            SearchView()
                .tabItem { Label("Search", systemImage: "magnifyingglass") }
        }
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button(action: { showCreationDialog = true }) {
                    Image(systemName: "square.and.pencil")
                }
                Button(action: {}) {
                    Image(systemName: "gearshape")
                }
            }
        }
        .confirmationDialog("New Notepad", isPresented: $showCreationDialog) {
            ForEach(NotepadType.allCases) { type in
                Button(type.rawValue) { createNote(type) }
            }
        }
    }

    private func createNote(_ type: NotepadType) {
        let newNote = Notepad(title: "", type: type)
        modelContext.insert(newNote)
    }
}
