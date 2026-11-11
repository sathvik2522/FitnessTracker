import XCTest

final class DataExportFlowTests: XCTestCase {
    @MainActor
    func testExportExplainsLimitationsAndOpensSystemFileSaver() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--nutrition-ui-test-store", UUID().uuidString, "-health.readRequestCompleted.v1", "NO"]
        app.launch()
        XCTAssertTrue(app.tabBars.buttons["Progress"].waitForExistence(timeout: 15))
        app.tabBars.buttons["Progress"].tap()
        app.buttons["Export local data"].firstMatch.tap()
        XCTAssertTrue(app.buttons["data.export"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "In-app restore is not available")).firstMatch.exists)
        let export = app.buttons["data.export"]
        for _ in 0..<6 {
            if export.isHittable && export.frame.maxY < app.frame.height - 80 { break }
            app.swipeUp()
        }
        XCTAssertTrue(export.isHittable)
        export.tap()
        let opened = app.buttons["Save"].waitForExistence(timeout: 30)
        if !opened {
            let failure = XCTAttachment(screenshot: app.screenshot()); failure.name = "Isolated export state after tap"; failure.lifetime = .keepAlways; add(failure)
            let hierarchy = XCTAttachment(string: app.debugDescription); hierarchy.name = "Isolated export UI hierarchy"; hierarchy.lifetime = .keepAlways; add(hierarchy)
        }
        XCTAssertTrue(opened, "The system file saver must open after export preparation")
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "System JSON file export"; screenshot.lifetime = .keepAlways; add(screenshot)
        // Cancel is deliberate: tests must not create files in the user's Files locations.
        // iOS 27's saver has no Cancel button inside the selected folder.
        // Dismiss its native sheet by dragging the visible sheet top downward.
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.075))
            .press(forDuration: 0.1, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.85)))
        let enabled = NSPredicate(format: "enabled == true AND hittable == true")
        expectation(for: enabled, evaluatedWith: app.buttons["data.export"])
        waitForExpectations(timeout: 5)
        XCTAssertFalse(app.staticTexts["data.export.success"].exists, "Cancelling must not claim a saved file")
    }
}
