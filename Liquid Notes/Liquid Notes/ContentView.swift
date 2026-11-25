import SwiftUI
import SwiftData

/// A three-column layout like Apple Notes: collections, notepads, editor.
/// On iPhone the split view collapses into a navigation stack automatically.
struct ContentView: View {
    @Environment(\.modelContext) private var modelContext

    @State private var collection: LibraryCollection? = .all
    @State private var selectedNotepad: Notepad?
    /// Start with the library visible, so portrait iPad doesn't open to an empty editor.
    @State private var columnVisibility = NavigationSplitViewVisibility.all
    @State private var searchText = ""

    @State private var isCreatingNotebook = false
    @State private var isImportingPDF = false
    @State private var isShowingImportError = false

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            SidebarView(selection: $collection, searchText: $searchText)
        } content: {
            if let collection {
                NotepadListView(
                    collection: collection,
                    selection: $selectedNotepad,
                    searchText: $searchText,
                    actions: actions
                )
            } else {
                ContentUnavailableView("No Collection Selected", systemImage: "sidebar.left")
            }
        } detail: {
            if let selectedNotepad {
                NotepadDetailView(notepad: selectedNotepad)
                    // A fresh editor for each notepad, so editor state never leaks between them.
                    .id(selectedNotepad.persistentModelID)
            } else {
                ContentUnavailableView(
                    "No Notepad Selected",
                    systemImage: "square.and.pencil",
                    description: Text("Choose a notepad, or create a new note, notebook or canvas.")
                )
            }
        }
        .focusedSceneValue(\.libraryActions, actions)
        #if DEBUG
        .task {
            // Lets UI tests and performance checks start straight in a new notepad.
            let arguments = ProcessInfo.processInfo.arguments
            if arguments.contains("-uiTestingOpenNewCanvas") {
                actions.newNotepad(.canvas)
                // At launch the split view finishes its first layout after this and brings the
                // library back in portrait, so hide it again once that's done.
                try? await Task.sleep(for: .milliseconds(500))
                columnVisibility = .detailOnly
            } else if arguments.contains("-uiTestingOpenNewNotebook") {
                actions.newNotepad(.notebook)
            }
        }
        #endif
        .onChange(of: selectedNotepad) { previous, current in
            discardIfEmpty(previous)
            // Writing and drawing get the whole screen; notes keep the list visible like Apple Notes.
            if let current, current.type != .notes {
                columnVisibility = .detailOnly
            }
        }
        .sheet(isPresented: $isCreatingNotebook) {
            NotebookSetupSheet { title, size, style in
                let notebook = Notepad(title: title, type: .notebook, folder: collection?.folder)
                notebook.paperSize = size
                notebook.paperStyle = style
                insertAndSelect(notebook)
                notebook.appendPage()
            }
        }
        .fileImporter(isPresented: $isImportingPDF, allowedContentTypes: [.pdf]) { result in
            guard case .success(let url) = result else { return }
            if let notebook = PDFSupport.makeNotebook(fromPDFAt: url, folder: collection?.folder) {
                insertAndSelect(notebook)
            } else {
                isShowingImportError = true
            }
        }
        .alert("Couldn’t Import PDF", isPresented: $isShowingImportError) {
            Button("OK") {}
        } message: {
            Text("The file couldn’t be read as a PDF.")
        }
    }

    private var actions: LibraryActions {
        LibraryActions(
            newNotepad: { type in
                switch type {
                case .notebook:
                    isCreatingNotebook = true
                case .notes:
                    insertAndSelect(Notepad(type: .notes, folder: collection?.folder))
                case .canvas:
                    insertAndSelect(Notepad(title: String(localized: "Untitled Canvas"), type: .canvas, folder: collection?.folder))
                }
            },
            importPDF: { isImportingPDF = true }
        )
    }

    private func insertAndSelect(_ notepad: Notepad) {
        modelContext.insert(notepad)
        // Saving right away gives the notepad its permanent identifier before an editor appears.
        try? modelContext.save()
        searchText = ""
        selectedNotepad = notepad
    }

    /// Like Apple Notes, a note you leave without typing anything is thrown away.
    private func discardIfEmpty(_ notepad: Notepad?) {
        guard let notepad,
              notepad.modelContext != nil,
              notepad.type == .notes,
              notepad.plainText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              notepad.attachments?.isEmpty ?? true
        else { return }
        modelContext.delete(notepad)
    }
}

#Preview {
    ContentView()
        .modelContainer(for: Liquid_NotesApp.modelTypes, inMemory: true)
}
