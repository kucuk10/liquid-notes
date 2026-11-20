#if canImport(UIKit)
import SwiftUI

/// Toolbar controls shared by the notebook and canvas editors.
struct DrawingToolbarItems: ToolbarContent {
    @Bindable var session: DrawingSession

    var body: some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            Toggle(isOn: $session.allowsFingerDrawing) {
                Label("Draw with Finger", systemImage: "hand.draw")
            }
            .help("When off, only Apple Pencil draws and your finger scrolls")

            Toggle(isOn: $session.showsToolPicker) {
                Label("Drawing Tools", systemImage: "pencil.tip.crop.circle")
            }
        }
    }
}
#endif
