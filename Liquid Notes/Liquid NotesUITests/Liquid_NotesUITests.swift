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
    private func launchApp() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTesting"]
        app.launch()
        return app
    }

    /// Opens a new canvas from the sidebar's Canvases collection.
    @MainActor
    private func openNewCanvas(in app: XCUIApplication) {
        // The row's label includes its count badge, such as "Canvases, 0".
        let canvases = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Canvases")).firstMatch
        XCTAssertTrue(canvases.waitForExistence(timeout: 5), "Canvases collection should be in the sidebar")
        canvases.tap()

        let newCanvas = app.buttons["New Canvas"].firstMatch
        XCTAssertTrue(newCanvas.waitForExistence(timeout: 5), "Empty Canvases list should offer New Canvas")
        newCanvas.tap()
    }

    @MainActor
    func testDoubleTapOnCanvasAddsTypableTextBox() throws {
        let app = launchApp()
        openNewCanvas(in: app)

        // Give the canvas a moment to open on its Origin scene.
        let zoomButton = app.buttons["Zoom"].firstMatch
        XCTAssertTrue(zoomButton.waitForExistence(timeout: 5), "Canvas should show its zoom level")

        app.coordinate(withNormalizedOffset: CGVector(dx: 0.55, dy: 0.55)).doubleTap()

        let textBox = app.textViews["Text box"].firstMatch
        XCTAssertTrue(textBox.waitForExistence(timeout: 5), "Double-tapping the canvas should add a text box")

        textBox.typeText("Hello canvas")
        let typed = app.textViews.matching(NSPredicate(format: "value CONTAINS %@", "Hello canvas")).firstMatch
        XCTAssertTrue(typed.waitForExistence(timeout: 5), "Text typed into the new box should appear in it")
    }

    @MainActor
    func testAddTextBoxButtonOnCanvasAddsTypableTextBox() throws {
        let app = launchApp()
        openNewCanvas(in: app)

        // On narrow layouts the button is inside the Text menu.
        let addButton = app.buttons["Add Text Box"].firstMatch
        if !addButton.waitForExistence(timeout: 3) {
            app.buttons["Text"].firstMatch.tap()
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
        let app = launchApp()
        openNewCanvas(in: app)

        let zoomButton = app.buttons["Zoom"].firstMatch
        XCTAssertTrue(zoomButton.waitForExistence(timeout: 5))
        XCTAssertEqual(zoomButton.value as? String, "100 percent", "New canvases open at 100%")

        zoomButton.tap()
        app.buttons["50%"].firstMatch.tap()

        expectation(for: NSPredicate(format: "value == %@", "50 percent"), evaluatedWith: zoomButton)
        waitForExpectations(timeout: 5)
    }

    @MainActor
    func testScenesStartWithOriginAndCanAddCurrentView() throws {
        let app = launchApp()
        openNewCanvas(in: app)

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
        let app = launchApp()
        let notebooks = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Notebooks")).firstMatch
        XCTAssertTrue(notebooks.waitForExistence(timeout: 5))
        notebooks.tap()
        app.buttons["New Notebook"].firstMatch.tap()
        app.buttons["Create"].firstMatch.tap()

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
