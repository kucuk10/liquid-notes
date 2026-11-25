import SwiftUI
import PencilKit

/// How a canvas maps its drawing coordinates onto the screen.
enum PencilCanvasLayout: Equatable {
    /// A fixed-size page. The drawing uses page coordinates (points) and is scaled to fit the view's width,
    /// so the same notebook looks identical on iPhone and iPad.
    case page(CGSize)
    /// A canvas with a fixed logical width that grows downward as you draw.
    case infinite(width: CGFloat)
    /// A very large space you can zoom and scroll in every direction, opening centered on `focus`.
    case world(CGSize, focus: CGPoint)

    var isWorld: Bool {
        if case .world = self { true } else { false }
    }
}

/// The visible part of a world canvas. The items layer follows it so text boxes and images move with the ink,
/// the toolbar shows its zoom, and scenes use it to move the view.
@MainActor
@Observable
final class CanvasViewport {
    /// The world coordinate at the top-leading corner of the screen. Observed by the items layer.
    var visibleOrigin: CGPoint = .zero
    /// Observed by the items layer and the toolbar's zoom percentage.
    var zoomScale: CGFloat = 1
    /// The canvas view's size on screen.
    @ObservationIgnored var viewSize: CGSize = .zero
    @ObservationIgnored weak var canvas: FittingCanvasView?

    static let minimumZoom: CGFloat = 0.1
    static let maximumZoom: CGFloat = 4

    /// The visible area in world coordinates.
    var visibleRect: CGRect {
        guard zoomScale > 0 else { return .zero }
        return CGRect(origin: visibleOrigin, size: CGSize(width: viewSize.width / zoomScale, height: viewSize.height / zoomScale))
    }

    var visibleCenter: CGPoint {
        CGPoint(x: visibleRect.midX, y: visibleRect.midY)
    }

    /// Converts a point in the canvas view (such as a drop location) to world coordinates.
    func canvasPoint(forViewPoint point: CGPoint) -> CGPoint {
        CGPoint(x: visibleOrigin.x + point.x / zoomScale, y: visibleOrigin.y + point.y / zoomScale)
    }

    /// Records the canvas's position. Only changed values are written, to avoid needless redraws.
    func update(from canvas: FittingCanvasView) {
        guard canvas.zoomScale > 0 else { return }
        viewSize = canvas.bounds.size
        if abs(zoomScale - canvas.zoomScale) > 0.0001 { zoomScale = canvas.zoomScale }
        let origin = canvas.visibleWorldOrigin
        if origin != visibleOrigin { visibleOrigin = origin }
    }

    /// Centers the view on a world point at a zoom level.
    func show(center: CGPoint, zoom: CGFloat) {
        guard let canvas else { return }
        canvas.showWorld(center: center, zoom: min(max(zoom, Self.minimumZoom), Self.maximumZoom))
        update(from: canvas)
    }

    /// Changes the zoom while keeping the middle of the screen in place.
    func setZoom(_ zoom: CGFloat) {
        show(center: visibleCenter, zoom: zoom)
    }

    /// Zooms to show everything in `rect`, with a margin.
    func fit(_ rect: CGRect) {
        guard viewSize.width > 0, !rect.isEmpty else { return }
        let padded = rect.insetBy(dx: -80, dy: -80)
        let zoom = min(viewSize.width / padded.width, viewSize.height / padded.height)
        show(center: CGPoint(x: padded.midX, y: padded.midY), zoom: zoom)
    }
}

/// A SwiftUI wrapper around `PKCanvasView`. Only Apple Pencil draws; fingers scroll.
struct PencilCanvasView: UIViewRepresentable {
    let canvasID: AnyHashable
    let drawingData: Data?
    let layout: PencilCanvasLayout
    let session: EditorSession
    /// Paper is always light, like real paper; canvases follow the system appearance.
    var alwaysLight = false
    let onDrawingChange: (Data?) -> Void
    /// Reports the drawing's bounds after each change, in drawing coordinates.
    var onDrawingBoundsChange: ((CGRect) -> Void)?
    /// Called with a location in drawing coordinates when you Pencil-tap with the picker's Text tool,
    /// or double-tap with a finger.
    var onPlaceText: ((CGPoint) -> Void)?
    /// Called with a location in drawing coordinates for a single finger tap, such as to select a photo
    /// under the ink. Without it, a tap just deselects.
    var onFingerTap: ((CGPoint) -> Void)?
    /// For world canvases: receives the scroll position and zoom as they change.
    var viewport: CanvasViewport?

    /// Fingers, plus mouse and trackpad clicks on Mac and iPad, but never Apple Pencil, which draws.
    private static let fingerAndPointerTouches = [
        NSNumber(value: UITouch.TouchType.direct.rawValue),
        NSNumber(value: UITouch.TouchType.indirectPointer.rawValue),
    ]

