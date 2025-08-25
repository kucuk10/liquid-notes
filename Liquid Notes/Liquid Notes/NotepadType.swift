import Foundation

enum NotepadType: String, Codable, CaseIterable, Identifiable {
    case postIt = "Post-It"
    case notebook = "Notebook"
    case canvas = "Canvas"

    var id: String { rawValue }

    /// System image name used for UI representations of each notepad type.
    var systemImageName: String {
        switch self {
        case .postIt:
            return "note.text"
        case .notebook:
            return "book.closed"
        case .canvas:
            return "scribble"
        }
    }
}
