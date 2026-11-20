import SwiftUI
import SwiftData

/// The second column: the notepads in the selected collection.
struct NotepadListView: View {
    let collection: LibraryCollection
    @Binding var selection: Notepad?
    @Binding var searchText: String
    let actions: LibraryActions

    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Notepad.modified, order: .reverse) private var allNotepads: [Notepad]
    @Query(sort: \Folder.name) private var folders: [Folder]

    private var isSearching: Bool {
        !searchText.trimmingCharacters(in: .whitespaces).isEmpty
    }

    /// Searching looks through every notepad, like Apple Notes.
    private var visibleNotepads: [Notepad] {
        guard isSearching else { return allNotepads.filter(collection.contains) }
        let query = searchText.trimmingCharacters(in: .whitespaces)
        return allNotepads.filter {
            $0.title.localizedStandardContains(query) || $0.plainText.localizedStandardContains(query)
        }
    }

    var body: some View {
        let notepads = visibleNotepads

        List(selection: $selection) {
            if collection.groupsByType && !isSearching {
                ForEach(NotepadType.allCases) { type in
                    let group = notepads.filter { $0.type == type }
                    if !group.isEmpty {
                        Section(type.pluralName) { rows(group) }
                    }
                }
            } else {
                rows(notepads)
            }
        }
        .overlay {
            if notepads.isEmpty {
                if isSearching {
                    ContentUnavailableView.search(text: searchText)
                } else {
                    ContentUnavailableView {
                        Label("No \(collection.preferredType.pluralName)", systemImage: collection.systemImageName)
                    } description: {
                        Text("Create a note, notebook or canvas to get started.")
                    } actions: {
                        Button("New \(collection.preferredType.displayName)") {
                            actions.newNotepad(collection.preferredType)
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }
            }
        }
        .navigationTitle(isSearching ? String(localized: "Search") : collection.title)
        .searchable(text: $searchText, prompt: "Search all notepads")
        #if os(macOS)
        .navigationSplitViewColumnWidth(min: 240, ideal: 300)
        #endif
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                NewNotepadMenu(preferredType: collection.preferredType, actions: actions)
            }
        }
    }

    private func rows(_ notepads: [Notepad]) -> some View {
        ForEach(notepads) { notepad in
            NavigationLink(value: notepad) {
                NotepadRow(notepad: notepad, showsFolder: collection.folder == nil)
            }
            .contextMenu { contextMenu(for: notepad) }
            .swipeActions {
                Button("Delete", systemImage: "trash", role: .destructive) { delete(notepad) }
            }
        }
    }

    @ViewBuilder
    private func contextMenu(for notepad: Notepad) -> some View {
        Menu("Move to Folder", systemImage: "folder") {
            Button("No Folder") { notepad.folder = nil }
                .disabled(notepad.folder == nil)
            Divider()
            ForEach(folders) { folder in
                Button(folder.name) { notepad.folder = folder }
                    .disabled(notepad.folder == folder)
            }
        }
        Divider()
        Button("Delete", systemImage: "trash", role: .destructive) { delete(notepad) }
    }

    private func delete(_ notepad: Notepad) {
        if selection == notepad { selection = nil }
        modelContext.delete(notepad)
    }
}

/// The "New" toolbar button. Tapping creates the preferred type; the menu offers everything else.
struct NewNotepadMenu: View {
    let preferredType: NotepadType
    let actions: LibraryActions

    var body: some View {
        Menu {
            ForEach(NotepadType.allCases) { type in
                Button {
                    actions.newNotepad(type)
                } label: {
                    Label(
                        type == .notebook ? "New \(type.displayName)…" : "New \(type.displayName)",
                        systemImage: type.systemImageName
                    )
                }
            }
            Divider()
            Button("Import PDF as Notebook…", systemImage: "square.and.arrow.down") {
                actions.importPDF()
            }
        } label: {
            Label("New \(preferredType.displayName)", systemImage: "square.and.pencil")
        } primaryAction: {
            actions.newNotepad(preferredType)
        }
    }
}

/// A notepad in the library list.
struct NotepadRow: View {
    let notepad: Notepad
    var showsFolder = true

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: notepad.type.systemImageName)
                .font(.title3)
                .foregroundStyle(notepad.type.tint)
                .frame(width: 28)
                .accessibilityLabel(notepad.type.displayName)

            VStack(alignment: .leading, spacing: 2) {
                Text(notepad.displayTitle)
                    .font(.headline)
                    .lineLimit(1)

                HStack(spacing: 6) {
                    Text(Self.dateText(for: notepad.modified))
                    Text(notepad.summary)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                .font(.subheadline)

                if showsFolder, let folder = notepad.folder {
                    Label(folder.name, systemImage: "folder")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 2)
    }

    /// Times for today, dates otherwise, like Apple Notes.
    static func dateText(for date: Date) -> String {
        if Calendar.current.isDateInToday(date) {
            date.formatted(date: .omitted, time: .shortened)
        } else {
            date.formatted(date: .numeric, time: .omitted)
        }
    }
}