    /// Apple Pencil, which always draws.
    private static let drawingTouches = [NSNumber(value: UITouch.TouchType.pencil.rawValue)]

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeUIView(context: Context) -> FittingCanvasView {
        let canvas = FittingCanvasView()
        canvas.layout = layout
        canvas.backgroundColor = .clear
        canvas.isOpaque = false
        canvas.delegate = context.coordinator
        canvas.contentInsetAdjustmentBehavior = .never
        if alwaysLight {
            canvas.overrideUserInterfaceStyle = .light
        }
        canvas.setWorldDrawing(DrawingRenderer.drawing(from: drawingData))
        canvas.onWindowMoved = { [weak coordinator = context.coordinator, weak canvas] in
            guard let canvas else { return }
            coordinator?.parent.viewport?.update(from: canvas)
        }

        viewport?.canvas = canvas

        // With the picker's Text tool, a Pencil tap places a text box.
        let textTap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.placeText(_:)))
        textTap.allowedTouchTypes = [NSNumber(value: UITouch.TouchType.pencil.rawValue)]
        textTap.isEnabled = false
        canvas.addGestureRecognizer(textTap)
        context.coordinator.textTap = textTap

        // A finger double-tap places a text box at any time, as a shortcut.
        let fingerDoubleTap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.placeText(_:)))
        fingerDoubleTap.numberOfTapsRequired = 2
        fingerDoubleTap.allowedTouchTypes = Self.fingerAndPointerTouches
        fingerDoubleTap.delegate = context.coordinator
        canvas.addGestureRecognizer(fingerDoubleTap)
        context.coordinator.fingerDoubleTap = fingerDoubleTap

        // A finger tap deselects text boxes and images. It also keeps PencilKit's own tap menu
        // (Select All, Insert Space) from appearing, since that menu has to wait for this to fail.
        let fingerTap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.deselect(_:)))
        fingerTap.allowedTouchTypes = Self.fingerAndPointerTouches
        fingerTap.require(toFail: fingerDoubleTap)
        fingerTap.delegate = context.coordinator
        canvas.addGestureRecognizer(fingerTap)
        context.coordinator.fingerTap = fingerTap

        context.coordinator.lastData = drawingData
        session.toolPicker.addObserver(canvas)
        session.toolPicker.addObserver(context.coordinator)
        return canvas
    }

    func updateUIView(_ canvas: FittingCanvasView, context: Context) {
        context.coordinator.parent = self
        canvas.layout = layout

        // Reload only when the stored data changed somewhere else, such as an iCloud sync or Undo.
        if drawingData != context.coordinator.lastData {
            context.coordinator.lastData = drawingData
            canvas.setWorldDrawing(DrawingRenderer.drawing(from: drawingData))
        }

        canvas.drawingPolicy = drawsWithAnyInput ? .anyInput : .pencilOnly
        // On Mac, PencilKit lets the trackpad draw even with the Pencil-only policy, so also limit
        // which touches the drawing gesture accepts. Set after the policy, which may reset them.
        canvas.drawingGestureRecognizer.allowedTouchTypes = drawsWithAnyInput
            ? Self.drawingTouches + Self.fingerAndPointerTouches
            : Self.drawingTouches

        // With the Text tool selected, taps place text boxes instead of drawing.
        let placesText = session.isTextToolSelected && onPlaceText != nil
        canvas.drawingGestureRecognizer.isEnabled = !placesText
        context.coordinator.textTap?.isEnabled = placesText
        context.coordinator.fingerDoubleTap?.isEnabled = onPlaceText != nil

        let isActive = session.activeCanvasID == canvasID
        let wantsTools = isActive && session.showsToolPicker
        session.toolPicker.setVisible(wantsTools, forFirstResponder: canvas)

        // Take first responder only when this canvas newly becomes the one with the tools, such as
        // switching pages or turning the tools back on. Doing it on every update would steal focus
        // from a text box you just started typing in.
        if wantsTools && !context.coordinator.wantsTools && !canvas.isFirstResponder {
            // Becoming first responder must wait until the view is in a window.
            DispatchQueue.main.async { canvas.becomeFirstResponder() }
        }
        context.coordinator.wantsTools = wantsTools
    }

    /// Apple Pencil always draws. A finger, trackpad or mouse draws only when you turn that on.
    private var drawsWithAnyInput: Bool {
        session.drawsWithTouch
    }

    static func dismantleUIView(_ canvas: FittingCanvasView, coordinator: Coordinator) {
        coordinator.flushPendingSave(canvas)
        coordinator.parent.session.toolPicker.removeObserver(canvas)
        coordinator.parent.session.toolPicker.removeObserver(coordinator)
    }

    @MainActor
    final class Coordinator: NSObject, PKCanvasViewDelegate, PKToolPickerObserver, UIGestureRecognizerDelegate {
        var parent: PencilCanvasView
        var lastData: Data?
        var textTap: UITapGestureRecognizer?
        var fingerDoubleTap: UITapGestureRecognizer?
        var fingerTap: UITapGestureRecognizer?
        /// Whether this canvas had the tools at the last update.
        var wantsTools = false

        init(_ parent: PencilCanvasView) {
            self.parent = parent
        }

        // MARK: Scrolling and zooming

        func scrollViewDidScroll(_ scrollView: UIScrollView) {
            guard let canvas = scrollView as? FittingCanvasView else { return }
            parent.viewport?.update(from: canvas)
        }

        func scrollViewDidZoom(_ scrollView: UIScrollView) {
            guard let canvas = scrollView as? FittingCanvasView else { return }
            parent.viewport?.update(from: canvas)
        }

        // MARK: Drawing

        func canvasViewDidBeginUsingTool(_ canvasView: PKCanvasView) {
            let session = parent.session
            session.selectedItemID = nil
            // Whichever canvas you start drawing on owns the tool picker. Drawing after typing in a
            // text box also brings the tools back.
            if session.activeCanvasID != parent.canvasID {
                session.activeCanvasID = parent.canvasID
            }
            if session.showsToolPicker && !canvasView.isFirstResponder {
                canvasView.becomeFirstResponder()
            }
        }

        func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) {
            guard let canvas = canvasView as? FittingCanvasView, !canvas.isReplacingDrawing else { return }
            canvas.updateContentSize()
            // Serializing a large drawing on every stroke slows writing down, so save after a short
            // pause, and serialize in the background so the next stroke isn't held up.
            pendingSave?.cancel()
            pendingSave = Task { [weak self, weak canvas] in
                try? await Task.sleep(for: .milliseconds(400))
                guard !Task.isCancelled, let drawing = canvas?.drawing else { return }
                let data = await Task.detached(priority: .userInitiated) {
                    DrawingRenderer.data(for: drawing)
                }.value
                // A newer stroke replaces this save with its own.
                guard !Task.isCancelled else { return }
                self?.store(data, bounds: drawing.bounds)
            }
        }

        private var pendingSave: Task<Void, Never>?

        /// Saves the drawing right away, such as when the editor closes.
        func save(_ canvas: FittingCanvasView) {
            store(DrawingRenderer.data(for: canvas.drawing), bounds: canvas.drawing.bounds)
        }

        private func store(_ data: Data?, bounds: CGRect) {
            pendingSave?.cancel()
            pendingSave = nil
            guard data != lastData else { return }
            lastData = data
            parent.onDrawingChange(data)
            parent.onDrawingBoundsChange?(bounds)
        }

        /// Saves any change that's still waiting, such as when the editor closes.
        func flushPendingSave(_ canvas: FittingCanvasView) {
            if pendingSave != nil { save(canvas) }
        }

        func toolPickerSelectedToolItemDidChange(_ toolPicker: PKToolPicker) {
            let isText = toolPicker.selectedToolItemIdentifier == EditorSession.textToolIdentifier
            if parent.session.isTextToolSelected != isText {
                parent.session.isTextToolSelected = isText
            }
        }

        // MARK: Taps

        @objc func deselect(_ recognizer: UITapGestureRecognizer) {
            if let onFingerTap = parent.onFingerTap, let canvas = recognizer.view as? FittingCanvasView {
                onFingerTap(canvas.worldPoint(for: recognizer.location(in: canvas)))
            } else if parent.session.selectedItemID != nil {
                parent.session.selectedItemID = nil
            }
        }

        @objc func placeText(_ recognizer: UITapGestureRecognizer) {
            guard let canvas = recognizer.view as? FittingCanvasView else { return }
            parent.onPlaceText?(canvas.worldPoint(for: recognizer.location(in: canvas)))
        }

        /// Makes PencilKit's built-in tap recognizers wait for ours to fail. Ours always succeed on a
        /// finger tap, so PencilKit's tap menu never opens.
        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldBeRequiredToFailBy otherGestureRecognizer: UIGestureRecognizer
        ) -> Bool {
            guard otherGestureRecognizer is UITapGestureRecognizer,
                  otherGestureRecognizer !== fingerTap,
                  otherGestureRecognizer !== fingerDoubleTap,
                  otherGestureRecognizer !== textTap,
                  let canvas = gestureRecognizer.view,
                  let otherView = otherGestureRecognizer.view
            else { return false }
            return otherView.isDescendant(of: canvas)
        }
    }
}

