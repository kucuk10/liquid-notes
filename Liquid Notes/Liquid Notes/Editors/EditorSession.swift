import SwiftUI
import PencilKit

/// Editing state shared by an editor's toolbar and its content: the PencilKit tool picker,
/// the selected text box or image, and the text that formatting buttons apply to.
@MainActor
@Observable
final class EditorSession {
    /// The selected text box or image on a page or canvas.
    var selectedItemID: UUID?
    /// A newly created text box that should start editing as soon as it appears.
    var pendingFocusItemID: UUID?
    /// The text the formatting buttons apply to, if any.
    var textTarget: RichTextTarget?
    /// The point size of the selected text, shown in the toolbar. `nil` when sizes are mixed.
    var currentFontSize: CGFloat?
    /// An item being moved or resized. Photos and their handles are drawn in different layers,
    /// so the drag lives here where both can follow it.
    var activeDrag: ItemDrag?

    /// The in-progress move and resize for an item, in drawing coordinates.
    struct ItemDrag {
        let itemID: UUID
        var move: CGSize = .zero
        var resize: CGSize = .zero
    }

    func drag(for item: PlacedItem) -> ItemDrag? {
        activeDrag?.itemID == item.itemID ? activeDrag : nil
    }

    /// One tool picker shared by every canvas in the editor, such as all pages of a notebook.
    let toolPicker: PKToolPicker
    /// Whether the PencilKit tools are shown.
    var showsToolPicker = true
    /// The canvas that receives the tool picker.
    var activeCanvasID: AnyHashable?
    /// Whether the picker's Text tool is selected, so taps place text boxes instead of drawing.
    var isTextToolSelected = false

    static let textToolIdentifier = "ca.dal.kucuk.Liquid-Notes.text-tool"

    init(includesTextTool: Bool = true) {
        toolPicker = includesTextTool ? Self.makeToolPickerWithTextTool() : PKToolPicker()
    }

    /// The standard PencilKit tools plus a Text tool, placed before the eraser.
    private static func makeToolPickerWithTextTool() -> PKToolPicker {
        #if os(iOS)
        var configuration = PKToolPickerCustomItem.Configuration(
            identifier: textToolIdentifier,
            name: String(localized: "Text")
        )
        configuration.allowsColorSelection = false
        configuration.imageProvider = { _ in
            let symbol = UIImage.SymbolConfiguration(pointSize: 30, weight: .medium)
            return UIImage(systemName: "character.textbox", withConfiguration: symbol)?
                .withTintColor(.label, renderingMode: .alwaysOriginal) ?? UIImage()
        }

        var items = PKToolPicker().toolItems
        let eraserIndex = items.firstIndex { $0 is PKToolPickerEraserItem } ?? items.endIndex
        items.insert(PKToolPickerCustomItem(configuration: configuration), at: eraserIndex)
        return PKToolPicker(toolItems: items)
        #else
        return PKToolPicker()
        #endif
    }

    /// Clears any state that refers to an item that's being deleted.
    func forget(_ item: PlacedItem) {
        if selectedItemID == item.itemID { selectedItemID = nil }
        if textTarget?.id == AnyHashable(item.itemID) {
            textTarget = nil
            currentFontSize = nil
        }
    }
}

/// A piece of rich text that formatting buttons can change, such as a note's body or a text box.
struct RichTextTarget {
    let id: AnyHashable
    /// The font of text that has no font of its own.
    let defaultFont: Font
    /// Runs a change against the text and its current selection.
    let edit: (_ change: (inout AttributedString, inout AttributedTextSelection) -> Void) -> Void

    /// Builds a target from a view's text and selection state.
    init(
        id: AnyHashable,
        text: Binding<AttributedString>,
        selection: Binding<AttributedTextSelection>,
        defaultFont: Font = .body
    ) {
        self.id = id
        self.defaultFont = defaultFont
        self.edit = { change in
            var newText = text.wrappedValue
            var newSelection = selection.wrappedValue
            change(&newText, &newSelection)
            text.wrappedValue = newText
            selection.wrappedValue = newSelection
        }
    }
}

