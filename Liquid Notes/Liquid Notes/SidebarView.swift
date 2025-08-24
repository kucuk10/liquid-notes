import SwiftUI
import SwiftData

struct SidebarView: View {
    @Query(sort: \Notepad.modified, order: .reverse) private var recentNotes: [Notepad]
    @Query private var folders: [Folder]
    @Query private var notes: [Notepad]
    @State private var searchText = ""

    private var filteredRecents: [Notepad] {
        recentNotes.filter { matchesSearch($0) }
    }

    private var filteredNotes: [Notepad] {
        notes.filter { matchesSearch($0) }
    }

    var body: some View {
        NavigationSplitView {
            List {
                Section("Recents") {
                    ForEach(filteredRecents) { note in
                        NavigationLink {
                            NotepadDetailView(note: note)
                        } label: {
                            Text(title(for: note))
                        }
                    }
                }
                Section("Lists") {
                    DisclosureGroup {
                        ForEach(filteredNotes) { note in
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
                        ForEach(filteredNotes.filter { $0.type == .postIt }) { note in
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
                        ForEach(filteredNotes.filter { $0.type == .notebook }) { note in
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
                        ForEach(filteredNotes.filter { $0.type == .canvas }) { note in
                            NavigationLink {
                                NotepadDetailView(note: note)
                            } label: {
                                Text(title(for: note))
                            }
                        }
                    } label: {
                        Label("Canvases", systemImage: "scribble")
                    }
                }
                if !folders.isEmpty {
                    Section("Folders") {
                        ForEach(folders) { folder in
                            DisclosureGroup {
                                ForEach(folder.notes.filter { matchesSearch($0) }) { note in
                                    NavigationLink {
                                        NotepadDetailView(note: note)
                                    } label: {
                                        Text(title(for: note))
                                    }
                                }
                            } label: {
                                Label(folder.name, systemImage: "folder")
                            }
                        }
                    }
                }
            }
            .searchable(text: $searchText)
            .listStyle(.sidebar)
            .navigationTitle("Notes")
        } detail: {
            Text("Select a note")
        }
    }

    private func matchesSearch(_ note: Notepad) -> Bool {
        searchText.isEmpty || note.title.localizedCaseInsensitiveContains(searchText)
    }

    private func title(for note: Notepad) -> String {
        note.title.isEmpty ? "Untitled" : note.title
    }
}

