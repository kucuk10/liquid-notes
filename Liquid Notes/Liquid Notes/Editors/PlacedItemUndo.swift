import Foundation
import SwiftData
import CoreGraphics

/// Records changes to text boxes and images in the undo history, so Undo and Redo cover them
/// alongside ink and typing.
@MainActor
enum PlacedItemUndo {
    /// Everything needed to bring a deleted item back.
    private struct Snapshot {
        let itemID: UUID
        let kind: PlacedItemKind
        let frame: CGRect
        let created: Date
        let richTextData: Data?
        let imageData: Data?
        let page: NotebookPage?
        let notepad: Notepad?

        init(_ item: PlacedItem) {
            itemID = item.itemID
            kind = item.kind
            frame = item.frame
            created = item.created
            richTextData = item.richTextData
            imageData = item.imageData
            page = item.page
            notepad = item.notepad
        }

        func restore(in context: ModelContext) -> PlacedItem {
            let item = PlacedItem(kind: kind, frame: frame)
            item.itemID = itemID
            item.created = created
            item.richTextData = richTextData
            item.imageData = imageData
            context.insert(item)
            item.page = page
            item.notepad = notepad
            item.owningNotepad?.touch()
            return item
        }
    }

    /// Adds items to their surface. Undo removes them again.
    static func insert(
        _ items: [PlacedItem],
        onPage page: NotebookPage? = nil,
        onCanvas canvas: Notepad? = nil,
        context: ModelContext,
        undoManager: UndoManager?,
        actionName: String
    ) {
        for item in items {
            context.insert(item)
            item.page = page
            item.notepad = canvas
        }
        recordInsertion(of: items, context: context, undoManager: undoManager)
        undoManager?.setActionName(actionName)
    }

    /// Deletes an item. Undo brings it back. Empty text boxes are removed without an undo step,
    /// since there's nothing in them to get back.
    static func delete(_ item: PlacedItem, context: ModelContext, undoManager: UndoManager?) {
        let notepad = item.owningNotepad
        let isEmptyTextBox = item.kind == .text && item.richText.characters.allSatisfy(\.isWhitespace)
        if isEmptyTextBox {
            undoManager?.removeAllActions(withTarget: item)
            context.delete(item)
        } else {
            let snapshot = Snapshot(item)
            context.delete(item)
            recordDeletion(of: [snapshot], context: context, undoManager: undoManager)
            undoManager?.setActionName(item.kind == .image ? String(localized: "Delete Image") : String(localized: "Delete Text Box"))
        }
        notepad?.touch()
    }

    /// Moves or resizes an item. Undo puts it back where it was.
    static func setFrame(_ item: PlacedItem, to frame: CGRect, undoManager: UndoManager?, actionName: String) {
        let previous = item.frame
        guard previous != frame else { return }
        item.x = frame.minX
        item.y = frame.minY
        item.width = frame.width
        item.height = frame.height
        item.owningNotepad?.touch()
        undoManager?.registerUndo(withTarget: item) { item in
            guard !item.isDeleted, item.modelContext != nil else { return }
            setFrame(item, to: previous, undoManager: undoManager, actionName: actionName)
        }
        undoManager?.setActionName(actionName)
    }

    // Undoing an insertion records a deletion, and the other way round, which gives Redo for free.

    private static func recordInsertion(of items: [PlacedItem], context: ModelContext, undoManager: UndoManager?) {
        for item in items {
            undoManager?.registerUndo(withTarget: item) { item in
                guard !item.isDeleted, item.modelContext != nil else { return }
                let snapshot = Snapshot(item)
                let notepad = item.owningNotepad
                context.delete(item)
                notepad?.touch()
                recordDeletion(of: [snapshot], context: context, undoManager: undoManager)
            }
        }
    }

    private static func recordDeletion(of snapshots: [Snapshot], context: ModelContext, undoManager: UndoManager?) {
        undoManager?.registerUndo(withTarget: context) { context in
            let restored = snapshots.map { $0.restore(in: context) }
            recordInsertion(of: restored, context: context, undoManager: undoManager)
        }
    }
}
