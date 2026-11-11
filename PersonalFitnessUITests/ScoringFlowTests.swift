import XCTest

final class ScoringFlowTests: XCTestCase {
    @MainActor func testExplicitRPEProducesRealActivityScoreAndSetupRequestsNothingOnLaunch() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--nutrition-ui-test-store", UUID().uuidString,
            "-health.readRequestCompleted.v1", "NO", "-health.sleepReadRequestCompleted.v1", "NO", "-health.recoveryReadRequestCompleted.v1", "NO"]
        app.launch()
        XCTAssertTrue(app.buttons["ring.strain"].waitForExistence(timeout: 20))
        XCTAssertTrue(app.buttons["ring.strain"].label.contains("Log activity"))
        XCTAssertTrue(app.buttons["ring.recovery"].label.contains("Build baseline"))
        XCTAssertFalse(app.alerts.firstMatch.exists)
        app.tabBars.buttons["Training"].tap(); app.buttons["Log cardio"].tap()
        fill(app, "Duration (minutes)", "10")
        let effort = app.buttons["session.rpe"]
        for _ in 0..<8 { if effort.exists && effort.isHittable && effort.frame.minY >= 110 && effort.frame.maxY < app.frame.height - 80 { break }; app.swipeUp() }
        XCTAssertTrue(effort.isHittable); effort.tap(); app.buttons["6"].tap()
        app.navigationBars["Log cardio"].buttons["Save"].tap()
        app.tabBars.buttons["Today"].tap(); app.buttons["Refresh"].tap()
        let ring = app.buttons["ring.strain"]
        let expectation = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label CONTAINS %@", "20 / 100"), object: ring)
        XCTAssertEqual(XCTWaiter.wait(for: [expectation], timeout: 10), .completed)
        XCTAssertTrue(ring.label.contains("Provisional"))
        let today = XCTAttachment(screenshot: app.screenshot()); today.name = "Today with explicitly logged synthetic RPE fixture"; today.lifetime = .keepAlways; add(today)
        ring.tap()
        XCTAssertTrue(app.staticTexts["strain.score"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "60 session-RPE units")).firstMatch.exists)
        let capture = XCTAttachment(screenshot: app.screenshot()); capture.name = "Synthetic locally logged RPE fixture, not owner data"; capture.lifetime = .keepAlways; add(capture)
        app.terminate(); app.launch()
        XCTAssertTrue(app.buttons["ring.strain"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["ring.strain"].label.contains("20 / 100"))
    }
    @MainActor func testScoringSetupValidatesAndPersistsWithoutGuessingProfile() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--nutrition-ui-test-store", UUID().uuidString, "-health.readRequestCompleted.v1", "NO", "-health.sleepReadRequestCompleted.v1", "NO", "-health.recoveryReadRequestCompleted.v1", "NO"]
        app.launch(); app.tabBars.buttons["More"].tap(); app.buttons["Scoring & expenditure settings"].tap()
        let target = app.textFields["Session-RPE target"]
        XCTAssertTrue(target.waitForExistence(timeout: 5))
        fill(app, "Session-RPE target", "0")
        app.buttons["Save scoring settings"].tap()
        XCTAssertTrue(app.alerts["Unable to save"].waitForExistence(timeout: 5)); app.alerts.buttons["OK"].tap()
        XCTAssertEqual(target.value as? String, "0")
        fill(app, "Session-RPE target", "400")
        app.buttons["Save scoring settings"].tap()
        XCTAssertTrue(app.navigationBars["More"].waitForExistence(timeout: 5))
        app.terminate(); app.launch(); app.tabBars.buttons["More"].tap(); app.buttons["Scoring & expenditure settings"].tap()
        XCTAssertEqual(app.textFields["Session-RPE target"].value as? String, "400")
        XCTAssertFalse(app.textFields["Equation age (years)"].exists)
        XCTAssertFalse(app.alerts.firstMatch.exists)
    }
    @MainActor func testEnergyProgressUsesLoggedIntakeOverPreservedHistoricalExpenditure() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--nutrition-ui-test-store", UUID().uuidString,
            "-health.readRequestCompleted.v1", "NO", "-health.sleepReadRequestCompleted.v1", "NO", "-health.recoveryReadRequestCompleted.v1", "NO"]
        app.launch(); app.tabBars.buttons["More"].tap(); app.buttons["Scoring & expenditure settings"].tap()
        fill(app, "Full-day expenditure (kcal)", "2000")
        app.buttons["Save scoring settings"].tap()
        app.tabBars.buttons["Today"].tap(); app.buttons["Previous day"].tap()
        app.buttons["Quick actions"].tap(); app.buttons["quick.food"].tap(); app.buttons["Create food"].tap()
        fill(app, "Name", "Synthetic energy progress fixture")
        fill(app, "Calories (kcal)", "1500")
        for title in ["Protein (g)", "Carbohydrates (g)", "Fat (g)"] { fill(app, title, "0") }
        app.buttons["Save & log"].tap()
        XCTAssertTrue(app.navigationBars["Log portion"].waitForExistence(timeout: 5))
        app.navigationBars["Log portion"].buttons["Save"].tap()
        app.tabBars.buttons["Today"].tap(); app.buttons["Refresh"].tap()
        let ring = app.buttons["ring.balance"]
        let ratio = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label CONTAINS %@", "Intake / expenditure: 75%"), object: ring)
        XCTAssertEqual(XCTWaiter.wait(for: [ratio], timeout: 10), .completed)
        XCTAssertTrue(ring.label.contains("-500")); XCTAssertTrue(ring.label.contains("Est. deficit"))
        let capture = XCTAttachment(screenshot: app.screenshot()); capture.name = "Synthetic 1500 intake over explicit 2000 expenditure - actual progress arc"; capture.lifetime = .keepAlways; add(capture)
        ring.tap()
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "Preserved closed-day prediction")).firstMatch.waitForExistence(timeout: 5))
        let detail = XCTAttachment(screenshot: app.screenshot()); detail.name = "Synthetic energy source and calculation detail"; detail.lifetime = .keepAlways; add(detail)
        app.terminate(); app.launch()
        app.buttons["Previous day"].tap()
        XCTAssertTrue(app.buttons["ring.balance"].label.contains("Intake / expenditure: 75%"))
    }
    @MainActor private func fill(_ app: XCUIApplication, _ title: String, _ text: String) {
        if app.buttons["Done editing"].isHittable { app.buttons["Done editing"].tap() }
        let field = app.textFields[title]
        for _ in 0..<12 {
            if field.exists && field.isHittable && field.frame.minY >= 110 && field.frame.maxY < app.frame.height * 0.65 { break }
            let movingDown = field.exists && field.frame.minY < 110
            let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.55))
            let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: movingDown ? 0.75 : 0.35))
            start.press(forDuration: 0.1, thenDragTo: end)
        }
        XCTAssertTrue(field.exists && field.isHittable)
        field.tap(); field.coordinate(withNormalizedOffset: CGVector(dx: 0.99, dy: 0.5)).tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 3))
        let old = field.value as? String ?? ""
        let count = ["Required", "Optional", title].contains(old) ? 0 : old.count
        if count > 0 { field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: count)) }
        for character in text { field.typeText(String(character)) }
        if field.value as? String != text {
            let capture = XCTAttachment(screenshot: app.screenshot()); capture.name = "Synthetic settings input diagnostic"; capture.lifetime = .keepAlways; add(capture)
            let hierarchy = XCTAttachment(string: app.debugDescription); hierarchy.name = "Isolated test UI hierarchy"; hierarchy.lifetime = .keepAlways; add(hierarchy)
        }
        XCTAssertEqual(field.value as? String, text)
        if app.buttons["Done editing"].isHittable { app.buttons["Done editing"].tap() }
    }

}
