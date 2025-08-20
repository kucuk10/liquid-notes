import SwiftUI
import SwiftData

struct NoteListsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var folders: [Folder]
    @State private var showingFolderSheet = false
    @State private var newFolderName = ""

    var body: some View {
        NavigationStack {
            List {
                Section {
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
                if !folders.isEmpty {
                    Section("Folders") {
                        ForEach(folders) { folder in
                            NavigationLink {
                                FolderDetailView(folder: folder)
                            } label: {
                                Label(folder.name, systemImage: "folder")
                            }
                        }
                    }
                }
            }
            .navigationTitle("Lists")
            .toolbar {
                #if os(macOS)
                ToolbarItem(placement: .primaryAction) {
                    Button(action: { showingFolderSheet = true }) {
                        Image(systemName: "folder.badge.plus")
                    }
                }
                #else
                ToolbarItem(placement: .topBarTrailing) {
                    Button(action: { showingFolderSheet = true }) {
                        Image(systemName: "folder.badge.plus")
                    }
                }
                #endif
            }
            .sheet(isPresented: $showingFolderSheet) {
                NavigationStack {
                    Form {
                        TextField("Folder Name", text: $newFolderName)
                    }
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Cancel") { showingFolderSheet = false }
                        }
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Add") { createFolder() }
                        }
                    }
                    .navigationTitle("New Folder")
                    .padding()
                }
            }
        }
    }

    private func createFolder() {
        guard !newFolderName.isEmpty else { return }
        let folder = Folder(name: newFolderName)
        modelContext.insert(folder)
        newFolderName = ""
        showingFolderSheet = false
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
