import SwiftUI
import SwiftData

/// A paper notebook: a vertical stack of fixed-size pages that grows as you fill it.
/// Pages take Apple Pencil ink, text boxes and images.
struct NotebookView: View {
    @Bindable var notepad: Notepad
    @Environment(\.modelContext) private var modelContext
    @Environment(\.undoManager) private var undoManager
    @State private var renderer: PDFPageRenderer?
    @State private var session = EditorSession()
    /// The page that toolbar actions, like Add Text Box, apply to.
    @State private var visiblePageID: UUID?
    @State private var zoom = NotebookZoom.fitToScreen
    @State private var viewSize = CGSize.zero
    @State private var scrollPosition = ScrollPosition(idType: UUID.self)

    /// Screen points per point of paper.
    private func pageScale(firstPage: NotebookPage?) -> CGFloat {
        switch zoom {
        case .fitToScreen: fitScale(firstPage: firstPage)
        case .percent(let percent): percent * PhysicalScreen.actualSizeScale
        }
    }

    /// The scale that fits a whole page on screen, with a margin around it.
    private func fitScale(firstPage: NotebookPage?) -> CGFloat {
        let page = firstPage?.size ?? notepad.paperSize.size
        guard page.width > 0, page.height > 0, viewSize.width > 0 else { return 1 }
        return max(0.05, min((viewSize.width - 32) / page.width, (viewSize.height - 48) / page.height))
    }

