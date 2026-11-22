import SwiftUI
import SwiftData

/// A freeform space for Apple Pencil ink, text boxes and images that you can zoom and scroll in every direction.
/// Like Freeform, you can save views of it as scenes and jump between them.
struct CanvasNotepadView: View {
    @Bindable var notepad: Notepad
    @Environment(\.modelContext) private var modelContext
    @State private var session = EditorSession()
    /// The bounds of the ink, in canvas coordinates.
    @State private var drawingBounds: CGRect?
    @State private var isManagingScenes = false

    /// The size of the canvas. It's large enough to feel endless; new canvases open in the middle,
    /// so there's room to grow in every direction.
    static let worldSize = CGSize(width: 20_000, height: 20_000)
    private let canvasID = "canvas"

    #if canImport(UIKit)
    @State private var viewport = CanvasViewport()
    /// Where the canvas opens, decided once when it loads.
    @State private var openingFocus: CGPoint?
    #else
    @State private var zoom: CGFloat = 1
    @State private var zoomAtGestureStart: CGFloat = 1
    @State private var scrollPosition = ScrollPosition()
    /// The visible part of the scroll view, in its content coordinates.
    @State private var visibleScrollRect: CGRect = .zero
    #endif

    var body: some View {
        content
            .background(.background)
            .navigationTitle($notepad.title)
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            .toolbarRole(.editor)
            .ignoresSafeArea(.container, edges: .bottom)
            #endif
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
                    AnyView(zoomMenu),
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
                #if canImport(UIKit)
                if openingFocus == nil { openingFocus = initialFocus }
                session.activeCanvasID = canvasID
                #endif
            }
    }

    // MARK: Layout

    @ViewBuilder
    private var content: some View {
        #if canImport(UIKit)
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
                let prepared = ImageProcessing.preparedImages(from: images.map(\.data))
                guard !prepared.isEmpty else { return false }
                addImages(prepared, centeredAt: viewport.canvasPoint(forViewPoint: location))
                return true
            }
        } else {
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        #else
        macCanvas
        #endif
    }

    #if canImport(UIKit)
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
    #endif

    @ViewBuilder
    private var zoomMenu: some View {
        #if canImport(UIKit)
        ViewportZoomMenu(viewport: viewport, onZoomToFit: zoomToFit)
        #else
        CanvasZoomMenu(zoom: zoom, onSelect: { show(center: visibleCenter, zoom: $0) }, onZoomToFit: zoomToFit)
        #endif
    }

    #if !canImport(UIKit)
    /// On Mac the canvas shows the area around your content, scrolling both ways and zooming with a pinch.
    private var macCanvas: some View {
        let region = macRegion
        return ScrollView([.horizontal, .vertical]) {
            DrawingSurface(
                canvasID: canvasID,
                logicalSize: region.size,
                origin: region.origin,
                itemBounds: Self.worldSize,
                displayWidth: region.width * zoom,
                drawingData: notepad.canvasDrawingData,
                items: notepad.sortedCanvasItems,
                session: session,
                onDrawingChange: { _ in },
                onPlaceText: { addTextBox(at: $0) },
                onDropImages: { addImages($0, centeredAt: $1) },
                onDeleteItem: delete
            ) {
                Color.clear
            }
        }
        .scrollPosition($scrollPosition)
        .defaultScrollAnchor(.center)
        .onScrollGeometryChange(for: CGRect.self) { geometry in
            CGRect(origin: geometry.contentOffset, size: geometry.containerSize)
        } action: { _, visible in
            visibleScrollRect = visible
        }
        .gesture(
            MagnifyGesture()
                .onChanged { value in
                    zoom = min(max(zoomAtGestureStart * value.magnification, 0.1), 4)
                }
                .onEnded { _ in zoomAtGestureStart = zoom }
        )
    }

    private var macRegion: CGRect {
        let world = CGRect(origin: .zero, size: Self.worldSize)
        var base = contentBounds ?? CGRect(x: world.midX - 600, y: world.midY - 400, width: 1200, height: 800)
        // Keep scenes reachable even if nothing has been drawn there.
        for scene in notepad.sortedScenes {
            base = base.union(CGRect(x: scene.centerX - 600, y: scene.centerY - 400, width: 1200, height: 800))
        }
        return base.insetBy(dx: -1500, dy: -1500).intersection(world)
    }
    #endif

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
        #if canImport(UIKit)
        if !viewport.visibleRect.isEmpty { return viewport.visibleCenter }
        return openingFocus ?? initialFocus
        #else
        guard visibleScrollRect.width > 0 else { return CGPoint(x: macRegion.midX, y: macRegion.midY) }
        return CGPoint(
            x: macRegion.minX + visibleScrollRect.midX / zoom,
            y: macRegion.minY + visibleScrollRect.midY / zoom
        )
        #endif
    }

    private var currentZoom: CGFloat {
        #if canImport(UIKit)
        viewport.zoomScale
        #else
        zoom
        #endif
    }

    private func show(_ scene: CanvasScene) {
        show(center: scene.center, zoom: scene.zoom)
    }

    private func show(center: CGPoint, zoom newZoom: CGFloat) {
        #if canImport(UIKit)
        viewport.show(center: center, zoom: newZoom)
        #else
        let clamped = min(max(newZoom, 0.1), 4)
        let region = macRegion
        withAnimation {
            zoom = clamped
            zoomAtGestureStart = clamped
        }
        // Scroll once the content has been laid out at the new zoom.
        DispatchQueue.main.async {
            let point = CGPoint(
                x: max(0, (center.x - region.minX) * clamped - visibleScrollRect.width / 2),
                y: max(0, (center.y - region.minY) * clamped - visibleScrollRect.height / 2)
            )
            withAnimation { scrollPosition.scrollTo(point: point) }
        }
        #endif
    }

    private func zoomToFit() {
        guard let content = contentBounds else {
            show(center: visibleCenter, zoom: 1)
            return
        }
        #if canImport(UIKit)
        viewport.fit(content)
        #else
        let padded = content.insetBy(dx: -80, dy: -80)
        let fitZoom = min(visibleScrollRect.width / padded.width, visibleScrollRect.height / padded.height)
        show(center: CGPoint(x: padded.midX, y: padded.midY), zoom: fitZoom)
        #endif
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
            zoom: currentZoom,
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
        for item in items {
            modelContext.insert(item)
            item.notepad = notepad
        }
        notepad.touch()
    }

    private func delete(_ item: PlacedItem) {
        session.forget(item)
        modelContext.delete(item)
        notepad.touch()
    }
}
