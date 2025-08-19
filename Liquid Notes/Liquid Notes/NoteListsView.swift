import SwiftUI
import SwiftData

struct NoteListsView: View {
    @Query private var allNotes: [Notepad]

    var body: some View {
        NavigationStack {
            List {
                NavigationLink {
                    NotepadListView(filter: nil)
                } label: {
                    Label("All Notes", systemImage: "tray.full")
                }
                NavigationLink {
                    NotepadListView(filter: .postIt)
                } label: {
                    Label("Post-It Notes", systemImage: "note.text")
                }
                NavigationLink {
                    NotepadListView(filter: .notebook)
                } label: {
                    Label("Notebooks", systemImage: "book.closed")
                }
                NavigationLink {
                    NotepadListView(filter: .canvas)
                } label: {
                    Label("Canvases", systemImage: "scribble")
                }
            }
            .navigationTitle("Lists")
        }
    }
}

struct NotepadListView: View {
    var filter: NotepadType?
    @Query private var notes: [Notepad]

    init(filter: NotepadType?) {
        self.filter = filter
        if let filter = filter {
            _notes = Query(filter: #Predicate { $0.type == filter })
        } else {
            _notes = Query()
        }
    }

    var body: some View {
        List(notes) { note in
            NavigationLink {
                NotepadDetailView(note: note)
            } label: {
                Text(note.title.isEmpty ? "Untitled" : note.title)
            }
        }
        .navigationTitle(filter?.rawValue ?? "All Notes")
    }
}
