import Foundation
import PDFKit
import SwiftUI

enum PDFSupport {
    /// The displayed size of each page in a PDF, accounting for page rotation.
    static func pageSizes(of document: PDFDocument) -> [CGSize] {
        (0..<document.pageCount).compactMap { index in
            guard let page = document.page(at: index) else { return nil }
            let bounds = page.bounds(for: .cropBox)
            let isSideways = abs(page.rotation) % 180 == 90
            return isSideways
                ? CGSize(width: bounds.height, height: bounds.width)
                : bounds.size
        }
    }

    /// Renders one page of a PDF at the given pixel width.
    static func image(of page: PDFPage, pixelWidth: CGFloat) -> CGImage? {
        let bounds = page.bounds(for: .cropBox)
        let isSideways = abs(page.rotation) % 180 == 90
        let pageSize = isSideways ? CGSize(width: bounds.height, height: bounds.width) : bounds.size
        guard pageSize.width > 0 else { return nil }
        let scale = pixelWidth / pageSize.width
        let target = CGSize(width: pageSize.width * scale, height: pageSize.height * scale)
        return page.thumbnail(of: target, for: .cropBox).cgImageValue
    }

    static func image(ofPage index: Int, in data: Data, pixelWidth: CGFloat) -> CGImage? {
        guard let page = PDFDocument(data: data)?.page(at: index) else { return nil }
        return image(of: page, pixelWidth: pixelWidth)
    }

    /// Creates a notebook from a PDF file, with one notebook page per PDF page.
    static func makeNotebook(fromPDFAt url: URL, folder: Folder?) -> Notepad? {
        let didAccess = url.startAccessingSecurityScopedResource()
        defer { if didAccess { url.stopAccessingSecurityScopedResource() } }

        guard let data = try? Data(contentsOf: url),
              let document = PDFDocument(data: data),
              document.pageCount > 0
        else { return nil }

        let notebook = Notepad(
            title: url.deletingPathExtension().lastPathComponent,
            type: .notebook,
            folder: folder
        )
        notebook.paperStyle = .blank
        notebook.pdfData = data
        notebook.pages = pageSizes(of: document).enumerated().map { index, size in
            NotebookPage(index: index, size: size, pdfPageIndex: index)
        }
        return notebook
    }
}

/// Renders pages of one PDF document. Being an actor, it serializes access to the non-thread-safe `PDFDocument`.
actor PDFPageRenderer {
    private let document: PDFDocument?

    init(data: Data?) {
        document = data.flatMap { PDFDocument(data: $0) }
    }

    func image(ofPage index: Int, pixelWidth: CGFloat) -> CGImage? {
        guard let page = document?.page(at: index) else { return nil }
        return PDFSupport.image(of: page, pixelWidth: pixelWidth)
    }
}

/// Displays a PDF with the system PDF viewer.
struct PDFKitView: View {
    let data: Data

    var body: some View {
        PDFKitRepresentable(data: data)
            .ignoresSafeArea(edges: .bottom)
    }
}

#if canImport(UIKit)
private struct PDFKitRepresentable: UIViewRepresentable {
    let data: Data

    func makeUIView(context: Context) -> PDFView {
        let view = PDFView()
        view.autoScales = true
        view.document = PDFDocument(data: data)
        return view
    }

    func updateUIView(_ view: PDFView, context: Context) {}
}
#else
private struct PDFKitRepresentable: NSViewRepresentable {
    let data: Data

    func makeNSView(context: Context) -> PDFView {
        let view = PDFView()
        view.autoScales = true
        view.document = PDFDocument(data: data)
        return view
    }

    func updateNSView(_ view: PDFView, context: Context) {}
}
#endif
