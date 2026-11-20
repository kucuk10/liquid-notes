import Foundation
import SwiftData

/// The kinds of files a notepad can hold as attachments.
enum AttachmentKind: String, Codable {
    case image
    case pdf
    /// A handwritten sketch stored as `PKDrawing` data.
    case sketch
}

/// A file attached to a notepad, such as a photo, PDF or sketch.
@Model
final class Attachment {
    var kindRawValue: String = AttachmentKind.image.rawValue
    var filename: String = ""
    var created: Date = Date.now
    @Attribute(.externalStorage) var data: Data?

    var notepad: Notepad?

    init(kind: AttachmentKind, filename: String, data: Data) {
        self.kindRawValue = kind.rawValue
        self.filename = filename
        self.data = data
        self.created = .now
    }

    var kind: AttachmentKind {
        get { AttachmentKind(rawValue: kindRawValue) ?? .image }
        set { kindRawValue = newValue.rawValue }
    }
}
