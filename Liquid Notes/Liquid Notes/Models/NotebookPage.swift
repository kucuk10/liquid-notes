import Foundation
import SwiftData

/// A single fixed-size page in a notebook.
///
/// Each page stores its own drawing so that editing one page only syncs that page.
@Model
final class NotebookPage {
    /// Stable identity for views. (`persistentModelID` changes when a new model is first saved.)
    var pageID: UUID = UUID()
    /// Position of the page within its notebook.
    var index: Int = 0
    /// Page size in points.
    var width: Double = 612
    var height: Double = 792
    /// When set, the page shows this page of the notebook's imported PDF as its background.
    var pdfPageIndex: Int?
    /// Serialized `PKDrawing` data.
    @Attribute(.externalStorage) var drawingData: Data?

    var notepad: Notepad?

    @Relationship(deleteRule: .cascade, inverse: \PlacedItem.page)
    var items: [PlacedItem]? = []

    init(index: Int, size: CGSize, pdfPageIndex: Int? = nil) {
        self.index = index
        self.width = size.width
        self.height = size.height
        self.pdfPageIndex = pdfPageIndex
    }

    var size: CGSize { CGSize(width: width, height: height) }

    /// Whether the page has anything on it yet.
    var hasContent: Bool {
        pdfPageIndex != nil || !(drawingData?.isEmpty ?? true) || !(items?.isEmpty ?? true)
    }

    var sortedItems: [PlacedItem] {
        (items ?? []).sorted { $0.created < $1.created }
    }
}
