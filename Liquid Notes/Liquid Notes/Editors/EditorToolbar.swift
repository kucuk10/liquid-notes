import SwiftUI
import PhotosUI
import UniformTypeIdentifiers

/// Undo and Redo for everything in an editor: ink, typing, and adding, moving or deleting items.
struct UndoRedoButtons: View {
    @Environment(\.undoManager) private var undoManager
    @State private var canUndo = false
    @State private var canRedo = false

    var body: some View {
        Button("Undo", systemImage: "arrow.uturn.backward") { undoManager?.undo() }
            .disabled(!canUndo)
        Button("Redo", systemImage: "arrow.uturn.forward") { undoManager?.redo() }
            .disabled(!canRedo)
            .task(id: undoManager.map(ObjectIdentifier.init)) {
                await watchUndoManager()
            }
    }

    /// Keeps the buttons' enabled state in step with the undo history.
    private func watchUndoManager() async {
        refresh()
        guard let undoManager else { return }
        await withTaskGroup(of: Void.self) { group in
            for name in [Notification.Name.NSUndoManagerCheckpoint, .NSUndoManagerDidUndoChange, .NSUndoManagerDidRedoChange] {
                group.addTask { @MainActor in
                    for await _ in NotificationCenter.default.notifications(named: name, object: undoManager) {
                        refresh()
                    }
                }
            }
        }
    }

    private func refresh() {
        canUndo = undoManager?.canUndo ?? false
        canRedo = undoManager?.canRedo ?? false
    }
}

/// The first button in the editor toolbar.
enum LeadingEditorTool {
    /// Shows and hides the PencilKit tools (notebooks and canvases).
    case pencil
    /// Opens the sketch pad and saves the sketch as an attachment (notes).
    case sketch
}

extension View {
    /// The toolbar shared by every editor. After the title, from left to right: Undo and Redo, any
    /// editor-specific controls (a canvas's Scenes and Zoom, a notebook's paper style), Pencil or
    /// Sketch, text formatting, then attachments. Each is its own group.
    /// - Parameters:
    ///   - contextTools: Editor-specific controls, each shown as a separate group.
    ///   - showsFontSizes: Point sizes (12, 14…) matter on fixed-size notebook pages.
    ///     Notes and canvases rely on text styles instead.
    func editorToolbar(
        session: EditorSession,
        leadingTool: LeadingEditorTool,
        contextTools: [AnyView] = [],
        showsFontSizes: Bool = false,
        onAddTextBox: (() -> Void)? = nil,
        onSketch: ((Data) -> Void)? = nil,
        onImportImages: @escaping ([Data]) -> Void
    ) -> some View {
        modifier(EditorToolbarModifier(
            session: session,
            leadingTool: leadingTool,
            contextTools: contextTools,
            showsFontSizes: showsFontSizes,
            onAddTextBox: onAddTextBox,
            onSketch: onSketch,
            onImportImages: onImportImages
        ))
    }
}

private struct EditorToolbarModifier: ViewModifier {
    @Bindable var session: EditorSession
    let leadingTool: LeadingEditorTool
    let contextTools: [AnyView]
    let showsFontSizes: Bool
    let onAddTextBox: (() -> Void)?
    let onSketch: ((Data) -> Void)?
    let onImportImages: ([Data]) -> Void

    @Environment(\.fontResolutionContext) private var fontResolutionContext
    @State private var availableWidth: CGFloat = 0
    @State private var isPickingPhotos = false
    @State private var photoItems: [PhotosPickerItem] = []
    @State private var isImportingFiles = false
    @State private var isSketching = false

    /// Below these widths, a group collapses into a single menu button.
    private let expandedTextWidth: CGFloat = 860
    private let expandedAttachmentWidth: CGFloat = 620

    func body(content: Content) -> some View {
        content
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { availableWidth = $0 }
            // When the toolbar runs out of room, such as on the side of iPhone Duo's outer display,
            // lower-priority groups move into the overflow menu first.
            .toolbar {
                ToolbarItemGroup(placement: .primaryAction) { UndoRedoButtons() }
                    .visibilityPriority(.high)
                ToolbarSpacer(.fixed, placement: .primaryAction)
                if contextTools.indices.contains(0) {
                    ToolbarItem(placement: .primaryAction) { contextTools[0] }
                    ToolbarSpacer(.fixed, placement: .primaryAction)
                }
                if contextTools.indices.contains(1) {
                    ToolbarItem(placement: .primaryAction) { contextTools[1] }
                    ToolbarSpacer(.fixed, placement: .primaryAction)
                }
                #if canImport(UIKit)
                ToolbarItem(placement: .primaryAction) { leadingButton }
                    .visibilityPriority(ToolbarItemVisibilityPriority(higherThan: .high))
                ToolbarSpacer(.fixed, placement: .primaryAction)
                #endif
                ToolbarItemGroup(placement: .primaryAction) { textTools }
                ToolbarSpacer(.fixed, placement: .primaryAction)
                ToolbarItemGroup(placement: .primaryAction) { attachmentTools }
                    .visibilityPriority(.low)
            }
            .photosPicker(isPresented: $isPickingPhotos, selection: $photoItems, matching: .images)
            .onChange(of: photoItems) { _, items in
                guard !items.isEmpty else { return }
                Task { await importPhotos(items) }
            }
            .fileImporter(
                isPresented: $isImportingFiles,
                allowedContentTypes: [.image],
                allowsMultipleSelection: true
            ) { result in
                if case .success(let urls) = result { importFiles(urls) }
            }
            #if canImport(UIKit)
            .sheet(isPresented: $isSketching) {
                SketchEditorView(initialData: nil) { data in
                    if let data { onSketch?(data) }
                }
            }
            #endif
    }

