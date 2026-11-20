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
}

/// Shared drawing state for every canvas in an editor, such as one tool picker for all pages of a notebook.
@Observable
final class DrawingSession {
    let toolPicker = PKToolPicker()
    /// Whether the tool picker is shown.
    var showsToolPicker = true
    /// When off, only Apple Pencil draws and fingers scroll.
    var allowsFingerDrawing = false
    /// The canvas that should receive the tool picker.
    var activeCanvasID: AnyHashable?

    init() {
        // Follow the system "Only Draw with Apple Pencil" setting, which is on once a Pencil is paired.
        #if os(iOS)
        allowsFingerDrawing = !UIPencilInteraction.prefersPencilOnlyDrawing
        #else
        allowsFingerDrawing = true
        #endif
    }
}

/// A SwiftUI wrapper around `PKCanvasView`.
struct PencilCanvasView: UIViewRepresentable {
    let canvasID: AnyHashable
    let drawingData: Data?
    let layout: PencilCanvasLayout
    let session: DrawingSession
    /// Paper is always light, like real paper; canvases follow the system appearance.
    var alwaysLight = false
    let onDrawingChange: (Data?) -> Void

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
        if alwaysLight {
            canvas.overrideUserInterfaceStyle = .light
        }
        context.coordinator.lastData = drawingData
        session.toolPicker.addObserver(canvas)
        return canvas
    }

    func updateUIView(_ canvas: FittingCanvasView, context: Context) {
        context.coordinator.parent = self
        canvas.layout = layout
        canvas.drawingPolicy = session.allowsFingerDrawing ? .anyInput : .pencilOnly

        // Reload only when the stored data changed somewhere else, such as an iCloud sync.
        if drawingData != context.coordinator.lastData {
            context.coordinator.lastData = drawingData
            canvas.drawing = DrawingRenderer.drawing(from: drawingData)
        }

        let isActive = session.activeCanvasID == canvasID
        session.toolPicker.setVisible(session.showsToolPicker && isActive, forFirstResponder: canvas)
        if isActive && session.showsToolPicker && !canvas.isFirstResponder {
            // Becoming first responder must wait until the view is in a window.
            DispatchQueue.main.async { canvas.becomeFirstResponder() }
        }
    }

    static func dismantleUIView(_ canvas: FittingCanvasView, coordinator: Coordinator) {
        coordinator.parent.session.toolPicker.removeObserver(canvas)
    }

    @MainActor
    final class Coordinator: NSObject, PKCanvasViewDelegate {
        var parent: PencilCanvasView
        var lastData: Data?

        init(_ parent: PencilCanvasView) {
            self.parent = parent
        }

        func canvasViewDidBeginUsingTool(_ canvasView: PKCanvasView) {
            // Whichever canvas you start drawing on owns the tool picker.
            if parent.session.activeCanvasID != parent.canvasID {
                parent.session.activeCanvasID = parent.canvasID
            }
        }

        func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) {
            (canvasView as? FittingCanvasView)?.updateContentSize()
            let data = DrawingRenderer.data(for: canvasView.drawing)
            lastData = data
            parent.onDrawingChange(data)
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

    /// Extra space below the lowest stroke on an infinite canvas, in drawing coordinates.
    private let overscroll: CGFloat = 800
    private var lastFittedWidth: CGFloat = 0

    override func layoutSubviews() {
        super.layoutSubviews()
        guard bounds.width > 0, bounds.width != lastFittedWidth else { return }
        lastFittedWidth = bounds.width

        let fitScale = bounds.width / logicalWidth
        switch layout {
        case .page:
            // Pages scale with the view and never scroll on their own; the notebook scrolls instead.
            isScrollEnabled = false
            minimumZoomScale = fitScale
            maximumZoomScale = fitScale
        case .infinite:
            isScrollEnabled = true
            minimumZoomScale = fitScale
            maximumZoomScale = fitScale * 4
        }
        zoomScale = fitScale
        updateContentSize()
    }

    private var logicalWidth: CGFloat {
        switch layout {
        case .page(let size): size.width
        case .infinite(let width): width
        }
    }

    /// Content size is expressed in zoomed coordinates.
    func updateContentSize() {
        switch layout {
        case .page(let size):
            contentSize = CGSize(width: size.width * zoomScale, height: size.height * zoomScale)
        case .infinite(let width):
            let drawingBottom = drawing.bounds.isNull ? 0 : drawing.bounds.maxY
            let height = max(bounds.height, (drawingBottom + overscroll) * zoomScale)
            contentSize = CGSize(width: width * zoomScale, height: height)
        }
    }
}
#endif
