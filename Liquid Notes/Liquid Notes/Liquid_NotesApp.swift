import SwiftUI
import SwiftData

@main
struct Liquid_NotesApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(for: Notepad.self)
    }
}
