#if canImport(UIKit)
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
}

/// The visible part of a world canvas. The items layer follows it so text boxes and images move with the ink,
/// the toolbar shows its zoom, and scenes use it to move the view.
@MainActor
@Observable
final class CanvasViewport {
    /// The scroll position, in zoomed points. Observed by the items layer so it tracks scrolling.
    var contentOffset: CGPoint = .zero
    /// Observed by the items layer and the toolbar's zoom percentage.
    var zoomScale: CGFloat = 1
    /// The canvas view's size on screen.
    @ObservationIgnored var viewSize: CGSize = .zero

    static let minimumZoom: CGFloat = 0.1
    static let maximumZoom: CGFloat = 4

    @ObservationIgnored weak var scrollView: UIScrollView?
    @ObservationIgnored var worldSize: CGSize = .zero

    /// The visible area in canvas coordinates.
    var visibleRect: CGRect {
        guard zoomScale > 0 else { return .zero }
        return CGRect(
            x: contentOffset.x / zoomScale,
            y: contentOffset.y / zoomScale,
            width: viewSize.width / zoomScale,
            height: viewSize.height / zoomScale
        )
    }

    var visibleCenter: CGPoint {
        CGPoint(x: visibleRect.midX, y: visibleRect.midY)
    }

    /// Converts a point in the canvas view (such as a drop location) to canvas coordinates.
    func canvasPoint(forViewPoint point: CGPoint) -> CGPoint {
        CGPoint(x: (contentOffset.x + point.x) / zoomScale, y: (contentOffset.y + point.y) / zoomScale)
    }

    /// Records the scroll view's position. Only changed values are written, to avoid needless redraws.
    func update(from scrollView: UIScrollView) {
        guard scrollView.zoomScale > 0 else { return }
        viewSize = scrollView.bounds.size
        if abs(zoomScale - scrollView.zoomScale) > 0.0001 { zoomScale = scrollView.zoomScale }
        if contentOffset != scrollView.contentOffset { contentOffset = scrollView.contentOffset }
    }

    /// Centers the view on a point at a zoom level.
    func show(center: CGPoint, zoom: CGFloat, animated: Bool = true) {
        guard let scrollView, scrollView.bounds.width > 0 else { return }
        let zoom = min(max(zoom, Self.minimumZoom), Self.maximumZoom)
        let bounds = scrollView.bounds.size
        let contentSize = CGSize(width: worldSize.width * zoom, height: worldSize.height * zoom)
        let offset = CGPoint(
            x: min(max(center.x * zoom - bounds.width / 2, 0), max(contentSize.width - bounds.width, 0)),
            y: min(max(center.y * zoom - bounds.height / 2, 0), max(contentSize.height - bounds.height, 0))
        )
        let move = {
            scrollView.zoomScale = zoom
            scrollView.contentOffset = offset
        }
        if animated {
            UIView.animate(withDuration: 0.35, delay: 0, options: [.curveEaseInOut], animations: move) { _ in
                self.update(from: scrollView)
            }
        } else {
            move()
            update(from: scrollView)
        }
    }

    /// Changes the zoom while keeping the middle of the screen in place.
    func setZoom(_ zoom: CGFloat) {
        show(center: visibleCenter, zoom: zoom)
    }

    /// Zooms to show everything in `rect`, with a margin.
    func fit(_ rect: CGRect) {
        guard let scrollView, !rect.isEmpty else { return }
        let padded = rect.insetBy(dx: -80, dy: -80)
        let zoom = min(scrollView.bounds.width / padded.width, scrollView.bounds.height / padded.height)
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

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeUIView(context: Context) -> FittingCanvasView {
        let canvas = FittingCanvasView()
        canvas.layout = layout
        canvas.backgroundColor = .clear
        canvas.isOpaque = false
        canvas.drawing = DrawingRenderer.drawing(from: drawingData)
        canvas.delegate = context.coordinator
        canvas.contentInsetAdjustmentBehavior = .never
        canvas.drawingPolicy = .pencilOnly
        if alwaysLight {
            canvas.overrideUserInterfaceStyle = .light
        }

        if let viewport {
            viewport.scrollView = canvas
            if case .world(let size, _) = layout { viewport.worldSize = size }
        }

        // With the picker's Text tool, a Pencil tap places a text box.
        let textTap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.placeText(_:)))
        textTap.allowedTouchTypes = [NSNumber(value: UITouch.TouchType.pencil.rawValue)]
        textTap.isEnabled = false
        canvas.addGestureRecognizer(textTap)
        context.coordinator.textTap = textTap

