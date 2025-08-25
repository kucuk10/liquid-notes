import SwiftUI
import SwiftData

struct NoteListsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var folders: [Folder]
    @Query private var notes: [Notepad]
    @State private var showingFolderSheet = false
    @State private var newFolderName = ""

    private var postItNotes: [Notepad] { notes.filter { $0.type == .postIt } }
    private var notebookNotes: [Notepad] { notes.filter { $0.type == .notebook } }
    private var canvasNotes: [Notepad] { notes.filter { $0.type == .canvas } }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    DisclosureGroup {
                        ForEach(notes) { note in
                            NavigationLink {
                                NotepadDetailView(note: note)
                            } label: {
                                Text(note.title.isEmpty ? "Untitled" : note.title)
                            }
                        }
                    } label: {
                        Label("All Notes", systemImage: "tray.full")
                    }
                    DisclosureGroup {
                        ForEach(postItNotes) { note in
                            NavigationLink {
                                NotepadDetailView(note: note)
                            } label: {
                                Text(note.title.isEmpty ? "Untitled" : note.title)
                            }
                        }
                    } label: {
                        Label("Post-It Notes", systemImage: "note.text")
                    }
                    DisclosureGroup {
                        ForEach(notebookNotes) { note in
                            NavigationLink {
                                NotepadDetailView(note: note)
                            } label: {
                                Text(note.title.isEmpty ? "Untitled" : note.title)
                            }
                        }
                    } label: {
                        Label("Notebooks", systemImage: "book.closed")
                    }
                    DisclosureGroup {
                        ForEach(canvasNotes) { note in
                            NavigationLink {
                                NotepadDetailView(note: note)
                            } label: {
                                Text(note.title.isEmpty ? "Untitled" : note.title)
                            }
                        }
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

