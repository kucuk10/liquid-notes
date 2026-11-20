import Foundation
import SwiftData

@Model
final class Folder {
    var name: String = ""
    var created: Date = Date.now

    // CloudKit requires optional relationships with an explicit inverse.
    @Relationship(deleteRule: .cascade, inverse: \Notepad.folder)
    var notepads: [Notepad]? = []

    init(name: String) {
        self.name = name
        self.created = .now
    }
}
