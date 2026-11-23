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

    /// Pages never get wider than this, so they stay comfortable to read on large displays.
    private let maximumPageWidth: CGFloat = 900

    var body: some View {
        let pages = notepad.sortedPages

        GeometryReader { proxy in
            let pageWidth = max(100, min(proxy.size.width - 32, maximumPageWidth))

            ScrollView {
                LazyVStack(spacing: 24) {
                    ForEach(Array(pages.enumerated()), id: \.element.pageID) { position, page in
                        NotebookPageView(
                            page: page,
                            style: notepad.paperStyle,
                            renderer: renderer,
                            displayWidth: pageWidth,
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
                .frame(maxWidth: .infinity)
            }
        }
        .background(.background.secondary)
        .navigationTitle($notepad.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarRole(.editor)
        .editorToolbar(
            session: session,
            leadingTool: .pencil,
            // In the same spot as a canvas's Scenes and Zoom.
            contextTools: [AnyView(paperStyleMenu)],
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
