import SwiftUI
import SwiftData
import PhotosUI
import UniformTypeIdentifiers

/// A simple rich-text note, like Apple Notes, with optional attachments.
struct NoteEditorView: View {
    @Bindable var notepad: Notepad
    @Environment(\.modelContext) private var modelContext
    @Environment(\.fontResolutionContext) private var fontResolutionContext

    @State private var text: AttributedString
    @State private var selection = AttributedTextSelection()
    @State private var editorWidth: CGFloat = 0
    @FocusState private var isEditorFocused: Bool

    @State private var photoItems: [PhotosPickerItem] = []
    @State private var isImportingFiles = false
    @State private var isSketching = false

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
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                formatMenu
                attachMenu
            }
        }
        .onChange(of: text) { _, newValue in
            notepad.updateRichText(newValue)
        }
        .onChange(of: photoItems) { _, items in
            guard !items.isEmpty else { return }
            Task { await importPhotos(items) }
        }
        .fileImporter(
            isPresented: $isImportingFiles,
            allowedContentTypes: [.image, .pdf],
            allowsMultipleSelection: true
        ) { result in
            if case .success(let urls) = result {
                urls.forEach(importFile)
            }
        }
        #if canImport(UIKit)
        .sheet(isPresented: $isSketching) {
            SketchEditorView(initialData: nil) { data in
                if let data { addAttachment(Attachment(kind: .sketch, filename: "Sketch", data: data)) }
            }
        }
        #endif
        .onAppear {
            // New notes start ready for typing.
            if notepad.plainText.isEmpty { isEditorFocused = true }
        }
    }

    private var horizontalMargin: CGFloat {
        max(16, (editorWidth - readableWidth) / 2)
    }

    // MARK: Formatting

    private var formatMenu: some View {
        Menu {
            Section {
                ForEach(ParagraphStyle.allCases) { style in
                    Button(style.name) { apply(style) }
                }
            }
            Section {
                Button("Bold", systemImage: "bold") { toggleBold() }
                Button("Italic", systemImage: "italic") { toggleItalic() }
                Button("Underline", systemImage: "underline") {
                    text.transformAttributes(in: &selection) { container in
                        container.underlineStyle = container.underlineStyle == nil ? .single : nil
                    }
                }
                Button("Strikethrough", systemImage: "strikethrough") {
                    text.transformAttributes(in: &selection) { container in
                        container.strikethroughStyle = container.strikethroughStyle == nil ? .single : nil
                    }
                }
            }
            Section {
                Button("Bulleted Item", systemImage: "list.bullet") {
                    text.replaceSelection(&selection, withCharacters: "• ")
                }
            }
        } label: {
            Label("Format", systemImage: "textformat")
        }
    }

    private func apply(_ style: ParagraphStyle) {
        text.transformAttributes(in: &selection) { container in
            container.font = style.font
        }
    }

    private func toggleBold() {
        text.transformAttributes(in: &selection) { container in
            let font = container.font ?? .body
            let isBold = font.resolve(in: fontResolutionContext).isBold
            container.font = font.bold(!isBold)
        }
    }

    private func toggleItalic() {
        text.transformAttributes(in: &selection) { container in
            let font = container.font ?? .body
            let isItalic = font.resolve(in: fontResolutionContext).isItalic
            container.font = font.italic(!isItalic)
        }
    }

    // MARK: Attachments

    private var attachMenu: some View {
        Menu {
            PhotosPicker(selection: $photoItems, matching: .images) {
                Label("Photo Library", systemImage: "photo.on.rectangle")
            }
            Button("Choose File…", systemImage: "folder") {
                isImportingFiles = true
            }
            #if canImport(UIKit)
            Button("Sketch", systemImage: "pencil.and.scribble") {
                isSketching = true
            }
            #endif
        } label: {
            Label("Attach", systemImage: "paperclip")
        }
    }

    private func importPhotos(_ items: [PhotosPickerItem]) async {
        for item in items {
            guard let data = try? await item.loadTransferable(type: Data.self),
                  let prepared = ImageProcessing.preparedImageData(from: data)
            else { continue }
            addAttachment(Attachment(kind: .image, filename: "Photo", data: prepared))
        }
        photoItems = []
    }

    private func importFile(_ url: URL) {
        let didAccess = url.startAccessingSecurityScopedResource()
        defer { if didAccess { url.stopAccessingSecurityScopedResource() } }
        guard let data = try? Data(contentsOf: url) else { return }

        let filename = url.lastPathComponent
        if UTType(filenameExtension: url.pathExtension)?.conforms(to: .pdf) == true {
            addAttachment(Attachment(kind: .pdf, filename: filename, data: data))
        } else if let prepared = ImageProcessing.preparedImageData(from: data) {
            addAttachment(Attachment(kind: .image, filename: filename, data: prepared))
        }
    }

    private func addAttachment(_ attachment: Attachment) {
        modelContext.insert(attachment)
        attachment.notepad = notepad
        notepad.touch()
    }
}

/// Paragraph styles offered in the Format menu. Fonts are text styles, so they follow Dynamic Type.
private enum ParagraphStyle: CaseIterable, Identifiable {
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
