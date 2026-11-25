//
//  Liquid_NotesUITests.swift
//  Liquid NotesUITests
//
//  Created by Caner Kucuk on 8/19/25.
//

import XCTest

private extension XCUIElement {
    /// Waits for the element to become enabled, or disabled when `enabled` is false.
    func waitForEnabled(_ enabled: Bool = true, timeout: TimeInterval = 3) -> Bool {
        let deadline = Date.now.addingTimeInterval(timeout)
        while Date.now < deadline {
            if isEnabled == enabled { return true }
            RunLoop.current.run(until: .now.addingTimeInterval(0.2))
        }
        return isEnabled == enabled
    }
}

final class Liquid_NotesUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    /// Launches with an empty library that isn't saved.
    @MainActor
    private func launchApp(_ extraArguments: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTesting"] + extraArguments
        app.launch()
        return app
    }

    /// Launches straight into a new, empty canvas.
    @MainActor
    private func launchIntoNewCanvas(_ extraArguments: [String] = []) -> XCUIApplication {
        let app = launchApp(["-uiTestingOpenNewCanvas"] + extraArguments)
        XCTAssertTrue(app.buttons["Zoom"].firstMatch.waitForExistence(timeout: 10), "The new canvas should open")
        return app
    }

    /// Taps a toolbar button, looking in the toolbar's overflow menu if there wasn't room for it.
    @MainActor
    private func tapToolbarButton(_ label: String, in app: XCUIApplication) {
        let button = app.buttons[label].firstMatch
        if !button.waitForExistence(timeout: 2) {
            app.buttons["More"].firstMatch.tap()
        }
        XCTAssertTrue(app.buttons[label].firstMatch.waitForExistence(timeout: 3), "\(label) should be in the toolbar")
        app.buttons[label].firstMatch.tap()
    }

    /// Regression test: drawing on a canvas used to need a canvas-sized GPU texture, which crashed the
    /// app on the first stroke. Draws at several zoom levels and checks the app is still running.
    @MainActor
    func testDrawingOnCanvasAtAnyZoomDoesNotCrash() throws {
        // The simulator has no Apple Pencil, so this test turns on drawing with a finger.
        let app = launchIntoNewCanvas()
        tapToolbarButton("Draw with Touch", in: app)
        let zoomButton = app.buttons["Zoom"].firstMatch

        func drawStroke() {
            let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.55, dy: 0.45))
            let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.8, dy: 0.6))
            start.press(forDuration: 0.05, thenDragTo: end)
        }

        drawStroke()
        for level in ["400%", "10%"] {
            zoomButton.tap()
            app.buttons[level].firstMatch.tap()
            drawStroke()
        }

        XCTAssertEqual(app.state, .runningForeground, "Drawing shouldn't crash the app")
        let undo = app.buttons["Undo"].firstMatch
        XCTAssertTrue(undo.waitForExistence(timeout: 3))
        XCTAssertTrue(undo.isEnabled, "Strokes should be undoable")
    }

    /// With Draw with Touch off, a finger doesn't draw; turning it on lets it draw, and off again stops it.
    @MainActor
    func testDrawWithTouchTurnsFingerDrawingOnAndOff() throws {
        let app = launchIntoNewCanvas()
        let undo = app.buttons["Undo"].firstMatch

        func drawStroke() {
            let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.55, dy: 0.45))
            let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.8, dy: 0.6))
            start.press(forDuration: 0.05, thenDragTo: end)
        }

        drawStroke()
        XCTAssertFalse(undo.isEnabled, "A finger doesn't draw until Draw with Touch is on")

        tapToolbarButton("Draw with Touch", in: app)
        drawStroke()
        XCTAssertTrue(undo.waitForEnabled(), "With Draw with Touch on, a finger draws")

        undo.tap()
        XCTAssertTrue(undo.waitForEnabled(false), "Undo removes the stroke")
        tapToolbarButton("Draw with Touch", in: app)
        drawStroke()
        XCTAssertFalse(undo.isEnabled, "Turning Draw with Touch off stops finger drawing")
    }

    @MainActor
    func testDoubleTapOnCanvasAddsTypableTextBox() throws {
        let app = launchIntoNewCanvas()

        app.coordinate(withNormalizedOffset: CGVector(dx: 0.6, dy: 0.55)).doubleTap()

        let textBox = app.textViews["Text box"].firstMatch
        XCTAssertTrue(textBox.waitForExistence(timeout: 5), "Double-tapping the canvas should add a text box")

        textBox.typeText("Hello canvas")
        let typed = app.textViews.matching(NSPredicate(format: "value CONTAINS %@", "Hello canvas")).firstMatch
        XCTAssertTrue(typed.waitForExistence(timeout: 5), "Text typed into the new box should appear in it")
    }

    @MainActor
    func testAddTextBoxButtonOnCanvasAddsTypableTextBox() throws {
        let app = launchIntoNewCanvas()

        // On narrow layouts the button is inside the Text menu.
        if !app.buttons["Add Text Box"].firstMatch.waitForExistence(timeout: 2) {
            tapToolbarButton("Text", in: app)
        }
        app.buttons["Add Text Box"].firstMatch.tap()

        let textBox = app.textViews["Text box"].firstMatch
        XCTAssertTrue(textBox.waitForExistence(timeout: 5), "Add Text Box should add a text box")
        textBox.typeText("Typed via toolbar")
        let typed = app.textViews.matching(NSPredicate(format: "value CONTAINS %@", "Typed via toolbar")).firstMatch
        XCTAssertTrue(typed.waitForExistence(timeout: 5), "Text typed into the new box should appear in it")
    }

    @MainActor
    func testZoomMenuChangesZoomLevel() throws {
        let app = launchIntoNewCanvas()

        let zoomButton = app.buttons["Zoom"].firstMatch
        XCTAssertEqual(zoomButton.value as? String, "100 percent", "New canvases open at 100%")

        zoomButton.tap()
        app.buttons["50%"].firstMatch.tap()

        expectation(for: NSPredicate(format: "value == %@", "50 percent"), evaluatedWith: zoomButton)
        waitForExpectations(timeout: 5)
    }

    @MainActor
    func testScenesStartWithOriginAndCanAddCurrentView() throws {
        let app = launchIntoNewCanvas()

        let scenesButton = app.buttons["Scenes"].firstMatch
        XCTAssertTrue(scenesButton.waitForExistence(timeout: 5))
        scenesButton.tap()
        XCTAssertTrue(app.buttons["Origin"].firstMatch.waitForExistence(timeout: 3), "Every canvas has an Origin scene")

        app.buttons["Add Scene from Current View"].firstMatch.tap()
        scenesButton.tap()
        XCTAssertTrue(app.buttons["Scene 2"].firstMatch.waitForExistence(timeout: 3), "Adding a scene should list it")
        app.buttons["Scene 2"].firstMatch.tap()

        // After zooming elsewhere, going to Origin restores its 100% zoom.
        let zoomButton = app.buttons["Zoom"].firstMatch
        zoomButton.tap()
        app.buttons["200%"].firstMatch.tap()
        expectation(for: NSPredicate(format: "value == %@", "200 percent"), evaluatedWith: zoomButton)
        waitForExpectations(timeout: 5)

        scenesButton.tap()
        app.buttons["Origin"].firstMatch.tap()
        expectation(for: NSPredicate(format: "value == %@", "100 percent"), evaluatedWith: zoomButton)
        waitForExpectations(timeout: 5)
    }

    @MainActor
    func testNotebookPaperStyleCanBeChanged() throws {
        // Opens the New Notebook sheet directly.
        let app = launchApp(["-uiTestingOpenNewNotebook"])
        let create = app.buttons["Create"].firstMatch
        XCTAssertTrue(create.waitForExistence(timeout: 10), "The New Notebook sheet should open")
        create.tap()

        let paperStyle = app.buttons["Paper Style"].firstMatch
        XCTAssertTrue(paperStyle.waitForExistence(timeout: 5), "Notebooks show the paper style button")
        paperStyle.tap()
        XCTAssertTrue(app.buttons["Grid"].firstMatch.waitForExistence(timeout: 3), "The menu lists paper styles")
        XCTAssertTrue(app.buttons["Add Page"].firstMatch.exists, "The menu can add a page")
    }

    /// The library's New button works with a pointer as well as touch, on iPad and on Mac.
    @MainActor
    func testNewNoteButtonOpensAnEditor() throws {
        let app = launchApp()
        let newNote = app.buttons["New Note"].firstMatch
        XCTAssertTrue(newNote.waitForExistence(timeout: 10), "The library shows a New Note button")
        newNote.tap()
        XCTAssertTrue(app.buttons["Sketch"].firstMatch.waitForExistence(timeout: 5) || app.buttons["More"].firstMatch.exists,
                      "A new note opens in the editor")
    }

    /// Search is in the top bar of the first screen, not the bottom, and finds notepads.
    @MainActor
    func testSearchIsAtTheTopAndFindsNotepads() throws {
        // Starts with one canvas to find. Back out to the first screen of the library.
        let app = launchApp(["-uiTestingOpenNewCanvas"])
        let back = app.buttons["BackButton"].firstMatch
        _ = back.waitForExistence(timeout: 5)
        while back.exists && back.isHittable { back.tap() }
        // On iPad the canvas hides the library instead of pushing it, so bring the sidebar back.
        let showSidebar = app.buttons["Show Sidebar"].firstMatch
        if showSidebar.waitForExistence(timeout: 2) { showSidebar.tap() }

        let search = app.searchFields.firstMatch.exists ? app.searchFields.firstMatch : app.buttons["Search"].firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 5), "The library shows search")
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.lifetime = .keepAlways
        add(attachment)
        XCTAssertLessThan(search.frame.midY, app.frame.height / 3, "Search is at the top of the screen")

        search.tap()
        let field = app.searchFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 3))
        field.typeText("Untitled\n")
        XCTAssertTrue(app.staticTexts["Untitled Canvas"].firstMatch.waitForExistence(timeout: 5),
                      "Searching finds the canvas")

        // The results list keeps search at the top too.
        let results = XCTAttachment(screenshot: app.screenshot())
        results.lifetime = .keepAlways
        add(results)
        let newNote = app.buttons["New Note"].firstMatch
        XCTAssertTrue(newNote.waitForExistence(timeout: 5))
        let listSearch = app.searchFields.firstMatch.exists ? app.searchFields.firstMatch : app.buttons["Search"].firstMatch
        XCTAssertTrue(listSearch.exists)
        XCTAssertLessThan(listSearch.frame.minX, newNote.frame.minX, "Search comes before New")
        XCTAssertLessThan(listSearch.frame.midY, app.frame.height / 3, "The list's search is at the top")
    }

    /// iPhone and iPad get the Pencil tools plus a separate Draw with Touch button. The Mac has no
    /// Apple Pencil, so it gets one Draw with Trackpad button instead.
    @MainActor
    func testCanvasToolbarMatchesThePlatform() throws {
        let app = launchIntoNewCanvas()
        XCTAssertTrue(app.buttons["Scenes"].firstMatch.exists)
        XCTAssertTrue(app.buttons["Undo"].firstMatch.exists)
        let pencilTools = app.descendants(matching: .any)["Apple Pencil Tools"].firstMatch
        let touchDrawing = app.descendants(matching: .any)["Draw with Touch"].firstMatch
        let trackpadDrawing = app.descendants(matching: .any)["Draw with Trackpad"].firstMatch
        #if targetEnvironment(macCatalyst)
        XCTAssertTrue(trackpadDrawing.waitForExistence(timeout: 3), "Mac offers drawing with the trackpad")
        XCTAssertFalse(pencilTools.exists, "There's no Apple Pencil on Mac")
        XCTAssertFalse(touchDrawing.exists)
        #else
        XCTAssertTrue(pencilTools.waitForExistence(timeout: 3), "iPad shows the Apple Pencil tools")
        XCTAssertTrue(touchDrawing.exists, "Drawing with a finger is its own button")
        XCTAssertFalse(trackpadDrawing.exists)
        #endif

        // Undo and Redo are the same size.
        XCTAssertEqual(app.buttons["Undo"].firstMatch.frame.size, app.buttons["Redo"].firstMatch.frame.size)
    }

    /// Notebooks open fitted to the screen, and can zoom to the paper's real size and back.
    @MainActor
    func testNotebookZoomFitsAndShowsActualSize() throws {
        let app = launchApp(["-uiTestingOpenNewNotebook"])
        let create = app.buttons["Create"].firstMatch
        XCTAssertTrue(create.waitForExistence(timeout: 10))
        create.tap()

        let zoom = app.buttons["Zoom"].firstMatch
        XCTAssertTrue(zoom.waitForExistence(timeout: 5), "Notebooks have a zoom menu")
        let page = app.descendants(matching: .any)["Page 1 of 1"].firstMatch
        XCTAssertTrue(page.waitForExistence(timeout: 5))
        let fittedWidth = page.frame.width
        XCTAssertLessThanOrEqual(page.frame.height, app.frame.height, "Fit to Screen shows a whole page")

        zoom.tap()
        XCTAssertTrue(app.buttons["Fit to Screen"].firstMatch.waitForExistence(timeout: 3))
        app.buttons["150%"].firstMatch.tap()
        expectation(for: NSPredicate(format: "value == %@", "150 percent"), evaluatedWith: zoom)
        waitForExpectations(timeout: 5)
        XCTAssertGreaterThan(page.frame.width, fittedWidth, "Zooming in makes the page bigger")

        zoom.tap()
        app.buttons["Fit to Screen"].firstMatch.tap()
        let fitted = NSPredicate { _, _ in abs(page.frame.width - fittedWidth) < 1 }
        expectation(for: fitted, evaluatedWith: page)
        waitForExpectations(timeout: 5)

        // Pinching out zooms in.
        page.pinch(withScale: 1.5, velocity: 1)
        let pinched = NSPredicate { _, _ in page.frame.width > fittedWidth + 20 }
        expectation(for: pinched, evaluatedWith: page)
        waitForExpectations(timeout: 5)
    }

    /// Text boxes show their text sharply when not being edited, and switch to editing when tapped.
    @MainActor
    func testTextBoxShowsTextAndEditsWhenTapped() throws {
        let app = launchIntoNewCanvas()
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.6, dy: 0.55)).doubleTap()
        let editor = app.textViews["Text box"].firstMatch
        XCTAssertTrue(editor.waitForExistence(timeout: 5))
        editor.typeText("Hello")

        // Tapping empty canvas moves on, and the box shows its text without a text editor.
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.3, dy: 0.85)).tap()
        let shown = app.descendants(matching: .any)["Text box"].firstMatch
        XCTAssertTrue(app.textViews.count == 0 || !app.textViews["Text box"].exists, "Only the box being edited uses a text editor")
        XCTAssertTrue(shown.waitForExistence(timeout: 3))

        // Tapping the text edits it again, with the cursor at the end.
        shown.tap()
        XCTAssertTrue(editor.waitForExistence(timeout: 3))
        editor.typeText(" there")
        let typed = app.textViews.matching(NSPredicate(format: "value CONTAINS %@", "Hello there")).firstMatch
        XCTAssertTrue(typed.waitForExistence(timeout: 5))
    }

    @MainActor
    func testLaunchPerformance() throws {
        measure(metrics: [XCTApplicationLaunchMetric()]) {
            XCUIApplication().launch()
        }
    }
}
