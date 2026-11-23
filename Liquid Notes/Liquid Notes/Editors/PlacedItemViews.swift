import SwiftUI
import SwiftData

extension EnvironmentValues {
    /// The font of unstyled text in text boxes. Notebook pages use 12 pt, like a printed document.
    @Entry var textBoxFont: Font = .body
}

/// Shows a surface's text boxes and images, laid out in drawing coordinates and scaled to the screen.
///
/// Surfaces use two of these: photos go below the ink so you can draw on them, and text boxes go
/// above it so you can type over photos. Within each, earlier items sit below later ones.
struct PlacedItemsLayer: View {
    enum Layer {
        /// Photos only. They don't take touches; tapping the surface selects them instead.
        case photos
        /// Text boxes, plus the handles of a selected photo so it can be moved from above the ink.
        case textAndHandles
    }

    let items: [PlacedItem]
    let layer: Layer
    /// The area this layer covers, in drawing coordinates.
    let logicalSize: CGSize
    let scale: CGFloat
    let session: EditorSession
    /// The drawing coordinate at this layer's top-leading corner.
    var origin: CGPoint = .zero
    /// Where items may be moved, in drawing coordinates. Defaults to the area this layer covers.
    var itemBounds: CGSize?
    /// When `false`, the layer stays at drawing size and something outside scales it (a zooming canvas).
    var scalesContent = true
    let onDelete: (PlacedItem) -> Void

    var body: some View {
        let content = ZStack(alignment: .topLeading) {
            ForEach(items, id: \.itemID) { item in
                if let role = role(for: item) {
                    PlacedItemView(
                        item: item,
                        role: role,
                        scale: scale,
                        bounds: itemBounds ?? logicalSize,
                        session: session
                    ) {
                        onDelete(item)
                    }
                }
            }
        }
        .offset(x: -origin.x, y: -origin.y)
        .frame(width: logicalSize.width, height: logicalSize.height, alignment: .topLeading)
        // Gestures measure in this unscaled space, so drags translate straight into drawing coordinates.
        .coordinateSpace(.named(PlacedItemView.coordinateSpace))
        .allowsHitTesting(layer == .textAndHandles)

        if scalesContent {
            content
                .scaleEffect(scale, anchor: .topLeading)
                .frame(width: logicalSize.width * scale, height: logicalSize.height * scale, alignment: .topLeading)
        } else {
            content
        }
    }

    private func role(for item: PlacedItem) -> PlacedItemView.Role? {
        switch (layer, item.kind) {
        case (.photos, .image): .content
        case (.textAndHandles, .text): .content
        case (.textAndHandles, .image): session.selectedItemID == item.itemID ? .handlesOnly : nil
        case (.photos, .text): nil
        }
    }
}

/// A single text box or image. When selected it shows handles to move, resize and delete it.
struct PlacedItemView: View {
    static let coordinateSpace = "placed-items"

    enum Role {
        /// The item itself, with handles if it's a selected text box.
        case content
        /// Just the selection frame and handles, drawn above the ink for a photo that's below it.
        case handlesOnly
    }

    @Bindable var item: PlacedItem
    let role: Role
    let scale: CGFloat
    let bounds: CGSize
    let session: EditorSession
    let onDelete: () -> Void

    @Environment(\.undoManager) private var undoManager
    private let minimumSize = CGSize(width: 60, height: 40)

    private var isSelected: Bool { session.selectedItemID == item.itemID }

    /// Handles keep the same on-screen size whatever the page's scale.
    private var handleSize: CGFloat { 30 / scale }

    /// Photos show their handles from the layer above the ink; text boxes show their own.
    private var showsHandles: Bool {
        isSelected && (role == .handlesOnly || item.kind == .text)
    }

    var body: some View {
        // The drag is shared through the session, so a photo and its handles move together.
        let drag = session.drag(for: item)
        let move = drag?.move ?? .zero
        let resize = drag?.resize ?? .zero

        body(for: role)
            .frame(
                width: max(minimumSize.width, item.width + resize.width),
                height: max(minimumSize.height, item.height + resize.height)
            )
            .overlay {
                if showsHandles {
                    Rectangle()
                        .strokeBorder(Color.accentColor, lineWidth: 1.5 / scale)
                        .allowsHitTesting(false)
                }
            }
            .overlay(alignment: .topLeading) {
                if showsHandles {
                    handle(systemImage: "arrow.up.and.down.and.arrow.left.and.right", label: "Move")
                        .offset(x: -handleSize / 2, y: -handleSize / 2)
                        .gesture(moveGesture)
                }
            }
            .overlay(alignment: .topTrailing) {
                if showsHandles {
                    Button(action: onDelete) {
                        handle(systemImage: "xmark", label: "Delete", tint: .red)
                    }
                    .buttonStyle(.plain)
                    .offset(x: handleSize / 2, y: -handleSize / 2)
                }
            }
            .overlay(alignment: .bottomTrailing) {
                if showsHandles {
                    handle(systemImage: "arrow.up.left.and.arrow.down.right", label: "Resize")
                        .offset(x: handleSize / 2, y: handleSize / 2)
                        .gesture(resizeGesture)
                }
            }
            .offset(x: item.x + move.width, y: item.y + move.height)
    }

    @ViewBuilder
    private func body(for role: Role) -> some View {
        switch (role, item.kind) {
        case (.content, .text):
            TextBoxView(item: item, session: session, onDeleteIfEmpty: onDelete)
        case (.content, .image):
            imageContent
        case (.handlesOnly, _):
            // Dragging anywhere on a selected photo moves it.
            Color.clear
                .contentShape(.rect)
                .gesture(moveGesture)
                .accessibilityLabel("Selected image")
        }
    }

