import Foundation
import SwiftData

@Model
final class Folder {
    var name: String
    @Relationship(deleteRule: .cascade) var notes: [Notepad] = []

    init(name: String) {
        self.name = name
    }
}