    var body: some View {
        let pages = notepad.sortedPages
        let scale = pageScale(firstPage: pages.first)

        PinchZoomScrollView(
            zoom: scale / PhysicalScreen.actualSizeScale,
            minimumWidth: viewSize.width,
            scrollPosition: $scrollPosition,
            onPinchEnded: { zoom = .percent($0) }
        ) {
            LazyVStack(spacing: 24) {
                ForEach(Array(pages.enumerated()), id: \.element.pageID) { position, page in
                    NotebookPageView(
                        page: page,
                        style: notepad.paperStyle,
                        renderer: renderer,
                        displayWidth: page.size.width * scale,
                        session: session,
                        onPlaceText: { addTextBox(on: page, at: $0) },
                        onDropImages: { addImages($0, on: page, centeredAt: $1) },
                        onDeleteItem: delete,
                        onContentChange: { notepad.ensureTrailingBlankPage() }
                    )
                    .accessibilityLabel("Page \(position + 1) of \(pages.count)")
                    .onScrollVisibilityChange(threshold: 0.3) { isVisible in
                        if isVisible { visiblePageID = page.pageID }
                    }
                    .onAppear {
                        // Reaching the last page makes sure there's another blank page to continue on.
                        if position == pages.count - 1 {
                            notepad.ensureTrailingBlankPage()
                        }
                    }
                }
            }
            .padding(.vertical, 24)
            .padding(.horizontal, 16)
        }
        // The window's visible area: the scroll view reaches under the toolbar, which would
        // otherwise cover part of a page that's meant to fit.
        .onGeometryChange(for: CGSize.self) { proxy in
            let insets = proxy.safeAreaInsets
            return CGSize(
                width: proxy.size.width - insets.leading - insets.trailing,
                height: proxy.size.height - insets.top - insets.bottom
            )
        } action: { size in
            viewSize = size
            // Keep the page fitted as the window is resized.
            if zoom == .fitToScreen { centerVisiblePage() }
        }
        .background(.background.secondary)
        .navigationTitle($notepad.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarRole(.editor)
        .editorToolbar(
            session: session,
            leadingTool: .pencil,
            // In the same spot as a canvas's Scenes and Zoom.
            contextTools: [AnyView(paperStyleMenu), AnyView(zoomMenu(scale: scale))],
            showsFontSizes: true,
            onAddTextBox: {
                if let page = currentPage { addTextBox(on: page, at: nil) }
            },
            onImportImages: { images in
                if let page = currentPage { addImages(images, on: page, centeredAt: nil) }
            }
        )
        .task(id: notepad.persistentModelID) {
            if notepad.pdfData != nil {
                renderer = PDFPageRenderer(data: notepad.pdfData)
            }
            if notepad.pages?.isEmpty ?? true {
                notepad.appendPage()
            }
            if session.activeCanvasID == nil {
                session.activeCanvasID = notepad.sortedPages.first?.pageID
            }
        }
    }

    private var paperStyleMenu: some View {
        Menu {
            Picker("Paper", selection: $notepad.paperStyle) {
                ForEach(PaperStyle.allCases) { style in
                    Label(style.displayName, systemImage: style.systemImageName).tag(style)
                }
            }
            .pickerStyle(.inline)
            Divider()
            Button("Add Page", systemImage: "doc.badge.plus") {
                notepad.appendPage()
            }
        } label: {
            // The icon shows the current paper style.
            Label("Paper Style", systemImage: notepad.paperStyle.systemImageName)
        }
    }

    /// 100% shows the paper at its real size. Fit to Screen shows a whole page.
    private func zoomMenu(scale: CGFloat) -> some View {
        CanvasZoomMenu(
            zoom: scale / PhysicalScreen.actualSizeScale,
            levels: NotebookZoom.levels,
            fitTitle: "Fit to Screen",
            onSelect: { zoom = .percent($0) },
            onZoomToFit: {
                zoom = .fitToScreen
                centerVisiblePage()
            }
        )
    }

    /// Scrolls the page you're on to the middle of the window, so a fitted page is shown whole
    /// rather than split across two.
    private func centerVisiblePage() {
        guard let page = currentPage else { return }
        scrollPosition.scrollTo(id: page.pageID, anchor: .center)
    }

    private var currentPage: NotebookPage? {
        let pages = notepad.sortedPages
        return pages.first { $0.pageID == visiblePageID } ?? pages.first
    }

    // MARK: Placing items

    private func addTextBox(on page: NotebookPage, at point: CGPoint?) {
        // Without a tap location, stack new boxes down the page so they don't cover each other.
        let stagger = CGFloat((page.items?.count ?? 0) % 12) * 36
        let origin = point.map { CGPoint(x: $0.x, y: $0.y - 16) } ?? CGPoint(x: 48, y: 72 + stagger)
        let item = PlacedItemFactory.textBox(at: origin, in: page.size)
        insert([item], on: page)
        session.selectedItemID = item.itemID
        session.pendingFocusItemID = item.itemID
    }

    private func addImages(_ images: [Data], on page: NotebookPage, centeredAt center: CGPoint?) {
        let items = PlacedItemFactory.images(images, center: center, fallbackOrigin: CGPoint(x: 48, y: 72), in: page.size)
        insert(items, on: page)
        session.selectedItemID = items.last?.itemID
    }

    private func insert(_ items: [PlacedItem], on page: NotebookPage) {
        let isImage = items.first?.kind == .image
        PlacedItemUndo.insert(
            items,
            onPage: page,
            context: modelContext,
            undoManager: undoManager,
            actionName: isImage ? String(localized: "Add Image") : String(localized: "Add Text Box")
        )
        notepad.touch()
        notepad.ensureTrailingBlankPage()
    }

    private func delete(_ item: PlacedItem) {
        session.forget(item)
        PlacedItemUndo.delete(item, context: modelContext, undoManager: undoManager)
    }
}

/// Scrolls the notebook's pages and pinches to zoom them.
///
/// The pinch lives here rather than in `NotebookView`, so each frame of a pinch only updates this
/// view's magnification. The pages are built by the notebook and don't change until the pinch ends.
private struct PinchZoomScrollView<Content: View>: View {
    /// The current zoom, as a fraction of the paper's real size.
    let zoom: CGFloat
    /// Pages narrower than this are centered.
    let minimumWidth: CGFloat
    @Binding var scrollPosition: ScrollPosition
    /// Receives the new zoom when a pinch ends.
    let onPinchEnded: (CGFloat) -> Void
    @ViewBuilder let content: Content

