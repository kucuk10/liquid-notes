import Foundation
import SwiftData
import CoreGraphics

enum PlacedItemKind: String, Codable {
    case text
    case image
}

/// A text box or image positioned on a notebook page or a canvas.
///
/// The frame is in the same coordinates as the drawing (page points, or canvas units),
/// so items stay aligned with handwriting on every screen size.
@Model
final class PlacedItem {
    /// Stable identity for views. (`persistentModelID` changes when a new model is first saved.)
    var itemID: UUID = UUID()
    var kindRawValue: String = PlacedItemKind.text.rawValue
    var x: Double = 0
    var y: Double = 0
    var width: Double = 300
    var height: Double = 120
    var created: Date = Date.now

    /// Rich text for text boxes (see `RichTextCoding`).
    var richTextData: Data?
    @Attribute(.externalStorage) var imageData: Data?

    /// Set for items on a notebook page.
    var page: NotebookPage?
    /// Set for items on a canvas.
    var notepad: Notepad?

    init(kind: PlacedItemKind, frame: CGRect) {
        self.kindRawValue = kind.rawValue
        self.x = frame.minX
        self.y = frame.minY
        self.width = frame.width
        self.height = frame.height
        self.created = .now
    }

    var kind: PlacedItemKind {
        PlacedItemKind(rawValue: kindRawValue) ?? .text
    }

    var frame: CGRect {
        CGRect(x: x, y: y, width: width, height: height)
    }

    var richText: AttributedString {
        RichTextCoding.decode(richTextData) ?? AttributedString()
    }

    /// The notepad this item belongs to, whether it's on a page or directly on a canvas.
    var owningNotepad: Notepad? {
        notepad ?? page?.notepad
    }
}

/// Builds placed items with sensible sizes and positions.
enum PlacedItemFactory {
    static let textBoxSize = CGSize(width: 320, height: 120)

    /// Scales an image's pixel size down to fit within `maxSide`, keeping its aspect ratio.
    static func fittedSize(for pixelSize: CGSize, maxSide: CGFloat) -> CGSize {
        guard pixelSize.width > 0, pixelSize.height > 0 else {
            return CGSize(width: maxSide, height: maxSide)
        }
        let scale = min(1, maxSide / max(pixelSize.width, pixelSize.height))
        return CGSize(width: pixelSize.width * scale, height: pixelSize.height * scale)
    }

    /// Keeps a frame inside the surface it's placed on.
    static func clamped(_ frame: CGRect, in bounds: CGSize) -> CGRect {
        var frame = frame
        frame.size.width = min(frame.width, bounds.width)
        frame.size.height = min(frame.height, bounds.height)
        frame.origin.x = min(max(frame.minX, 0), bounds.width - frame.width)
        frame.origin.y = min(max(frame.minY, 0), bounds.height - frame.height)
        return frame
    }

    /// The topmost image under a point. Later images sit above earlier ones.
    static func topImage(at point: CGPoint, in items: [PlacedItem]) -> PlacedItem? {
        items
            .filter { $0.kind == .image && $0.frame.contains(point) }
            .max { $0.created < $1.created }
    }

    static func textBox(at origin: CGPoint, in bounds: CGSize) -> PlacedItem {
        let size = CGSize(width: min(textBoxSize.width, bounds.width - 32), height: textBoxSize.height)
        return PlacedItem(kind: .text, frame: clamped(CGRect(origin: origin, size: size), in: bounds))
    }

    /// Creates image items. When `center` is given (a drop location), images are centered there.
    static func images(_ images: [Data], center: CGPoint?, fallbackOrigin: CGPoint, in bounds: CGSize) -> [PlacedItem] {
        let maxSide = min(420, bounds.width * 0.6)
        return images.enumerated().map { index, data in
            let size = fittedSize(for: ImageProcessing.pixelSize(of: data), maxSide: maxSide)
            let stagger = CGFloat(index) * 24
            let origin = center.map { CGPoint(x: $0.x - size.width / 2 + stagger, y: $0.y - size.height / 2 + stagger) }
                ?? CGPoint(x: fallbackOrigin.x + stagger, y: fallbackOrigin.y + stagger)
            let item = PlacedItem(kind: .image, frame: clamped(CGRect(origin: origin, size: size), in: bounds))
            item.imageData = data
            return item
        }
    }
}
