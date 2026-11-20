import SwiftUI
import SwiftData

/// A freeform drawing surface that grows downward as you draw.
struct CanvasNotepadView: View {
    @Bindable var notepad: Notepad
    #if canImport(UIKit)
    @State private var session = DrawingSession()
    #endif

    /// The canvas's logical width. Drawings scale to fit the screen, so they look the same on every device.
    static let logicalWidth: CGFloat = 1200
    private let canvasID = "canvas"

    var body: some View {
        content
            .background(.background)
            .navigationTitle($notepad.title)
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            .toolbarRole(.editor)
            .ignoresSafeArea(.container, edges: .bottom)
            #endif
            #if canImport(UIKit)
            .toolbar { DrawingToolbarItems(session: session) }
            .onAppear { session.activeCanvasID = canvasID }
            #endif
    }

    @ViewBuilder
    private var content: some View {
        #if canImport(UIKit)
        PencilCanvasView(
            canvasID: canvasID,
            drawingData: notepad.canvasDrawingData,
            layout: .infinite(width: Self.logicalWidth),
            session: session
        ) { data in
            notepad.canvasDrawingData = data
            notepad.touch()
        }
        #else
        CanvasPreview(drawingData: notepad.canvasDrawingData)
        #endif
    }
}

#if !canImport(UIKit)
/// Read-only canvas for Mac, where PencilKit drawing isn't available.
private struct CanvasPreview: View {
    let drawingData: Data?
    @Environment(\.displayScale) private var displayScale
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        GeometryReader { proxy in
            let drawing = DrawingRenderer.drawing(from: drawingData)
            if drawing.strokes.isEmpty {
                ContentUnavailableView(
                    "Empty Canvas",
                    systemImage: "scribble.variable",
                    description: Text("Draw on this canvas with your iPad or iPhone.")
                )
            } else {
                let fitScale = proxy.size.width / CanvasNotepadView.logicalWidth
                let rect = CGRect(x: 0, y: 0, width: CanvasNotepadView.logicalWidth, height: drawing.bounds.maxY + 40)
                let pixelScale = fitScale * displayScale
                let dark = colorScheme == .dark
                ScrollView {
                    AsyncRenderedImage(key: [AnyHashable(drawingData), AnyHashable(pixelScale), AnyHashable(dark)]) {
                        DrawingRenderer.image(from: drawingData, rect: rect, scale: pixelScale, dark: dark)
                    } placeholder: {
                        ProgressView()
                    }
                    .frame(width: rect.width * fitScale, height: rect.height * fitScale)
                }
            }
        }
    }
}
#endif
