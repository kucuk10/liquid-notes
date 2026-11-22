import SwiftUI
import SwiftData

/// A drawable area with text boxes and images, such as one notebook page.
///
/// Everything on the surface uses the same logical coordinates, scaled to fit `displayWidth`.
/// Layers from back to front: background, Apple Pencil ink, then text boxes and images.
struct DrawingSurface<Background: View>: View {
    let canvasID: AnyHashable
    /// The area shown, in logical coordinates.
    let logicalSize: CGSize
    /// The logical coordinate at the surface's top-leading corner, when it shows part of a larger space.
    var origin: CGPoint = .zero
    /// Where items may be moved. Defaults to the area shown.
    var itemBounds: CGSize?
    let displayWidth: CGFloat
    let drawingData: Data?
    let items: [PlacedItem]
    let session: EditorSession
    /// Paper stays light like real paper; canvases follow the system appearance.
    var alwaysLight = false
    let onDrawingChange: (Data?) -> Void
    var onDrawingBoundsChange: ((CGRect) -> Void)? = nil
    /// Places a text box at a point in logical coordinates: from the picker's Text tool, a finger
    /// double-tap, or a double-click on Mac.
    let onPlaceText: (CGPoint) -> Void
    /// Places dropped images centered on a point in logical coordinates.
    let onDropImages: ([Data], CGPoint) -> Void
    let onDeleteItem: (PlacedItem) -> Void
    @ViewBuilder var background: () -> Background

    @Environment(\.displayScale) private var displayScale
    @Environment(\.colorScheme) private var colorScheme

    private var scale: CGFloat {
        logicalSize.width > 0 ? displayWidth / logicalSize.width : 1
    }

    private func logicalPoint(_ location: CGPoint) -> CGPoint {
        CGPoint(x: origin.x + location.x / scale, y: origin.y + location.y / scale)
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            // On iPhone and iPad the ink layer covers this and handles taps itself; these gestures are for Mac.
            background()
                .contentShape(.rect)
                .onTapGesture(count: 2) { location in
                    onPlaceText(logicalPoint(location))
                }
                .onTapGesture { location in
                    selectPhoto(at: logicalPoint(location))
                }

            // Photos sit under the ink so you can draw on them.
            itemsLayer(.photos)

            ink

            // Text boxes sit above the ink so you can type over photos.
            itemsLayer(.textAndHandles)
        }
        .frame(width: displayWidth, height: logicalSize.height * scale, alignment: .topLeading)
        .dropDestination(for: DroppedImage.self) { images, location in
            let prepared = ImageProcessing.preparedImages(from: images.map(\.data))
            guard !prepared.isEmpty else { return false }
            onDropImages(prepared, logicalPoint(location))
            return true
        }
    }

    private func itemsLayer(_ layer: PlacedItemsLayer.Layer) -> some View {
        PlacedItemsLayer(
            items: items,
            layer: layer,
            logicalSize: logicalSize,
            scale: scale,
            session: session,
            origin: origin,
            itemBounds: itemBounds,
            onDelete: onDeleteItem
        )
    }

    /// Photos are under the ink, so a tap on the surface selects the topmost photo there, or deselects.
    private func selectPhoto(at point: CGPoint) {
        session.selectedItemID = PlacedItemFactory.topImage(at: point, in: items)?.itemID
    }

    @ViewBuilder
    private var ink: some View {
        #if canImport(UIKit)
        PencilCanvasView(
            canvasID: canvasID,
            drawingData: drawingData,
            layout: .page(logicalSize),
            session: session,
            alwaysLight: alwaysLight,
            onDrawingChange: onDrawingChange,
            onDrawingBoundsChange: onDrawingBoundsChange,
            onPlaceText: onPlaceText,
            onFingerTap: selectPhoto(at:)
        )
        #else
        // Drawing isn't available on Mac, so the ink is shown as an image.
        if let drawingData {
            let rect = CGRect(origin: origin, size: logicalSize)
            // Very large areas are rendered at a lower resolution to keep the image a reasonable size.
            let pixelScale = min(scale * displayScale, 8192 / max(rect.width, rect.height, 1))
            let dark = !alwaysLight && colorScheme == .dark
            AsyncRenderedImage(key: [
                AnyHashable(drawingData), AnyHashable(pixelScale), AnyHashable(rect.minX),
                AnyHashable(rect.minY), AnyHashable(rect.height), AnyHashable(dark),
            ]) {
                DrawingRenderer.image(from: drawingData, rect: rect, scale: pixelScale, dark: dark)
            } placeholder: {
                Color.clear
            }
            .allowsHitTesting(false)
        }
        #endif
    }
}
