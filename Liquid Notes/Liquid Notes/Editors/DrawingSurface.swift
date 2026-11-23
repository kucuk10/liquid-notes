import SwiftUI
import SwiftData

/// A drawable area with text boxes and images, such as one notebook page.
///
/// Everything on the surface uses the same logical coordinates, scaled to fit `displayWidth`.
/// Layers from back to front: background, photos, Apple Pencil ink, then text boxes.
struct DrawingSurface<Background: View>: View {
    let canvasID: AnyHashable
    /// The area shown, in logical coordinates.
    let logicalSize: CGSize
    let displayWidth: CGFloat
    let drawingData: Data?
    let items: [PlacedItem]
    let session: EditorSession
    /// Paper stays light like real paper; canvases follow the system appearance.
    var alwaysLight = false
    let onDrawingChange: (Data?) -> Void
    var onDrawingBoundsChange: ((CGRect) -> Void)? = nil
    /// Places a text box at a point in logical coordinates: from the picker's Text tool, a double-tap,
    /// or a double-click on Mac.
    let onPlaceText: (CGPoint) -> Void
    /// Places dropped images centered on a point in logical coordinates.
    let onDropImages: ([Data], CGPoint) -> Void
    let onDeleteItem: (PlacedItem) -> Void
    @ViewBuilder var background: () -> Background

    private var scale: CGFloat {
        logicalSize.width > 0 ? displayWidth / logicalSize.width : 1
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            background()

            // Photos sit under the ink so you can draw on them.
            itemsLayer(.photos)

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

            // Text boxes sit above the ink so you can type over photos.
            itemsLayer(.textAndHandles)
        }
        .frame(width: displayWidth, height: logicalSize.height * scale, alignment: .topLeading)
        .dropDestination(for: DroppedImage.self) { images, location in
            let point = CGPoint(x: location.x / scale, y: location.y / scale)
            let originals = images.map(\.data)
            Task {
                let prepared = await ImageProcessing.preparedImagesInBackground(from: originals)
                if !prepared.isEmpty { onDropImages(prepared, point) }
            }
            return !images.isEmpty
        }
    }

    private func itemsLayer(_ layer: PlacedItemsLayer.Layer) -> some View {
        PlacedItemsLayer(
            items: items,
            layer: layer,
            logicalSize: logicalSize,
            scale: scale,
            session: session,
            onDelete: onDeleteItem
        )
    }

    /// Photos are under the ink, so a tap on the surface selects the topmost photo there, or deselects.
    private func selectPhoto(at point: CGPoint) {
        session.selectedItemID = PlacedItemFactory.topImage(at: point, in: items)?.itemID
    }
}
