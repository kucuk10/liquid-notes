import Testing
@testable import Liquid_Notes

struct Liquid_NotesTests {
    @Test func createNotepad() throws {
        let note = Notepad(title: "Test", type: .postIt)
        #expect(note.type == .postIt)
        #expect(note.title == "Test")
    }
}