/// A `PKCanvasView` that keeps its drawing in fixed logical coordinates and zooms to fit its width.
final class FittingCanvasView: PKCanvasView {
    var layout: PencilCanvasLayout = .infinite(width: 1024) {
        didSet {
            if layout != oldValue { lastFittedWidth = 0; setNeedsLayout() }
        }
    }

    /// Set while the drawing is replaced in code, so the change isn't saved as an edit.
    private(set) var isReplacingDrawing = false
    /// Called after the view is moved or zoomed in code.
    var onWindowMoved: (() -> Void)?

    /// Hides Select All and Insert Space from PencilKit's edit menu. Lasso actions like Copy and Delete stay.
    override func canPerformAction(_ action: Selector, withSender sender: Any?) -> Bool {
        let name = NSStringFromSelector(action)
        if action == #selector(selectAll(_:)) || name.localizedCaseInsensitiveContains("insertSpace") {
            return false
        }
        return super.canPerformAction(action, withSender: sender)
    }

    /// Extra space below the lowest stroke on an infinite canvas, in drawing coordinates.
    private let overscroll: CGFloat = 800
    private var lastFittedWidth: CGFloat = 0
    private var lastFittedHeight: CGFloat = 0

    // MARK: Drawing

    /// Replaces the drawing with one loaded from storage, without treating it as an edit.
    func setWorldDrawing(_ world: PKDrawing) {
        isReplacingDrawing = true
        drawing = world
        isReplacingDrawing = false
    }

    /// Converts a location in this view (which includes the scroll offset) to drawing coordinates.
    func worldPoint(for location: CGPoint) -> CGPoint {
        guard zoomScale > 0 else { return location }
        return CGPoint(x: location.x / zoomScale, y: location.y / zoomScale)
    }

    /// The drawing coordinate at the top-leading corner of the screen.
    var visibleWorldOrigin: CGPoint {
        worldPoint(for: contentOffset)
    }

    // MARK: World canvas

    /// Centers the screen on a world point at a zoom level.
    func showWorld(center: CGPoint, zoom: CGFloat) {
        guard case .world(let worldSize, _) = layout, bounds.width > 0 else { return }
        // Zooming out stops once the whole world fits on screen.
        minimumZoomScale = max(CanvasViewport.minimumZoom, max(bounds.width / worldSize.width, bounds.height / worldSize.height))
        maximumZoomScale = CanvasViewport.maximumZoom
        zoomScale = min(max(zoom, minimumZoomScale), maximumZoomScale)
        updateContentSize()
        let offset = CGPoint(x: center.x * zoomScale - bounds.width / 2, y: center.y * zoomScale - bounds.height / 2)
        contentOffset = CGPoint(
            x: min(max(offset.x, 0), max(contentSize.width - bounds.width, 0)),
            y: min(max(offset.y, 0), max(contentSize.height - bounds.height, 0))
        )
        onWindowMoved?()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        // A world canvas also refits when only its height changes, such as when iPhone Duo folds.
        let sizeChanged = bounds.width != lastFittedWidth || (layout.isWorld && bounds.height != lastFittedHeight)
        guard bounds.width > 0, sizeChanged else { return }
        let isFirstLayout = lastFittedWidth == 0
        let previousSize = CGSize(width: lastFittedWidth, height: lastFittedHeight)
        lastFittedWidth = bounds.width
        lastFittedHeight = bounds.height

        switch layout {
        case .page(let size):
            // Pages scale with the view and never scroll on their own; the notebook scrolls instead.
            let fitScale = bounds.width / size.width
            isScrollEnabled = false
            minimumZoomScale = fitScale
            maximumZoomScale = fitScale
            zoomScale = fitScale
            updateContentSize()
        case .infinite(let width):
            let fitScale = bounds.width / width
            isScrollEnabled = true
            minimumZoomScale = fitScale
            maximumZoomScale = fitScale * 4
            zoomScale = fitScale
            updateContentSize()
        case .world(_, let focus):
            isScrollEnabled = true
            if isFirstLayout {
                showWorld(center: focus, zoom: 1)
            } else if zoomScale > 0 {
                // The window was resized; keep what was in the middle before in the middle now.
                let center = worldPoint(for: CGPoint(
                    x: contentOffset.x + previousSize.width / 2,
                    y: contentOffset.y + previousSize.height / 2
                ))
                showWorld(center: center, zoom: zoomScale)
            }
        }
    }

    /// Content size is expressed in zoomed coordinates.
    func updateContentSize() {
        switch layout {
        case .page(let size), .world(let size, _):
            contentSize = CGSize(width: size.width * zoomScale, height: size.height * zoomScale)
        case .infinite(let width):
            let drawingBottom = drawing.bounds.isNull ? 0 : drawing.bounds.maxY
            let height = max(bounds.height, (drawingBottom + overscroll) * zoomScale)
            contentSize = CGSize(width: width * zoomScale, height: height)
        }
    }
}
