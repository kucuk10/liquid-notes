import SwiftUI
import SwiftData

/// A horizontal row of a note's attachments.
struct AttachmentStrip: View {
    let notepad: Notepad
    @Environment(\.modelContext) private var modelContext
    @State private var openedAttachment: Attachment?

    var body: some View {
        ScrollView(.horizontal) {
            LazyHStack(spacing: 12) {
                ForEach(notepad.sortedAttachments) { attachment in
                    Button {
                        openedAttachment = attachment
                    } label: {
                        AttachmentThumbnail(attachment: attachment)
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        Button("Delete", systemImage: "trash", role: .destructive) {
                            modelContext.delete(attachment)
                            notepad.touch()
                        }
                    }
                }
            }
            .padding(12)
        }
        .scrollIndicators(.hidden)
        .frame(height: 120)
        .sheet(item: $openedAttachment) { attachment in
            AttachmentViewer(attachment: attachment)
        }
    }
}

/// A square preview of an attachment.
struct AttachmentThumbnail: View {
    let attachment: Attachment
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let data = attachment.data
        let dark = colorScheme == .dark

        ZStack(alignment: .bottomLeading) {
            Rectangle().fill(.background.secondary)

            if let data {
                switch attachment.kind {
                case .image:
                    AsyncRenderedImage(key: AnyHashable(data)) {
                        ImageProcessing.thumbnail(from: data, maxPixelSize: 300)
                    } placeholder: {
                        ProgressView()
                    }
                    .scaledToFill()
                case .pdf:
                    AsyncRenderedImage(key: AnyHashable(data)) {
                        PDFSupport.image(ofPage: 0, in: data, pixelWidth: 300)
                    } placeholder: {
                        Image(systemName: "doc.richtext")
                    }
                    .scaledToFit()
                    .padding(6)
                case .sketch:
                    AsyncRenderedImage(key: [AnyHashable(data), AnyHashable(dark)]) {
                        DrawingRenderer.image(from: data, scale: 1, dark: dark)
                    } placeholder: {
                        Image(systemName: "scribble")
                    }
                    .scaledToFit()
                    .padding(8)
                }
            }

            if attachment.kind == .pdf {
                Text("PDF")
                    .font(.caption2.bold())
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(.thinMaterial, in: .capsule)
                    .padding(6)
            }
        }
        .frame(width: 96, height: 96)
        .clipShape(.rect(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(.separator))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
    }

    private var accessibilityLabel: Text {
        switch attachment.kind {
        case .image: Text("Image attachment")
        case .pdf: Text("PDF attachment, \(attachment.filename)")
        case .sketch: Text("Sketch attachment")
        }
    }
}

/// Full-size viewer for an attachment. Sketches are editable on iPhone and iPad.
struct AttachmentViewer: View {
    @Bindable var attachment: Attachment
    @Environment(\.dismiss) private var dismiss
    @Environment(\.displayScale) private var displayScale

    var body: some View {
        if attachment.kind == .sketch {
            SketchEditorView(initialData: attachment.data) { data in
                if let data {
                    attachment.data = data
                    attachment.notepad?.touch()
                }
            }
        } else {
            viewer
        }
    }

    private var viewer: some View {
        NavigationStack {
            Group {
                if let data = attachment.data {
                    switch attachment.kind {
                    case .pdf:
                        PDFKitView(data: data)
                    case .image:
                        AsyncRenderedImage(key: AnyHashable(data)) {
                            ImageProcessing.thumbnail(from: data, maxPixelSize: 4096)
                        } placeholder: {
                            ProgressView()
                        }
                        .scaledToFit()
                        .padding()
                    case .sketch:
                        AsyncRenderedImage(key: AnyHashable(data)) {
                            DrawingRenderer.image(from: data, scale: 2)
                        } placeholder: {
                            ProgressView()
                        }
                        .scaledToFit()
                        .padding()
                        .background(.white)
                    }
                } else {
                    ContentUnavailableView("Attachment Unavailable", systemImage: "exclamationmark.triangle")
                }
            }
            .navigationTitle(attachment.filename)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

/// A full-screen sketch pad used for sketch attachments.
struct SketchEditorView: View {
    let initialData: Data?
    let onSave: (Data?) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var session = EditorSession(includesTextTool: false)
    @State private var data: Data?

    init(initialData: Data?, onSave: @escaping (Data?) -> Void) {
        self.initialData = initialData
        self.onSave = onSave
        _data = State(initialValue: initialData)
    }

    var body: some View {
        NavigationStack {
            PencilCanvasView(
                canvasID: "sketch",
                drawingData: data,
                layout: .infinite(width: 1024),
                session: session
            ) { data = $0 }
            .background(.background)
            .ignoresSafeArea(.container, edges: .bottom)
            .navigationTitle("Sketch")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", role: .cancel) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        onSave(data)
                        dismiss()
                    }
                }
                ToolbarItemGroup(placement: .primaryAction) {
                    DrawingToolsToggles(session: session)
                }
            }
            .onAppear { session.activeCanvasID = "sketch" }
        }
        .interactiveDismissDisabled(data != initialData)
    }
}
