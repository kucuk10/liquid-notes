import SwiftUI
import SwiftData

/// A simple rich-text note, like Apple Notes, with photo and sketch attachments.
struct NoteEditorView: View {
    @Bindable var notepad: Notepad
    @Environment(\.modelContext) private var modelContext
    @Environment(\.fontResolutionContext) private var fontResolutionContext

    @State private var text: AttributedString
    @State private var selection = AttributedTextSelection()
    @State private var session = EditorSession(includesTextTool: false)
    @State private var editorWidth: CGFloat = 0
    @FocusState private var isEditorFocused: Bool

    /// Text stays at a readable line length on wide screens, like Apple Notes.
    private let readableWidth: CGFloat = 720

    init(notepad: Notepad) {
        _notepad = Bindable(notepad)
        _text = State(initialValue: notepad.richText)
    }

    var body: some View {
        VStack(spacing: 0) {
            TextEditor(text: $text, selection: $selection)
                .font(.body)
                .focused($isEditorFocused)
                .scrollContentBackground(.hidden)
                .contentMargins(.horizontal, horizontalMargin, for: .scrollContent)
                .contentMargins(.vertical, 12, for: .scrollContent)
                .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { editorWidth = $0 }

            if !notepad.sortedAttachments.isEmpty {
                Divider()
                AttachmentStrip(notepad: notepad)
            }
        }
        .background(.background)
        .navigationTitle(notepad.displayTitle)
        .navigationBarTitleDisplayMode(.inline)
        .editorToolbar(
            session: session,
            leadingTool: .sketch,
            onSketch: { data in
                addAttachment(Attachment(kind: .sketch, filename: String(localized: "Sketch"), data: data))
            },
            onImportImages: addImages
        )
        .dropDestination(for: DroppedImage.self) { images, _ in
            let originals = images.map(\.data)
            Task { addImages(await ImageProcessing.preparedImagesInBackground(from: originals)) }
            return !images.isEmpty
        }
        .onChange(of: text) { _, newValue in
            notepad.updateRichText(newValue)
            reportFontSize()
        }
        .onChange(of: selection) { reportFontSize() }
        .onAppear {
            // The note's text is always what the formatting buttons change.
            session.textTarget = RichTextTarget(id: "note", text: $text, selection: $selection)
            reportFontSize()
            // New notes start ready for typing.
            if notepad.plainText.isEmpty { isEditorFocused = true }
        }
    }

    private var horizontalMargin: CGFloat {
        max(16, (editorWidth - readableWidth) / 2)
    }

    /// Keeps the toolbar's size readout in step with the selection.
    private func reportFontSize() {
        session.currentFontSize = FontSizes.pointSize(
            of: text, selection: selection, defaultFont: .body, context: fontResolutionContext
        )
    }

    private func addImages(_ images: [Data]) {
        for data in images {
            addAttachment(Attachment(kind: .image, filename: String(localized: "Photo"), data: data))
        }
    }

    private func addAttachment(_ attachment: Attachment) {
        modelContext.insert(attachment)
        attachment.notepad = notepad
        notepad.touch()
    }
}
