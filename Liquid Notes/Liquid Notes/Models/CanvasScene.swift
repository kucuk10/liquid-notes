import Foundation
import SwiftData
import CoreGraphics

/// A saved view of a canvas, like a scene in Freeform: a spot and zoom level you can jump back to.
@Model
final class CanvasScene {
    /// Stable identity for views. (`persistentModelID` changes when a new model is first saved.)
    var sceneID: UUID = UUID()
    var name: String = ""
    /// The middle of the view, in canvas coordinates.
    var centerX: Double = 0
    var centerY: Double = 0
    var zoom: Double = 1
    /// Position in the scenes list.
    var order: Int = 0
    var created: Date = Date.now

    var notepad: Notepad?

    init(name: String, center: CGPoint, zoom: CGFloat, order: Int) {
        self.name = name
        self.centerX = center.x
        self.centerY = center.y
        self.zoom = zoom
        self.order = order
        self.created = .now
    }

    var center: CGPoint {
        CGPoint(x: centerX, y: centerY)
    }
}
