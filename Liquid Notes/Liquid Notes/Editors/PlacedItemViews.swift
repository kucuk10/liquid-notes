import SwiftUI
import SwiftData

extension EnvironmentValues {
    /// The font of unstyled text in text boxes. Notebook pages use 12 pt, like a printed document.
    @Entry var textBoxFont: Font = .body
}

/// Shows a surface's text boxes and images. Items are stored in drawing coordinates and laid out
/// at their size on screen, rather than drawn small and magnified, so text stays sharp at any zoom.
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
    let onDelete: (PlacedItem) -> Void

    var body: some View {
        ZStack(alignment: .topLeading) {
            ForEach(items, id: \.itemID) { item in
                if let role = role(for: item) {
                    PlacedItemView(
                        item: item,
                        role: role,
                        scale: scale,
                        bounds: itemBounds ?? logicalSize,
                        session: session,
                        onDelete: onDelete
                    )
                    // Scrolling a canvas moves this whole layer; items whose own inputs didn't
                    // change are skipped instead of redrawn.
                    .equatable()
                }
            }
        }
        .offset(x: -origin.x * scale, y: -origin.y * scale)
        .frame(width: logicalSize.width * scale, height: logicalSize.height * scale, alignment: .topLeading)
        // Drags measure in screen points here, and items divide by the scale to get drawing coordinates.
        .coordinateSpace(.named(PlacedItemView.coordinateSpace))
        .allowsHitTesting(layer == .textAndHandles)
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
struct PlacedItemView: View, Equatable {
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
    let onDelete: (PlacedItem) -> Void

    @Environment(\.undoManager) private var undoManager
    private let minimumSize = CGSize(width: 60, height: 40)

    /// Compares what the view draws. Closures can't be compared, so `onDelete` is left out; it's
    /// the editor's delete action, which doesn't change while the editor is open. Changes to the
    /// item and session still redraw the view through observation.
    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.item === rhs.item && lhs.role == rhs.role && lhs.scale == rhs.scale
            && lhs.bounds == rhs.bounds && lhs.session === rhs.session
    }

    private var isSelected: Bool { session.selectedItemID == item.itemID }

    private let handleSize: CGFloat = 30

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
                width: max(minimumSize.width, item.width + resize.width) * scale,
                height: max(minimumSize.height, item.height + resize.height) * scale
            )
            .overlay {
                if showsHandles {
                    Rectangle()
                        .strokeBorder(Color.accentColor, lineWidth: 1.5)
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
                    Button {
                        onDelete(item)
                    } label: {
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
            .offset(x: (item.x + move.width) * scale, y: (item.y + move.height) * scale)
    }

    /// A drag's movement in drawing coordinates.
    private func drawingDistance(_ translation: CGSize) -> CGSize {
        CGSize(width: translation.width / scale, height: translation.height / scale)
    }

    @ViewBuilder
    private func body(for role: Role) -> some View {
        switch (role, item.kind) {
        case (.content, .text):
            TextBoxView(item: item, scale: scale, session: session) { onDelete(item) }
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
            .font(.system(size: 13, weight: .semibold))
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
                session.updateDrag(of: item, move: drawingDistance(value.translation))
            }
            .onEnded { value in
                let distance = drawingDistance(value.translation)
                let moved = item.frame.offsetBy(dx: distance.width, dy: distance.height)
                let actionName = item.kind == .image ? String(localized: "Move Image") : String(localized: "Move Text Box")
                PlacedItemUndo.setFrame(item, to: PlacedItemFactory.clamped(moved, in: bounds), undoManager: undoManager, actionName: actionName)
                session.endDrag()
            }
    }

    private var resizeGesture: some Gesture {
        DragGesture(minimumDistance: 1, coordinateSpace: .named(Self.coordinateSpace))
            .onChanged { value in
                session.updateDrag(of: item, resize: drawingDistance(value.translation))
            }
            .onEnded { value in
                let distance = drawingDistance(value.translation)
                let resized = CGRect(
                    x: item.x,
                    y: item.y,
                    width: min(max(minimumSize.width, item.width + distance.width), bounds.width - item.x),
                    height: min(max(minimumSize.height, item.height + distance.height), bounds.height - item.y)
                )
                let actionName = item.kind == .image ? String(localized: "Resize Image") : String(localized: "Resize Text Box")
                PlacedItemUndo.setFrame(item, to: resized, undoManager: undoManager, actionName: actionName)
                session.endDrag()
            }
    }
}

/// An editable rich-text box. While focused, the toolbar's text buttons format it.
///
/// Boxes show their text with SwiftUI's `Text`, in fonts scaled to the screen, so text is sharp at
/// any zoom. They switch to a `TextEditor` only while you edit one; that editor is laid out at drawing
/// size and magnified, which keeps its cursor and selection simple. `Text` is also far lighter than a
/// text editor, so pages and canvases with many text boxes scroll and zoom smoothly.
struct TextBoxView: View {
    @Bindable var item: PlacedItem
    /// Screen points per drawing point.
    let scale: CGFloat
    let session: EditorSession
    /// Empty text boxes are removed once they're deselected.
    let onDeleteIfEmpty: () -> Void

    @Environment(\.textBoxFont) private var defaultFont
    @Environment(\.fontResolutionContext) private var fontResolutionContext
    @State private var text: AttributedString
    /// `text` with its fonts scaled to the screen. Kept up to date here rather than built in `body`,
    /// since scaling makes a new font for every run, and boxes redraw often while you scroll.
    @State private var displayText: AttributedString?
    @State private var selection = AttributedTextSelection()
    @State private var isEditing = false
    @FocusState private var isFocused: Bool

    init(item: PlacedItem, scale: CGFloat, session: EditorSession, onDeleteIfEmpty: @escaping () -> Void) {
        _item = Bindable(item)
        self.scale = scale
        self.session = session
        self.onDeleteIfEmpty = onDeleteIfEmpty
        _text = State(initialValue: item.richText)
    }

    private var isEmpty: Bool {
        text.characters.allSatisfy(\.isWhitespace)
    }

    var body: some View {
        content
            .overlay(alignment: .topLeading) {
                if isEmpty && !isFocused {
                    Text("Text")
                        .font(displayFont(defaultFont))
                        .foregroundStyle(.tertiary)
                        .padding(8 * scale)
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
                // While editing, the text editor shows the text; the display copy catches up after.
                if !isEditing { displayText = scaledText() }
                reportFontSize()
            }
            .onChange(of: isEditing) { if !isEditing { displayText = scaledText() } }
            .onChange(of: scale) { displayText = scaledText() }
            .onChange(of: defaultFont) { displayText = scaledText() }
            .onChange(of: fontResolutionContext) { displayText = scaledText() }
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
                // focus alone isn't enough, since focus can move briefly while the box is still in use,
                // such as when you use the toolbar's formatting buttons.
                guard previous == item.itemID, current != item.itemID else { return }
                if isEmpty {
                    onDeleteIfEmpty()
                } else {
                    isEditing = false
                }
            }
            .onAppear {
                displayText = scaledText()
                guard session.pendingFocusItemID == item.itemID else { return }
                session.pendingFocusItemID = nil
                startEditing()
            }
            .accessibilityLabel("Text box")
    }

    @ViewBuilder
    private var content: some View {
        if isEditing {
            GeometryReader { proxy in
                TextEditor(text: $text, selection: $selection)
                    .font(defaultFont)
                    .scrollContentBackground(.hidden)
                    .focused($isFocused)
                    .frame(width: proxy.size.width / scale, height: proxy.size.height / scale)
                    .scaleEffect(scale, anchor: .topLeading)
            }
        } else {
            Text(displayText ?? scaledText())
                // Matches where a text editor lays out its text, so nothing jumps when editing starts.
                .padding(.horizontal, 5 * scale)
                .padding(.vertical, 8 * scale)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .clipped()
                .contentShape(.rect)
                .onTapGesture(perform: startEditing)
                .accessibilityAddTraits(.isButton)
                .accessibilityHint("Edits the text")
        }
    }

    /// The text with each run's font scaled to the screen, including unstyled runs.
    private func scaledText() -> AttributedString {
        guard scale != 1 else { return text }
        var scaled = text
        for run in text.runs {
            scaled[run.range].font = displayFont(run.font ?? defaultFont)
        }
        return scaled
    }

    /// A font enlarged by the scale but keeping its original optical size. San Francisco adjusts
    /// letter shapes and spacing for each point size, so simply using the bigger size would set text
    /// tighter than the text editor does, and lines could wrap differently when editing starts.
    private func displayFont(_ font: Font) -> Font {
        let resolved = font.resolve(in: fontResolutionContext)
        let descriptor = CTFontDescriptorCreateWithAttributes(
            [kCTFontOpticalSizeAttribute: resolved.pointSize] as CFDictionary
        )
        return Font(CTFontCreateCopyWithAttributes(resolved.ctFont, resolved.pointSize * scale, nil, descriptor))
    }

    /// Swaps in the text editor and puts the cursor at the end of the text.
    private func startEditing() {
        session.selectedItemID = item.itemID
        selection = AttributedTextSelection(range: text.endIndex..<text.endIndex)
        isEditing = true
        // Focus once the text editor is in the window.
        DispatchQueue.main.async { isFocused = true }
    }

    /// Updates the toolbar's size readout while this box is the one being formatted.
    private func reportFontSize() {
        guard session.textTarget?.id == AnyHashable(item.itemID) else { return }
        session.currentFontSize = FontSizes.pointSize(
            of: text, selection: selection, defaultFont: defaultFont, context: fontResolutionContext
        )
    }
}