    @ViewBuilder
    private var imageContent: some View {
        let data = item.imageData
        AsyncRenderedImage(key: AnyHashable(item.itemID)) {
            data.flatMap { ImageProcessing.thumbnail(from: $0, maxPixelSize: 2048) }
        } placeholder: {
            Rectangle().fill(.quaternary)
        }
        .scaledToFit()
        .accessibilityLabel("Image")
        .accessibilityAddTraits(.isImage)
    }

    private func handle(systemImage: String, label: LocalizedStringKey, tint: Color = .accentColor) -> some View {
        Image(systemName: systemImage)
            .font(.system(size: 13 / scale, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: handleSize, height: handleSize)
            .background(tint, in: .circle)
            .contentShape(.circle)
            .accessibilityLabel(label)
    }

    private var moveGesture: some Gesture {
        DragGesture(minimumDistance: 2, coordinateSpace: .named(Self.coordinateSpace))
            .onChanged { value in
                session.selectedItemID = item.itemID
                session.activeDrag = EditorSession.ItemDrag(itemID: item.itemID, move: value.translation)
            }
            .onEnded { value in
                let moved = item.frame.offsetBy(dx: value.translation.width, dy: value.translation.height)
                let actionName = item.kind == .image ? String(localized: "Move Image") : String(localized: "Move Text Box")
                PlacedItemUndo.setFrame(item, to: PlacedItemFactory.clamped(moved, in: bounds), undoManager: undoManager, actionName: actionName)
                session.activeDrag = nil
            }
    }

    private var resizeGesture: some Gesture {
        DragGesture(minimumDistance: 1, coordinateSpace: .named(Self.coordinateSpace))
            .onChanged { value in
                session.activeDrag = EditorSession.ItemDrag(itemID: item.itemID, resize: value.translation)
            }
            .onEnded { value in
                let resized = CGRect(
                    x: item.x,
                    y: item.y,
                    width: min(max(minimumSize.width, item.width + value.translation.width), bounds.width - item.x),
                    height: min(max(minimumSize.height, item.height + value.translation.height), bounds.height - item.y)
                )
                let actionName = item.kind == .image ? String(localized: "Resize Image") : String(localized: "Resize Text Box")
                PlacedItemUndo.setFrame(item, to: resized, undoManager: undoManager, actionName: actionName)
                session.activeDrag = nil
            }
    }
}

/// An editable rich-text box. While focused, the toolbar's text buttons format it.
struct TextBoxView: View {
    @Bindable var item: PlacedItem
    let session: EditorSession
    /// Empty text boxes are removed once they're deselected.
    let onDeleteIfEmpty: () -> Void

    @Environment(\.textBoxFont) private var defaultFont
    @Environment(\.fontResolutionContext) private var fontResolutionContext
    @State private var text: AttributedString
    @State private var selection = AttributedTextSelection()
    @FocusState private var isFocused: Bool

    init(item: PlacedItem, session: EditorSession, onDeleteIfEmpty: @escaping () -> Void) {
        _item = Bindable(item)
        self.session = session
        self.onDeleteIfEmpty = onDeleteIfEmpty
        _text = State(initialValue: item.richText)
    }

    private var isEmpty: Bool {
        text.characters.allSatisfy(\.isWhitespace)
    }

    var body: some View {
        TextEditor(text: $text, selection: $selection)
            .font(defaultFont)
            .scrollContentBackground(.hidden)
            .focused($isFocused)
            .overlay(alignment: .topLeading) {
                if isEmpty && !isFocused {
                    Text("Text")
                        .font(defaultFont)
                        .foregroundStyle(.tertiary)
                        .padding(8)
                        .allowsHitTesting(false)
                }
            }
            .background {
                if !isFocused && session.selectedItemID != item.itemID {
                    // A faint outline helps you find text boxes without cluttering the page.
                    Rectangle().strokeBorder(.quaternary, style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                        .opacity(isEmpty ? 1 : 0)
                }
            }
            .onChange(of: text) { _, newValue in
                item.richTextData = RichTextCoding.encode(newValue)
                item.owningNotepad?.touch()
                reportFontSize()
            }
            .onChange(of: selection) { reportFontSize() }
            .onChange(of: isFocused) { _, focused in
                if focused {
                    session.selectedItemID = item.itemID
                    session.textTarget = RichTextTarget(
                        id: item.itemID, text: $text, selection: $selection, defaultFont: defaultFont
                    )
                    reportFontSize()
                }
            }
            .onChange(of: session.selectedItemID) { previous, current in
                // Clean up when you move on, such as by drawing or selecting something else. Losing
                // focus alone isn't enough, since focus can move briefly while the box is still in use.
                if previous == item.itemID, current != item.itemID, isEmpty {
                    onDeleteIfEmpty()
                }
            }
            .onAppear {
                guard session.pendingFocusItemID == item.itemID else { return }
                session.pendingFocusItemID = nil
                // Focus once the text view is in the window.
                DispatchQueue.main.async { isFocused = true }
            }
            .accessibilityLabel("Text box")
    }

    /// Updates the toolbar's size readout while this box is the one being formatted.
    private func reportFontSize() {
        guard session.textTarget?.id == AnyHashable(item.itemID) else { return }
        session.currentFontSize = FontSizes.pointSize(
            of: text, selection: selection, defaultFont: defaultFont, context: fontResolutionContext
        )
    }
}
