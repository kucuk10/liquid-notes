import SwiftUI
import SwiftData

/// A freeform space for Apple Pencil ink, text boxes and images that you can zoom and scroll in every direction.
/// Like Freeform, you can save views of it as scenes and jump between them.
struct CanvasNotepadView: View {
    @Bindable var notepad: Notepad
    @Environment(\.modelContext) private var modelContext
    @Environment(\.undoManager) private var undoManager
    @State private var session = EditorSession()
    /// The bounds of the ink, in canvas coordinates.
    @State private var drawingBounds: CGRect?
    @State private var isManagingScenes = false
    @State private var viewport = CanvasViewport()
    /// Where the canvas opens, decided once when it loads.
    @State private var openingFocus: CGPoint?

    /// The size of the canvas. It's large enough to feel endless; new canvases open in the middle,
    /// so there's room to grow in every direction.
    static let worldSize = CGSize(width: 20_000, height: 20_000)
    private let canvasID = "canvas"

    var body: some View {
        content
            .background(.background)
            .navigationTitle($notepad.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbarRole(.editor)
            .ignoresSafeArea(.container, edges: .bottom)
            .editorToolbar(
                session: session,
                leadingTool: .pencil,
                // Scenes and Zoom are separate groups, between Undo/Redo and the Pencil.
                contextTools: [
                    AnyView(CanvasScenesMenu(
                        scenes: notepad.sortedScenes,
                        onShow: show,
                        onAdd: addScene,
                        onManage: { isManagingScenes = true }
                    )),
                    AnyView(ViewportZoomMenu(viewport: viewport, onZoomToFit: zoomToFit)),
                ],
                onAddTextBox: { addTextBox(at: nil) },
                onImportImages: { addImages($0, centeredAt: nil) }
            )
            .sheet(isPresented: $isManagingScenes) {
                ScenesManagerSheet(notepad: notepad, onShow: show)
            }
            .task(id: notepad.persistentModelID) {
                let data = notepad.canvasDrawingData
                let bounds = await Task.detached { DrawingRenderer.drawing(from: data).bounds }.value
                drawingBounds = bounds.isNull ? nil : bounds
                ensureOriginScene()
                if openingFocus == nil { openingFocus = initialFocus }
                session.activeCanvasID = canvasID
            }
    }

    // MARK: Layout

    @ViewBuilder
    private var content: some View {
        if let openingFocus {
            ZStack(alignment: .topLeading) {
                // Photos sit under the ink so you can draw on them.
                itemsOverlay(.photos)

                PencilCanvasView(
                    canvasID: canvasID,
                    drawingData: notepad.canvasDrawingData,
                    layout: .world(Self.worldSize, focus: openingFocus),
                    session: session,
                    onDrawingChange: { data in
                        notepad.canvasDrawingData = data
                        notepad.touch()
                    },
                    onDrawingBoundsChange: { bounds in
                        drawingBounds = bounds.isNull ? nil : bounds
                    },
                    onPlaceText: { addTextBox(at: $0) },
                    onFingerTap: { point in
                        // Photos are under the ink, so a tap selects the topmost photo there, or deselects.
                        session.selectedItemID = PlacedItemFactory.topImage(at: point, in: notepad.sortedCanvasItems)?.itemID
                    },
                    viewport: viewport
                )

                // Text boxes sit above the ink so you can type over photos. Both item layers follow the
                // canvas's scrolling and zooming; touches that miss an item go through to the canvas.
                itemsOverlay(.textAndHandles)
            }
            .clipped()
            .dropDestination(for: DroppedImage.self) { images, location in
                let point = viewport.canvasPoint(forViewPoint: location)
                let originals = images.map(\.data)
                Task {
                    let prepared = await ImageProcessing.preparedImagesInBackground(from: originals)
                    if !prepared.isEmpty { addImages(prepared, centeredAt: point) }
                }
                return !images.isEmpty
            }
        } else {
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func itemsOverlay(_ layer: PlacedItemsLayer.Layer) -> some View {
        CanvasItemsOverlay(
            viewport: viewport,
            items: notepad.sortedCanvasItems,
            layer: layer,
            worldSize: Self.worldSize,
            session: session,
            onDelete: delete
        )
    }

    // MARK: Viewing

    /// Everything on the canvas: ink, text boxes and images.
    private var contentBounds: CGRect? {
        let frames = (notepad.canvasItems ?? []).map(\.frame) + [drawingBounds].compactMap { $0 }
        guard let first = frames.first else { return nil }
        return frames.dropFirst().reduce(first) { $0.union($1) }
    }

    /// New canvases open in the middle of the space; existing ones open on their content.
    private var initialFocus: CGPoint {
        guard let content = contentBounds else {
            return CGPoint(x: Self.worldSize.width / 2, y: Self.worldSize.height / 2)
        }
        return CGPoint(x: content.midX, y: min(content.midY, content.minY + 400))
    }

    /// The middle of what's on screen, where toolbar-added items appear.
    private var visibleCenter: CGPoint {
        if !viewport.visibleRect.isEmpty { return viewport.visibleCenter }
        return openingFocus ?? initialFocus
    }

    private func show(_ scene: CanvasScene) {
        viewport.show(center: scene.center, zoom: scene.zoom)
    }

    private func zoomToFit() {
        if let content = contentBounds {
            viewport.fit(content)
        } else {
            viewport.show(center: visibleCenter, zoom: 1)
        }
    }

    // MARK: Scenes

    /// Every canvas has an Origin scene: where it was when it was first opened.
    private func ensureOriginScene() {
        guard notepad.canvasScenes?.isEmpty ?? true else { return }
        let origin = CanvasScene(name: String(localized: "Origin"), center: initialFocus, zoom: 1, order: 0)
        modelContext.insert(origin)
        origin.notepad = notepad
    }

    private func addScene() {
        let scenes = notepad.sortedScenes
        let scene = CanvasScene(
            name: String(localized: "Scene \(scenes.count + 1)"),
            center: visibleCenter,
            zoom: viewport.zoomScale,
            order: (scenes.map(\.order).max() ?? -1) + 1
        )
        modelContext.insert(scene)
        scene.notepad = notepad
        notepad.touch()
    }

    // MARK: Placing items

    private func addTextBox(at point: CGPoint?) {
        let size = PlacedItemFactory.textBoxSize
        let stagger = CGFloat((notepad.canvasItems?.count ?? 0) % 6) * 32
        let origin = point.map { CGPoint(x: $0.x, y: $0.y - 16) }
            ?? CGPoint(x: visibleCenter.x - size.width / 2 + stagger, y: visibleCenter.y - size.height / 2 + stagger)
        let item = PlacedItemFactory.textBox(at: origin, in: Self.worldSize)
        insert([item])
        session.selectedItemID = item.itemID
        session.pendingFocusItemID = item.itemID
    }

    private func addImages(_ images: [Data], centeredAt center: CGPoint?) {
        let items = PlacedItemFactory.images(
            images,
            center: center ?? visibleCenter,
            fallbackOrigin: visibleCenter,
            in: Self.worldSize
        )
        insert(items)
        session.selectedItemID = items.last?.itemID
    }

    private func insert(_ items: [PlacedItem]) {
        let isImage = items.first?.kind == .image
        PlacedItemUndo.insert(
            items,
            onCanvas: notepad,
            context: modelContext,
            undoManager: undoManager,
            actionName: isImage ? String(localized: "Add Image") : String(localized: "Add Text Box")
        )
        notepad.touch()
    }

    private func delete(_ item: PlacedItem) {
        session.forget(item)
        PlacedItemUndo.delete(item, context: modelContext, undoManager: undoManager)
    }
}