/// Header styles. Fonts are text styles, so they follow Dynamic Type.
enum ParagraphStyle: CaseIterable, Identifiable {
    case title, heading, subheading, body

    var id: Self { self }

    var name: LocalizedStringKey {
        switch self {
        case .title: "Title"
        case .heading: "Heading"
        case .subheading: "Subheading"
        case .body: "Body"
        }
    }

    var font: Font? {
        switch self {
        case .title: .title.bold()
        case .heading: .title2.bold()
        case .subheading: .title3.weight(.semibold)
        case .body: nil
        }
    }
}

/// Font sizes in points, like a word processor's size menu.
enum FontSizes {
    static let standard: [CGFloat] = [8, 9, 10, 11, 12, 14, 16, 18, 20, 22, 24, 28, 32, 36, 48, 72]

    /// The standard sizes plus the current one, so an unusual size (such as a heading's) is still listed.
    static func choices(including current: CGFloat?) -> [CGFloat] {
        guard let current, !standard.contains(current) else { return standard }
        return (standard + [current]).sorted()
    }

    static func next(after size: CGFloat) -> CGFloat {
        standard.first { $0 > size } ?? size
    }

    static func previous(before size: CGFloat) -> CGFloat {
        standard.last { $0 < size } ?? size
    }

    /// Shown as "12", or "12.5" for fractional sizes.
    static func label(for size: CGFloat) -> String {
        Double(size).formatted(.number.precision(.fractionLength(0...1)))
    }

    /// The point size of the selected text, or `nil` when the selection mixes sizes.
    static func pointSize(
        of text: AttributedString,
        selection: AttributedTextSelection,
        defaultFont: Font,
        context: Font.Context
    ) -> CGFloat? {
        let sizes = Set(selection.attributes(in: text)[\.font].map { font in
            ((font ?? defaultFont).resolve(in: context).pointSize * 2).rounded() / 2
        })
        return sizes.count == 1 ? sizes.first : nil
    }
}

extension RichTextTarget {
    func apply(_ style: ParagraphStyle) {
        edit { text, selection in
            text.transformAttributes(in: &selection) { $0.font = style.font }
        }
    }

    /// Rebuilds each run's font at a new size or weight, keeping its other traits.
    private func reshapeFonts(
        context: Font.Context,
        _ change: @escaping (_ size: inout CGFloat, _ isBold: inout Bool, _ isItalic: inout Bool) -> Void
    ) {
        let defaultFont = defaultFont
        edit { text, selection in
            text.transformAttributes(in: &selection) { container in
                let resolved = (container.font ?? defaultFont).resolve(in: context)
                var size = resolved.pointSize
                var isBold = resolved.isBold
                var isItalic = resolved.isItalic
                change(&size, &isBold, &isItalic)
                var font = Font.system(size: size, weight: isBold ? .bold : .regular)
                if isItalic { font = font.italic() }
                container.font = font
            }
        }
    }

    func apply(pointSize: CGFloat, context: Font.Context) {
        reshapeFonts(context: context) { size, _, _ in size = pointSize }
    }

    func increaseSize(context: Font.Context) {
        reshapeFonts(context: context) { size, _, _ in size = FontSizes.next(after: size) }
    }

    func decreaseSize(context: Font.Context) {
        reshapeFonts(context: context) { size, _, _ in size = FontSizes.previous(before: size) }
    }

    func toggleBold(context: Font.Context) {
        reshapeFonts(context: context) { _, isBold, _ in isBold.toggle() }
    }

    func toggleItalic(context: Font.Context) {
        reshapeFonts(context: context) { _, _, isItalic in isItalic.toggle() }
    }

    func toggleUnderline() {
        edit { text, selection in
            text.transformAttributes(in: &selection) { container in
                container.underlineStyle = container.underlineStyle == nil ? .single : nil
            }
        }
    }

    func toggleStrikethrough() {
        edit { text, selection in
            text.transformAttributes(in: &selection) { container in
                container.strikethroughStyle = container.strikethroughStyle == nil ? .single : nil
            }
        }
    }

    func insertBullet() {
        edit { text, selection in
            text.replaceSelection(&selection, withCharacters: "• ")
        }
    }
}
