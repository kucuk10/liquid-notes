import SwiftUI
import SwiftData

struct RecentsView: View {
    @Query(sort: \Notepad.modified, order: .reverse) private var notes: [Notepad]

    var body: some View {
        NavigationStack {
            List(notes) { note in
                NavigationLink {
                    NotepadDetailView(note: note)
                } label: {
                    Text(note.title.isEmpty ? "Untitled" : note.title)
                }
            }
            .navigationTitle("Recents")
        }
    }
}
