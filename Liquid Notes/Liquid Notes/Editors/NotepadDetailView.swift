import SwiftUI
import SwiftData

/// Shows the editor that matches a notepad's type.
struct NotepadDetailView: View {
    let notepad: Notepad

    var body: some View {
        switch notepad.type {
        case .notes:
            NoteEditorView(notepad: notepad)
        case .notebook:
            NotebookView(notepad: notepad)
        case .canvas:
            CanvasNotepadView(notepad: notepad)
        }
    }
}
