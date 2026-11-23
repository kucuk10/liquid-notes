//
//  Liquid_NotesUITests.swift
//  Liquid NotesUITests
//
//  Created by Caner Kucuk on 8/19/25.
//

import XCTest

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
        // The simulator has no Apple Pencil, so this test allows drawing with a finger.
        let app = launchIntoNewCanvas(["-uiTestingFingerDrawing"])
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

    @MainActor
    func testLaunchPerformance() throws {
        measure(metrics: [XCTApplicationLaunchMetric()]) {
            XCUIApplication().launch()
        }
    }
}
