import Foundation

enum NotepadType: String, Codable, CaseIterable, Identifiable {
    case postIt = "Post-It"
    case notebook = "Notebook"
    case canvas = "Canvas"

    var id: String { rawValue }
}
