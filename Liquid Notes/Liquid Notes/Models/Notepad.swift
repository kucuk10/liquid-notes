import Foundation
import SwiftData
import SwiftUI

/// A notes page, notebook, or canvas.
///
/// One model covers all three types so that folders, search, and recents can treat them uniformly.
/// Properties that only apply to a single type are grouped below.
@Model
final class Notepad {
    var title: String = ""
    var typeRawValue: String = NotepadType.notes.rawValue
    var created: Date = Date.now
    var modified: Date = Date.now

    var folder: Folder?

    @Relationship(deleteRule: .cascade, inverse: \Attachment.notepad)
    var attachments: [Attachment]? = []

    // MARK: Notes

    /// Rich text encoded with SwiftUI attributes (see `RichTextCoding`).
    var richTextData: Data?
    /// Plain-text mirror of the rich text, used for search and list previews.
    var plainText: String = ""

    // MARK: Notebook

    var paperSizeRawValue: String = PaperSize.letter.rawValue
    var paperStyleRawValue: String = PaperStyle.ruled.rawValue
    /// The original PDF for notebooks created by importing a PDF.
    @Attribute(.externalStorage) var pdfData: Data?

    @Relationship(deleteRule: .cascade, inverse: \NotebookPage.notepad)
    var pages: [NotebookPage]? = []

    // MARK: Canvas

    /// Serialized `PKDrawing` data for the whole canvas.
    @Attribute(.externalStorage) var canvasDrawingData: Data?

    init(title: String = "", type: NotepadType, folder: Folder? = nil) {
        self.title = title
        self.typeRawValue = type.rawValue
        self.created = .now
        self.modified = .now
        self.folder = folder
    }

    var type: NotepadType {
        get { NotepadType(rawValue: typeRawValue) ?? .notes }
        set { typeRawValue = newValue.rawValue }
    }

    var paperSize: PaperSize {
        get { PaperSize(rawValue: paperSizeRawValue) ?? .letter }
        set { paperSizeRawValue = newValue.rawValue }
    }

    var paperStyle: PaperStyle {
        get { PaperStyle(rawValue: paperStyleRawValue) ?? .ruled }
        set { paperStyleRawValue = newValue.rawValue }
    }

    var displayTitle: String {
        title.isEmpty ? String(localized: "Untitled") : title
    }

    var sortedPages: [NotebookPage] {
        (pages ?? []).sorted { $0.index < $1.index }
    }

    var sortedAttachments: [Attachment] {
        (attachments ?? []).sorted { $0.created < $1.created }
    }

    /// A short secondary line for library rows.
    var summary: String {
        switch type {
        case .notes:
            let body = plainText
                .split(whereSeparator: \.isNewline)
                .dropFirst()
                .first { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
            return body.map(String.init) ?? String(localized: "No additional text")
        case .notebook:
            let count = pages?.count ?? 0
            return String(localized: "\(count) pages")
        case .canvas:
            return String(localized: "Canvas")
        }
    }

    func touch() {
        modified = .now
    }

    // MARK: Rich text

    var richText: AttributedString {
        RichTextCoding.decode(richTextData) ?? AttributedString(plainText)
    }

    /// Stores new rich text and keeps the title and plain-text mirror in sync.
    func updateRichText(_ text: AttributedString) {
        richTextData = RichTextCoding.encode(text)
        plainText = String(text.characters)
        title = Self.title(fromPlainText: plainText)
        touch()
    }

    /// Like Apple Notes, a note's title is its first non-empty line.
    static func title(fromPlainText text: String) -> String {
        let firstLine = text
            .split(whereSeparator: \.isNewline)
            .first { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        return String(firstLine?.trimmingCharacters(in: .whitespaces).prefix(120) ?? "")
    }

    // MARK: Notebook pages

    /// Appends a blank page using the notebook's paper size.
    @discardableResult
    func appendPage() -> NotebookPage {
        let nextIndex = (pages ?? []).map(\.index).max().map { $0 + 1 } ?? 0
        let page = NotebookPage(index: nextIndex, size: paperSize.size)
        if pages == nil { pages = [] }
        pages?.append(page)
        touch()
        return page
    }

    /// Notebooks keep one empty page at the end so there is always room to keep writing.
    func ensureTrailingBlankPage() {
        guard type == .notebook else { return }
        if let last = sortedPages.last, !last.hasContent { return }
        appendPage()
    }
}

/// Encodes `AttributedString` including SwiftUI attributes such as fonts and colors.
enum RichTextCoding {
    private struct Container: Codable {
        @CodableConfiguration(from: \.swiftUI) var text = AttributedString()
    }

    static func encode(_ text: AttributedString) -> Data? {
        try? JSONEncoder().encode(Container(text: text))
    }

    static func decode(_ data: Data?) -> AttributedString? {
        guard let data else { return nil }
        return try? JSONDecoder().decode(Container.self, from: data).text
    }
}
