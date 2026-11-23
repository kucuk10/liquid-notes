import SwiftUI
import SwiftData

/// Zoom levels offered in the canvas's zoom menu.
enum CanvasZoomLevels {
    static let presets: [CGFloat] = [0.1, 0.25, 0.5, 0.75, 1, 1.25, 1.5, 2, 3, 4]

    static func percent(_ zoom: CGFloat) -> Int {
        Int((zoom * 100).rounded())
    }
}

/// Shows the canvas's zoom as a percentage. Tapping it offers preset levels and Zoom to Fit.
struct CanvasZoomMenu: View {
    let zoom: CGFloat
    let onSelect: (CGFloat) -> Void
    let onZoomToFit: () -> Void

    var body: some View {
        Menu {
            ForEach(CanvasZoomLevels.presets, id: \.self) { level in
                Button {
                    onSelect(level)
                } label: {
                    if CanvasZoomLevels.percent(level) == CanvasZoomLevels.percent(zoom) {
                        Label("\(CanvasZoomLevels.percent(level))%", systemImage: "checkmark")
                    } else {
                        Text("\(CanvasZoomLevels.percent(level))%")
                    }
                }
            }
            Divider()
            Button("Zoom to Fit", systemImage: "arrow.up.left.and.down.right.magnifyingglass", action: onZoomToFit)
        } label: {
            Text("\(CanvasZoomLevels.percent(zoom))%")
                .monospacedDigit()
                .frame(minWidth: 48)
        }
        .accessibilityLabel("Zoom")
        .accessibilityValue("\(CanvasZoomLevels.percent(zoom)) percent")
    }
}

/// A canvas's text boxes and images, drawn above the ink and moved to match its scroll position and zoom.
///
/// Only this view reads the viewport, so scrolling redraws the overlay without rebuilding the editor.
struct CanvasItemsOverlay: View {
    let viewport: CanvasViewport
    let items: [PlacedItem]
    let layer: PlacedItemsLayer.Layer
    let worldSize: CGSize
    let session: EditorSession
    let onDelete: (PlacedItem) -> Void

    var body: some View {
        let zoom = viewport.zoomScale
        let visible = viewport.visibleRect
        // The layer covers only the screen, not the whole canvas: a canvas-sized layer would need
        // an enormous GPU texture. Items well off screen are skipped, so scrolling stays fast.
        let nearby = visible.insetBy(dx: -visible.width / 2, dy: -visible.height / 2)
        PlacedItemsLayer(
            items: items.filter { $0.frame.intersects(nearby) || $0.itemID == session.selectedItemID },
            layer: layer,
            logicalSize: visible.size,
            scale: zoom,
            session: session,
            origin: visible.origin,
            itemBounds: worldSize,
            onDelete: onDelete
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .clipped()
    }
}

/// Reads the live zoom from the canvas, so only this button redraws while you pinch.
struct ViewportZoomMenu: View {
    let viewport: CanvasViewport
    let onZoomToFit: () -> Void

    var body: some View {
        CanvasZoomMenu(zoom: viewport.zoomScale, onSelect: viewport.setZoom, onZoomToFit: onZoomToFit)
    }
}

/// Lists the canvas's scenes, like Freeform: jump to one, save the current view, or manage them.
struct CanvasScenesMenu: View {
    let scenes: [CanvasScene]
    let onShow: (CanvasScene) -> Void
    let onAdd: () -> Void
    let onManage: () -> Void

    var body: some View {
        Menu {
            Section("Scenes") {
                ForEach(scenes, id: \.sceneID) { scene in
                    Button(scene.name.isEmpty ? String(localized: "Untitled Scene") : scene.name) {
                        onShow(scene)
                    }
                }
            }
            Section {
                Button("Add Scene from Current View", systemImage: "plus.rectangle.on.rectangle", action: onAdd)
                Button("Manage Scenes…", systemImage: "list.bullet", action: onManage)
            }
        } label: {
            Label("Scenes", systemImage: "rectangle.on.rectangle.angled")
        }
    }
}

/// Rename, reorder and delete a canvas's scenes.
struct ScenesManagerSheet: View {
    let notepad: Notepad
    let onShow: (CanvasScene) -> Void

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                ForEach(notepad.sortedScenes, id: \.sceneID) { scene in
                    SceneRow(scene: scene) {
                        onShow(scene)
                        dismiss()
                    }
                }
                .onDelete(perform: delete)
                .onMove(perform: move)
            }
            .overlay {
                if notepad.sortedScenes.isEmpty {
                    ContentUnavailableView(
                        "No Scenes",
                        systemImage: "rectangle.on.rectangle.angled",
                        description: Text("Save a view of the canvas as a scene to come back to it quickly.")
                    )
                }
            }
            .navigationTitle("Scenes")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { EditButton() }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private func delete(at offsets: IndexSet) {
        let scenes = notepad.sortedScenes
        for index in offsets {
            modelContext.delete(scenes[index])
        }
        notepad.touch()
    }

    private func move(from source: IndexSet, to destination: Int) {
        var scenes = notepad.sortedScenes
        scenes.move(fromOffsets: source, toOffset: destination)
        for (index, scene) in scenes.enumerated() {
            scene.order = index
        }
        notepad.touch()
    }
}

private struct SceneRow: View {
    @Bindable var scene: CanvasScene
    let onShow: () -> Void

    var body: some View {
        HStack {
            TextField("Scene Name", text: $scene.name)
            Text("\(CanvasZoomLevels.percent(scene.zoom))%")
                .monospacedDigit()
                .foregroundStyle(.secondary)
            Button("Show", action: onShow)
                .buttonStyle(.borderless)
        }
    }
}
