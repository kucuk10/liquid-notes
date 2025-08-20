import Foundation
import SwiftData

@Model
final class Notepad {
    var title: String
    var type: NotepadType
    var content: String
    var created: Date
    var modified: Date
    var folder: Folder?

    init(title: String, type: NotepadType, folder: Folder? = nil) {
        self.title = title
        self.type = type
        self.content = ""
        self.created = .now
        self.modified = .now
        self.folder = folder
    }
}
