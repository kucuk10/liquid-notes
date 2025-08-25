import SwiftUI
import SwiftData

struct SidebarView: View {
    @Query(sort: \Notepad.modified, order: .reverse) private var recentNotes: [Notepad]
    @Query private var folders: [Folder]
    @Query private var notes: [Notepad]

    var body: some View {
        NavigationSplitView {
            List {
                NavigationLink {
                    SearchView()
                } label: {
                    Label("Search", systemImage: "magnifyingglass")
                }
                Section {
                    ForEach(recentNotes) { note in
                        NavigationLink {
                            NotepadDetailView(note: note)
                        } label: {
                            Text(title(for: note))
                        }
                    }
                } header: {
                    NavigationLink {
                        RecentsView()
                    } label: {
                        Text("Recents")
                    }
                }
                Section {
                    DisclosureGroup {
                        ForEach(notes) { note in
                            NavigationLink {
                                NotepadDetailView(note: note)
                            } label: {
                                Text(title(for: note))
                            }
                        }
                    } label: {
                        Label("All Notes", systemImage: "tray.full")
                    }
                    DisclosureGroup {
                        ForEach(notes.filter { $0.type == .postIt }) { note in
                            NavigationLink {
                                NotepadDetailView(note: note)
                            } label: {
                                Text(title(for: note))
                            }
                        }
                    } label: {
                        Label("Post-It Notes", systemImage: "note.text")
                    }
                    DisclosureGroup {
                        ForEach(notes.filter { $0.type == .notebook }) { note in
                            NavigationLink {
                                NotepadDetailView(note: note)
                            } label: {
                                Text(title(for: note))
                            }
                        }
                    } label: {
                        Label("Notebooks", systemImage: "book.closed")
                    }
                    DisclosureGroup {
                        ForEach(notes.filter { $0.type == .canvas }) { note in
                            NavigationLink {
                                NotepadDetailView(note: note)
                            } label: {
                                Text(title(for: note))
                            }
                        }
                    } label: {
                        Label("Canvases", systemImage: "scribble")
                    }
                } header: {
                    NavigationLink {
                        NoteListsView()
                    } label: {
                        Text("Lists")
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
            .listStyle(.sidebar)
            .navigationTitle("Notes")
        } detail: {
            Text("Select a note")
        }
    }

    private func title(for note: Notepad) -> String {
        note.title.isEmpty ? "Untitled" : note.title
    }
}

