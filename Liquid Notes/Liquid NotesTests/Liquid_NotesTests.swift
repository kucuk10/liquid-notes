import Testing
import SwiftUI
import SwiftData
@testable import Liquid_Notes

@MainActor
struct Liquid_NotesTests {
    /// An in-memory store that never touches iCloud.
    private func makeContext() throws -> ModelContext {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        let container = try ModelContainer(
            for: Folder.self, Notepad.self, NotebookPage.self, Attachment.self,
            configurations: configuration
        )
        return ModelContext(container)
    }

    @Test func createNotepad() throws {
        let note = Notepad(title: "Test", type: .notes)
        #expect(note.type == .notes)
        #expect(note.title == "Test")
    }

    @Test(arguments: [
        ("Groceries\nMilk\nEggs", "Groceries"),
        ("\n\n   Ideas  \nMore", "Ideas"),
        ("", ""),
    ])
    func titleIsFirstNonEmptyLine(text: String, expected: String) {
        #expect(Notepad.title(fromPlainText: text) == expected)
    }

    @Test func richTextKeepsFormattingAndUpdatesTitle() throws {
        let note = Notepad(type: .notes)
        var text = AttributedString("Shopping\nApples")
        let range = try #require(text.range(of: "Shopping"))
        text[range].font = .title.bold()

        note.updateRichText(text)

        #expect(note.title == "Shopping")
        #expect(note.plainText == "Shopping\nApples")
        let decoded = try #require(RichTextCoding.decode(note.richTextData))
        #expect(decoded == text)
    }

    @Test func notebookKeepsOneBlankPageAtTheEnd() throws {
        let context = try makeContext()
        let notebook = Notepad(title: "Biology", type: .notebook)
        notebook.paperSize = .a4
        context.insert(notebook)

        notebook.ensureTrailingBlankPage()
        #expect(notebook.pages?.count == 1)
        #expect(notebook.sortedPages.first?.size == PaperSize.a4.size)

        // A blank last page is enough; nothing new is added.
        notebook.ensureTrailingBlankPage()
        #expect(notebook.pages?.count == 1)

        // Writing on the last page adds a new blank page after it.
        notebook.sortedPages.last?.drawingData = Data([1, 2, 3])
        notebook.ensureTrailingBlankPage()
        #expect(notebook.sortedPages.map(\.index) == [0, 1])
    }

    @Test func folderCollectionContainsOnlyItsNotepads() throws {
        let context = try makeContext()
        let folder = Folder(name: "Chemistry 101")
        context.insert(folder)
        let inFolder = Notepad(type: .canvas, folder: folder)
        let elsewhere = Notepad(type: .canvas)
        context.insert(inFolder)
        context.insert(elsewhere)

        #expect(LibraryCollection.folder(folder).contains(inFolder))
        #expect(!LibraryCollection.folder(folder).contains(elsewhere))
        #expect(LibraryCollection.type(.canvas).contains(elsewhere))
        #expect(!LibraryCollection.type(.notes).contains(elsewhere))
    }
}