    /// The in-progress pinch, as a multiple of the current zoom.
    @GestureState private var pinch: CGFloat = 1

    var body: some View {
        // Scrolls sideways too, for pages zoomed wider than the screen.
        ScrollView([.vertical, .horizontal]) {
            content
                .frame(minWidth: minimumWidth)
                // While pinching, the pages are only magnified, which is cheap. They're laid out at
                // the new size once, when the pinch ends.
                .scaleEffect(clampedPinch(pinch), anchor: .top)
        }
        .scrollPosition($scrollPosition)
        .simultaneousGesture(
            // Pinching zooms between the smallest and largest menu levels.
            MagnifyGesture()
                .updating($pinch) { value, state, _ in state = value.magnification }
                .onEnded { value in onPinchEnded(zoom * clampedPinch(value.magnification)) }
        )
    }

    /// Limits a pinch so the zoom stays within the menu's range.
    private func clampedPinch(_ magnification: CGFloat) -> CGFloat {
        guard zoom > 0 else { return 1 }
        let target = min(max(zoom * magnification, NotebookZoom.minimum), NotebookZoom.maximum)
        return target / zoom
    }
}

/// How big notebook pages are drawn.
enum NotebookZoom: Equatable {
    /// A whole page fits on screen. This changes with the window size.
    case fitToScreen
    /// A fraction of the paper's real size, where 1 is 100%.
    case percent(CGFloat)

    /// Larger sizes would make each page's layers too big for the GPU on some devices.
    static let levels: [CGFloat] = [0.5, 0.75, 1, 1.25, 1.5]
    /// The range pinching can reach.
    static let minimum: CGFloat = 0.25
    static let maximum: CGFloat = 1.5
}

/// The screen's size in the real world, so a notebook at 100% matches the paper.
enum PhysicalScreen {
    /// Screen points per inch. Approximate, since it varies slightly between models: about 153 on
    /// iPhone, 132 on iPad, and 127 on a Mac laptop at its default resolution.
    static var pointsPerInch: CGFloat {
        if ProcessInfo.processInfo.isMacCatalystApp { return 127 }
        return UITraitCollection.current.userInterfaceIdiom == .phone ? 153 : 132
    }

    /// Screen points for one point of paper (1/72 inch) at 100%.
    static var actualSizeScale: CGFloat { pointsPerInch / 72 }
}

/// One sheet of paper: the paper pattern or PDF page, ink, and any text boxes and images.
struct NotebookPageView: View {
    let page: NotebookPage
    let style: PaperStyle
    let renderer: PDFPageRenderer?
    let displayWidth: CGFloat
    let session: EditorSession
    let onPlaceText: (CGPoint) -> Void
    let onDropImages: ([Data], CGPoint) -> Void
    let onDeleteItem: (PlacedItem) -> Void
    var onContentChange: () -> Void = {}

    @Environment(\.displayScale) private var displayScale

    var body: some View {
        DrawingSurface(
            canvasID: page.pageID,
            logicalSize: page.size,
            displayWidth: displayWidth,
            drawingData: page.drawingData,
            items: page.sortedItems,
            session: session,
            alwaysLight: true,
            onDrawingChange: { data in
                page.drawingData = data
                page.notepad?.touch()
                onContentChange()
            },
            onPlaceText: onPlaceText,
            onDropImages: onDropImages,
            onDeleteItem: onDeleteItem
        ) {
            ZStack {
                Color.white
                if let pdfPageIndex = page.pdfPageIndex {
                    pdfBackground(pageIndex: pdfPageIndex)
                } else {
                    PaperBackground(style: style, pageSize: page.size)
                }
            }
        }
        .clipShape(.rect(cornerRadius: 3))
        .shadow(color: .black.opacity(0.15), radius: 4, y: 2)
        // Pages are white paper in dark mode too, so text on them stays dark.
        .environment(\.colorScheme, .light)
        // Pages are real paper sizes, so text starts at a typical document size.
        .environment(\.textBoxFont, .system(size: 12))
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
}
