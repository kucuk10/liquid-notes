import SwiftUI
import SwiftData

@main
struct Liquid_NotesApp: App {
    static let modelTypes: [any PersistentModel.Type] = [
        Folder.self, Notepad.self, NotebookPage.self, Attachment.self, PlacedItem.self, CanvasScene.self,
    ]

    /// UI tests launch with `-uiTesting` to start from an empty library that isn't saved.
    private let container: ModelContainer = {
        let isUITesting = ProcessInfo.processInfo.arguments.contains("-uiTesting")
        let configuration = ModelConfiguration(isStoredInMemoryOnly: isUITesting)
        do {
            return try ModelContainer(for: Schema(Liquid_NotesApp.modelTypes), configurations: configuration)
        } catch {
            fatalError("Couldn't open the notes library: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup(id: "library") {
            ContentView()
        }
        // SwiftData would sync through an iCloud container listed in the app's entitlements.
        .modelContainer(container)
        .commands {
            LiquidNotesCommands()
        }
    }
}

/// Menu bar commands (on Mac) and keyboard shortcuts (on iPad).
struct LiquidNotesCommands: Commands {
    @FocusedValue(\.libraryActions) private var actions
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("New Note") { actions?.newNotepad(.notes) }
                .keyboardShortcut("n")
            Button("New Notebook…") { actions?.newNotepad(.notebook) }
                .keyboardShortcut("n", modifiers: [.command, .shift])
            Button("New Canvas") { actions?.newNotepad(.canvas) }
                .keyboardShortcut("n", modifiers: [.command, .control])
            Divider()
            Button("New Window") { openWindow(id: "library") }
                .keyboardShortcut("n", modifiers: [.command, .option])
        }
        CommandGroup(after: .importExport) {
            Button("Import PDF as Notebook…") { actions?.importPDF() }
                .keyboardShortcut("i", modifiers: [.command, .shift])
        }
        TextFormattingCommands()
    }
}
