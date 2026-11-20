import SwiftUI
import SwiftData

/// A paper notebook: a vertical stack of fixed-size pages that grows as you fill it.
struct NotebookView: View {
    @Bindable var notepad: Notepad
    @State private var renderer: PDFPageRenderer?
    #if canImport(UIKit)
    @State private var session = DrawingSession()
    #endif

    /// Pages never get wider than this, so they stay comfortable to read on large displays.
    private let maximumPageWidth: CGFloat = 900

    var body: some View {
        let pages = notepad.sortedPages

        GeometryReader { proxy in
            let pageWidth = max(100, min(proxy.size.width - 32, maximumPageWidth))

            ScrollView {
                LazyVStack(spacing: 24) {
                    ForEach(Array(pages.enumerated()), id: \.element.pageID) { position, page in
                        pageView(page, width: pageWidth)
                            .accessibilityLabel("Page \(position + 1) of \(pages.count)")
                            .onAppear {
                                // Reaching the last page makes sure there's another blank page to continue on.
                                if position == pages.count - 1 {
                                    notepad.ensureTrailingBlankPage()
                                }
                            }
                    }
                }
                .padding(.vertical, 24)
                .frame(maxWidth: .infinity)
            }
        }
        .background(.background.secondary)
        .navigationTitle($notepad.title)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarRole(.editor)
        #endif
        .toolbar {
            #if canImport(UIKit)
            DrawingToolbarItems(session: session)
            #endif
            ToolbarItem(placement: .secondaryAction) {
                Menu {
                    Picker("Paper", selection: $notepad.paperStyle) {
                        ForEach(PaperStyle.allCases) { style in
                            Label(style.displayName, systemImage: style.systemImageName).tag(style)
                        }
                    }
                    Button("Add Page", systemImage: "doc.badge.plus") {
                        notepad.appendPage()
                    }
                } label: {
                    Label("Notebook Options", systemImage: "doc.text")
                }
            }
        }
        .task(id: notepad.persistentModelID) {
            if notepad.pdfData != nil {
                renderer = PDFPageRenderer(data: notepad.pdfData)
            }
            if notepad.pages?.isEmpty ?? true {
                notepad.appendPage()
            }
            #if canImport(UIKit)
            if session.activeCanvasID == nil {
                session.activeCanvasID = notepad.sortedPages.first?.pageID
            }
            #endif
        }
    }

    @ViewBuilder
    private func pageView(_ page: NotebookPage, width: CGFloat) -> some View {
        #if canImport(UIKit)
        NotebookPageView(page: page, style: notepad.paperStyle, renderer: renderer, displayWidth: width, session: session) {
            notepad.ensureTrailingBlankPage()
        }
        #else
        NotebookPageView(page: page, style: notepad.paperStyle, renderer: renderer, displayWidth: width)
        #endif
    }
}

/// One sheet of paper: the background (paper pattern or PDF page) with ink on top.
struct NotebookPageView: View {
    let page: NotebookPage
    let style: PaperStyle
    let renderer: PDFPageRenderer?
    let displayWidth: CGFloat
    #if canImport(UIKit)
    let session: DrawingSession
    var onDrawingChange: () -> Void = {}
    #endif

    @Environment(\.displayScale) private var displayScale

    var body: some View {
        ZStack {
            Color.white

            if let pdfPageIndex = page.pdfPageIndex {
                pdfBackground(pageIndex: pdfPageIndex)
            } else {
                PaperBackground(style: style, pageSize: page.size)
            }

            ink
        }
        .frame(width: displayWidth, height: displayWidth * page.height / page.width)
        .clipShape(.rect(cornerRadius: 3))
        .shadow(color: .black.opacity(0.15), radius: 4, y: 2)
    }

    private func pdfBackground(pageIndex: Int) -> some View {
        let pixelWidth = (displayWidth * displayScale).rounded()
        let renderer = renderer
        return AsyncRenderedImage(key: [AnyHashable(pageIndex), AnyHashable(pixelWidth), AnyHashable(renderer == nil)]) {
            await renderer?.image(ofPage: pageIndex, pixelWidth: pixelWidth)
        } placeholder: {
            ProgressView()
        }
    }

    @ViewBuilder
    private var ink: some View {
        #if canImport(UIKit)
        PencilCanvasView(
            canvasID: page.pageID,
            drawingData: page.drawingData,
            layout: .page(page.size),
            session: session,
            alwaysLight: true
        ) { data in
            page.drawingData = data
            page.notepad?.touch()
            onDrawingChange()
        }
        #else
        // Drawing isn't available on Mac, so show the page's ink as an image.
        if let data = page.drawingData {
            let scale = displayWidth / page.width * displayScale
            let rect = CGRect(origin: .zero, size: page.size)
            AsyncRenderedImage(key: [AnyHashable(data), AnyHashable(scale)]) {
                DrawingRenderer.image(from: data, rect: rect, scale: scale)
            } placeholder: {
                Color.clear
            }
        }
        #endif
    }
}
