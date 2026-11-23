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
            for: Schema(Liquid_NotesApp.modelTypes),
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

    @Test func textBoxOnLastPageAddsAnotherPage() throws {
        let context = try makeContext()
        let notebook = Notepad(title: "History", type: .notebook)
        context.insert(notebook)
        notebook.ensureTrailingBlankPage()
        let page = try #require(notebook.sortedPages.first)

        let textBox = PlacedItemFactory.textBox(at: CGPoint(x: 40, y: 40), in: page.size)
        context.insert(textBox)
        textBox.page = page
        notebook.ensureTrailingBlankPage()

        #expect(page.hasContent)
        #expect(notebook.pages?.count == 2)
        #expect(textBox.owningNotepad == notebook)
    }

    @Test func placedItemsStayOnTheSurface() {
        let page = CGSize(width: 612, height: 792)
        let clamped = PlacedItemFactory.clamped(CGRect(x: 500, y: -30, width: 300, height: 120), in: page)
        #expect(clamped == CGRect(x: 312, y: 0, width: 300, height: 120))

        let tall = PlacedItemFactory.fittedSize(for: CGSize(width: 1000, height: 2000), maxSide: 400)
        #expect(tall == CGSize(width: 200, height: 400))

        let small = PlacedItemFactory.fittedSize(for: CGSize(width: 100, height: 50), maxSide: 400)
        #expect(small == CGSize(width: 100, height: 50))
    }

    @Test func addingAndMovingItemsCanBeUndoneAndRedone() throws {
        let context = try makeContext()
        let canvas = Notepad(title: "Ideas", type: .canvas)
        context.insert(canvas)
        let undoManager = UndoManager()
        undoManager.groupsByEvent = false

        let image = PlacedItem(kind: .image, frame: CGRect(x: 10, y: 10, width: 100, height: 100))
        image.imageData = Data([1, 2, 3])
        undoManager.beginUndoGrouping()
        PlacedItemUndo.insert([image], onCanvas: canvas, context: context, undoManager: undoManager, actionName: "Add Image")
        undoManager.endUndoGrouping()
        #expect(canvas.canvasItems?.count == 1)

        undoManager.beginUndoGrouping()
        PlacedItemUndo.setFrame(image, to: CGRect(x: 300, y: 300, width: 100, height: 100), undoManager: undoManager, actionName: "Move Image")
        undoManager.endUndoGrouping()
        #expect(image.x == 300)

        undoManager.undo()
        #expect(image.x == 10, "Undo puts a moved item back")

        undoManager.undo()
        #expect(canvas.canvasItems?.isEmpty ?? true, "Undo removes an added item")

        undoManager.redo()
        let restored = try #require(canvas.canvasItems?.first)
        #expect(restored.itemID == image.itemID, "Redo brings the same item back")
        #expect(restored.imageData == Data([1, 2, 3]))
    }

    @Test func tapSelectsTheMostRecentPhotoUnderIt() {
        let older = PlacedItem(kind: .image, frame: CGRect(x: 0, y: 0, width: 200, height: 200))
        older.created = .now.addingTimeInterval(-60)
        let newer = PlacedItem(kind: .image, frame: CGRect(x: 100, y: 100, width: 200, height: 200))
        let text = PlacedItem(kind: .text, frame: CGRect(x: 0, y: 0, width: 400, height: 400))
        let items = [older, newer, text]

        // Where photos overlap, the one added later is on top.
        #expect(PlacedItemFactory.topImage(at: CGPoint(x: 150, y: 150), in: items) === newer)
        #expect(PlacedItemFactory.topImage(at: CGPoint(x: 50, y: 50), in: items) === older)
        // Text boxes aren't photos, and empty space selects nothing.
        #expect(PlacedItemFactory.topImage(at: CGPoint(x: 350, y: 350), in: items) == nil)
    }

    @Test func fontSizesStepLikeAWordProcessor() {
        #expect(FontSizes.next(after: 12) == 14)
        #expect(FontSizes.previous(before: 12) == 11)
        #expect(FontSizes.next(after: 17) == 18)
        #expect(FontSizes.next(after: 72) == 72)
        #expect(FontSizes.previous(before: 8) == 8)
        #expect(FontSizes.choices(including: 17).contains(17))
        #expect(FontSizes.choices(including: 12) == FontSizes.standard)
        #expect(FontSizes.label(for: 12) == "12")
    }

    @Test func fontSizeAppliesToSelectedText() throws {
        var text = AttributedString("Essay title")
        var selection = AttributedTextSelection(range: text.startIndex..<text.endIndex)
        let target = RichTextTarget(
            id: "test",
            text: Binding { text } set: { text = $0 },
            selection: Binding { selection } set: { selection = $0 },
            defaultFont: .system(size: 12)
        )
        let context = EnvironmentValues().fontResolutionContext

        #expect(FontSizes.pointSize(of: text, selection: selection, defaultFont: .system(size: 12), context: context) == 12)
        target.apply(pointSize: 18, context: context)
        #expect(FontSizes.pointSize(of: text, selection: selection, defaultFont: .system(size: 12), context: context) == 18)
        target.toggleBold(context: context)
        let font = try #require(text.runs.first?.font)
        #expect(font.resolve(in: context).isBold)
        #expect(font.resolve(in: context).pointSize == 18)
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