        // A finger double-tap places a text box at any time, as a shortcut.
        let fingerDoubleTap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.placeText(_:)))
        fingerDoubleTap.numberOfTapsRequired = 2
        fingerDoubleTap.allowedTouchTypes = [NSNumber(value: UITouch.TouchType.direct.rawValue)]
        fingerDoubleTap.delegate = context.coordinator
        canvas.addGestureRecognizer(fingerDoubleTap)
        context.coordinator.fingerDoubleTap = fingerDoubleTap

        // A finger tap deselects text boxes and images. It also keeps PencilKit's own tap menu
        // (Select All, Insert Space) from appearing, since that menu has to wait for this to fail.
        let fingerTap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.deselect(_:)))
        fingerTap.allowedTouchTypes = [NSNumber(value: UITouch.TouchType.direct.rawValue)]
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

        // Reload only when the stored data changed somewhere else, such as an iCloud sync.
        if drawingData != context.coordinator.lastData {
            context.coordinator.lastData = drawingData
            canvas.drawing = DrawingRenderer.drawing(from: drawingData)
        }

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

    static func dismantleUIView(_ canvas: FittingCanvasView, coordinator: Coordinator) {
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
            parent.viewport?.update(from: scrollView)
        }

        func scrollViewDidZoom(_ scrollView: UIScrollView) {
            parent.viewport?.update(from: scrollView)
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
            (canvasView as? FittingCanvasView)?.updateContentSize()
            let data = DrawingRenderer.data(for: canvasView.drawing)
            lastData = data
            parent.onDrawingChange(data)
            parent.onDrawingBoundsChange?(canvasView.drawing.bounds)
        }

        func toolPickerSelectedToolItemDidChange(_ toolPicker: PKToolPicker) {
            let isText = toolPicker.selectedToolItemIdentifier == EditorSession.textToolIdentifier
            if parent.session.isTextToolSelected != isText {
                parent.session.isTextToolSelected = isText
            }
        }

        // MARK: Taps

        @objc func deselect(_ recognizer: UITapGestureRecognizer) {
            if let onFingerTap = parent.onFingerTap,
               let canvas = recognizer.view as? PKCanvasView, canvas.zoomScale > 0 {
                let location = recognizer.location(in: canvas)
                onFingerTap(CGPoint(x: location.x / canvas.zoomScale, y: location.y / canvas.zoomScale))
            } else if parent.session.selectedItemID != nil {
                parent.session.selectedItemID = nil
            }
        }

        @objc func placeText(_ recognizer: UITapGestureRecognizer) {
            guard let canvas = recognizer.view as? PKCanvasView, canvas.zoomScale > 0 else { return }
            // Locations in a scroll view already include the scroll offset.
            let location = recognizer.location(in: canvas)
            parent.onPlaceText?(CGPoint(x: location.x / canvas.zoomScale, y: location.y / canvas.zoomScale))
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

    override func layoutSubviews() {
        super.layoutSubviews()
        guard bounds.width > 0, bounds.width != lastFittedWidth else { return }
        let isFirstLayout = lastFittedWidth == 0
        lastFittedWidth = bounds.width

        switch layout {
        case .page(let size):
            // Pages scale with the view and never scroll on their own; the notebook scrolls instead.
            let fitScale = bounds.width / size.width
            isScrollEnabled = false
            minimumZoomScale = fitScale
            maximumZoomScale = fitScale
            zoomScale = fitScale
        case .infinite(let width):
            let fitScale = bounds.width / width
            isScrollEnabled = true
            minimumZoomScale = fitScale
            maximumZoomScale = fitScale * 4
            zoomScale = fitScale
        case .world(_, let focus):
            isScrollEnabled = true
            minimumZoomScale = CanvasViewport.minimumZoom
            maximumZoomScale = CanvasViewport.maximumZoom
            guard isFirstLayout else { return }
            zoomScale = 1
            updateContentSize()
            // Open with `focus` in the middle of the screen.
            let offset = CGPoint(x: focus.x * zoomScale - bounds.width / 2, y: focus.y * zoomScale - bounds.height / 2)
            contentOffset = CGPoint(
                x: min(max(offset.x, 0), max(contentSize.width - bounds.width, 0)),
                y: min(max(offset.y, 0), max(contentSize.height - bounds.height, 0))
            )
            return
        }
        updateContentSize()
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
#endif
