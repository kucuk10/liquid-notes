import SwiftUI
import SwiftData

/// A group of notepads shown in the sidebar.
enum LibraryCollection: Hashable {
    case recents
    case all
    case type(NotepadType)
    case folder(Folder)

    var title: String {
        switch self {
        case .recents: String(localized: "Recents")
        case .all: String(localized: "All Notepads")
        case .type(let type): type.pluralName
        case .folder(let folder): folder.name
        }
    }

    var systemImageName: String {
        switch self {
        case .recents: "clock"
        case .all: "tray.full"
        case .type(let type): type.systemImageName
        case .folder: "folder"
        }
    }

    /// The folder new notepads are created in.
    var folder: Folder? {
        if case .folder(let folder) = self { folder } else { nil }
    }

    /// The type created by the main "New" button.
    var preferredType: NotepadType {
        if case .type(let type) = self { type } else { .notes }
    }

    /// Mixed collections are easier to scan when grouped by type.
    var groupsByType: Bool {
        switch self {
        case .all, .folder: true
        case .recents, .type: false
        }
    }

    func contains(_ notepad: Notepad) -> Bool {
        switch self {
        case .recents:
            notepad.modified > Calendar.current.date(byAdding: .day, value: -7, to: .now) ?? .distantPast
        case .all:
            true
        case .type(let type):
            notepad.type == type
        case .folder(let folder):
            notepad.folder == folder
        }
    }
}

extension NotepadType {
    /// Accent color that distinguishes each type in lists.
    var tint: Color {
        switch self {
        case .notes: .yellow
        case .notebook: .blue
        case .canvas: .purple
        }
    }
}

/// Actions for creating notepads, shared by toolbars and menu bar commands.
struct LibraryActions {
    var newNotepad: (NotepadType) -> Void
    var importPDF: () -> Void
}

extension FocusedValues {
    @Entry var libraryActions: LibraryActions?
}
