import Foundation

/// The three kinds of notepads the app supports.
///
/// Raw values are persisted (and synced through CloudKit), so never change them.
enum NotepadType: String, Codable, CaseIterable, Identifiable {
    case notes
    case notebook
    case canvas

    var id: String { rawValue }

    /// Singular name, used for creation menus ("New Note").
    var displayName: String {
        switch self {
        case .notes: "Note"
        case .notebook: "Notebook"
        case .canvas: "Canvas"
        }
    }

    /// Plural name, used for library sections.
    var pluralName: String {
        switch self {
        case .notes: "Notes"
        case .notebook: "Notebooks"
        case .canvas: "Canvases"
        }
    }

    /// System image name used for UI representations of each notepad type.
    var systemImageName: String {
        switch self {
        case .notes: "note.text"
        case .notebook: "book.closed"
        case .canvas: "scribble.variable"
        }
    }
}
