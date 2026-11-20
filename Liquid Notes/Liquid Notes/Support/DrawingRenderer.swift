import Foundation
import PencilKit

/// Converts stored `PKDrawing` data into images, for previews and for read-only display on Mac.
enum DrawingRenderer {
    static func drawing(from data: Data?) -> PKDrawing {
        guard let data, let drawing = try? PKDrawing(data: data) else { return PKDrawing() }
        return drawing
    }

    /// Serializes a drawing, returning `nil` for an empty drawing so empty pages stay empty.
    static func data(for drawing: PKDrawing) -> Data? {
        drawing.strokes.isEmpty ? nil : drawing.dataRepresentation()
    }

    /// Renders part of a drawing.
    /// - Parameters:
    ///   - rect: The area of the drawing to render, or `nil` to use the drawing's bounds.
    ///   - dark: Renders ink colors adapted for dark backgrounds, matching `PKCanvasView` in dark mode.
    static func image(from data: Data?, rect: CGRect? = nil, scale: CGFloat, dark: Bool = false) -> CGImage? {
        let drawing = drawing(from: data)
        let rect = rect ?? drawing.bounds
        guard !rect.isNull, !rect.isEmpty else { return nil }

        var result: CGImage?
        #if canImport(UIKit)
        let traits = UITraitCollection(userInterfaceStyle: dark ? .dark : .light)
        traits.performAsCurrent {
            result = drawing.image(from: rect, scale: scale).cgImage
        }
        #else
        let appearance = NSAppearance(named: dark ? .darkAqua : .aqua) ?? NSAppearance.currentDrawing()
        appearance.performAsCurrentDrawingAppearance {
            result = drawing.image(from: rect, scale: scale).cgImageValue
        }
        #endif
        return result
    }
}
