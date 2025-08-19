import SwiftUI
import SwiftData

struct NotepadDetailView: View {
    @Bindable var note: Notepad

    var body: some View {
        TextEditor(text: $note.content)
            .navigationTitle(note.title.isEmpty ? "Untitled" : note.title)
            .padding()
    }
}
