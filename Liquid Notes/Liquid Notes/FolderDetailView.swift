import SwiftUI
import SwiftData

struct FolderDetailView: View {
    @Bindable var folder: Folder

    var body: some View {
        List(folder.notes) { note in
            NavigationLink {
                NotepadDetailView(note: note)
            } label: {
                Text(note.title.isEmpty ? "Untitled" : note.title)
            }
        }
        .navigationTitle(folder.name)
    }
}