    // MARK: Pencil or Sketch

    #if canImport(UIKit)
    @ViewBuilder
    private var leadingButton: some View {
        switch leadingTool {
        case .pencil:
            Toggle(isOn: $session.showsToolPicker) {
                Label("Apple Pencil Tools", systemImage: "pencil.tip.crop.circle")
            }
        case .sketch:
            Button("Sketch", systemImage: "pencil.and.scribble") {
                isSketching = true
            }
        }
    }
    #endif

    // MARK: Text

    private var target: RichTextTarget? { session.textTarget }

    @ViewBuilder
    private var textTools: some View {
        if availableWidth >= expandedTextWidth {
            if let onAddTextBox {
                Button("Add Text Box", systemImage: "character.textbox", action: onAddTextBox)
            }
            Menu {
                paragraphStyleButtons
                Divider()
                bulletButton
            } label: {
                Label("Text Style", systemImage: "textformat")
            }
            .disabled(target == nil)
            if showsFontSizes {
                Menu {
                    fontSizeControls
                } label: {
                    // Like a word processor, the button shows the current size.
                    Text(session.currentFontSize.map(FontSizes.label(for:)) ?? "–")
                        .monospacedDigit()
                        .frame(minWidth: 28)
                }
                .accessibilityLabel("Font Size")
                .accessibilityValue(session.currentFontSize.map { "\(FontSizes.label(for: $0)) points" } ?? "Mixed")
                .disabled(target == nil)
            }
            emphasisButtons
                .disabled(target == nil)
        } else {
            Menu {
                if let onAddTextBox {
                    Button("Add Text Box", systemImage: "character.textbox", action: onAddTextBox)
                }
                Group {
                    Section("Style") { paragraphStyleButtons }
                    if showsFontSizes {
                        Menu {
                            fontSizeControls
                        } label: {
                            Label(
                                session.currentFontSize.map { String(localized: "Size: \(FontSizes.label(for: $0)) pt") }
                                    ?? String(localized: "Size"),
                                systemImage: "textformat.size"
                            )
                        }
                    }
                    Section { emphasisButtons }
                    Section { bulletButton }
                }
                .disabled(target == nil)
            } label: {
                Label("Text", systemImage: "textformat")
            }
        }
    }

    @ViewBuilder
    private var paragraphStyleButtons: some View {
        ForEach(ParagraphStyle.allCases) { style in
            Button(style.name) { target?.apply(style) }
        }
    }

    @ViewBuilder
    private var fontSizeControls: some View {
        Section {
            Button("Bigger", systemImage: "textformat.size.larger") {
                target?.increaseSize(context: fontResolutionContext)
            }
            Button("Smaller", systemImage: "textformat.size.smaller") {
                target?.decreaseSize(context: fontResolutionContext)
            }
        }
        Section {
            Picker("Font Size", selection: fontSizeSelection) {
                ForEach(FontSizes.choices(including: session.currentFontSize), id: \.self) { size in
                    Text("\(FontSizes.label(for: size)) pt").tag(Optional(size))
                }
            }
            .pickerStyle(.inline)
            .labelsHidden()
        }
    }

    /// Selecting a size applies it; the check mark follows the selected text's size.
    private var fontSizeSelection: Binding<CGFloat?> {
        Binding {
            session.currentFontSize
        } set: { size in
            if let size { target?.apply(pointSize: size, context: fontResolutionContext) }
        }
    }

    @ViewBuilder
    private var emphasisButtons: some View {
        Button("Bold", systemImage: "bold") { target?.toggleBold(context: fontResolutionContext) }
        Button("Italic", systemImage: "italic") { target?.toggleItalic(context: fontResolutionContext) }
        Button("Underline", systemImage: "underline") { target?.toggleUnderline() }
        Button("Strikethrough", systemImage: "strikethrough") { target?.toggleStrikethrough() }
    }

    private var bulletButton: some View {
        Button("Bulleted Item", systemImage: "list.bullet") { target?.insertBullet() }
    }

    // MARK: Attachments

    @ViewBuilder
    private var attachmentTools: some View {
        if availableWidth >= expandedAttachmentWidth {
            photosButton
            filesButton
        } else {
            Menu {
                photosButton
                filesButton
            } label: {
                Label("Attach", systemImage: "paperclip")
            }
        }
    }

    private var photosButton: some View {
        Button("Photos", systemImage: "photo.on.rectangle") { isPickingPhotos = true }
    }

    private var filesButton: some View {
        Button("Files", systemImage: "folder") { isImportingFiles = true }
    }

    private func importPhotos(_ items: [PhotosPickerItem]) async {
        var originals: [Data] = []
        for item in items {
            if let data = try? await item.loadTransferable(type: Data.self) {
                originals.append(data)
            }
        }
        photoItems = []
        let images = await ImageProcessing.preparedImagesInBackground(from: originals)
        if !images.isEmpty { onImportImages(images) }
    }

    private func importFiles(_ urls: [URL]) {
        let originals = urls.compactMap { url -> Data? in
            let didAccess = url.startAccessingSecurityScopedResource()
            defer { if didAccess { url.stopAccessingSecurityScopedResource() } }
            return try? Data(contentsOf: url)
        }
        Task {
            let images = await ImageProcessing.preparedImagesInBackground(from: originals)
            if !images.isEmpty { onImportImages(images) }
        }
    }
}
