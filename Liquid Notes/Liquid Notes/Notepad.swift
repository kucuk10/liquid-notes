import Foundation
import SwiftData

@Model
final class Notepad {
    var title: String
    var type: NotepadType
    var content: String
    var created: Date
    var modified: Date

    init(title: String, type: NotepadType) {
        self.title = title
        self.type = type
        self.content = ""
        self.created = .now
        self.modified = .now
    }
}
