import XCTest

final class ProgressFlowTests: XCTestCase {
    @MainActor func testProgressRangeControlsAtAccessibilitySize() {
        let app = XCUIApplication()
        app.launchArguments = ["--nutrition-ui-test-store", UUID().uuidString, "-health.readRequestCompleted.v1", "NO",
                               "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        app.launch()
        XCTAssertTrue(app.tabBars.buttons["Progress"].waitForExistence(timeout: 15))
        app.tabBars.buttons["Progress"].tap()
        let ninety = app.buttons["90 days"]
        reveal(ninety, app: app)
        XCTAssertGreaterThanOrEqual(ninety.frame.height, 44)
        ninety.tap()
        XCTAssertTrue(ninety.isSelected)
    }
    @MainActor func testInteractiveProgressWithSyntheticScreens() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--nutrition-ui-test-store", UUID().uuidString, "-health.readRequestCompleted.v1", "NO"]
        app.launch()
        XCTAssertTrue(app.tabBars.buttons["Progress"].waitForExistence(timeout: 15))
        app.tabBars.buttons["Progress"].tap()
        app.buttons["7 days"].tap()
        XCTAssertTrue(app.buttons["7 days"].isSelected)
        XCTAssertTrue(app.staticTexts["No calorie history available"].waitForExistence(timeout: 10))
        app.swipeUp()
        capture(app, "progress-empty")

        app.tabBars.buttons["Food"].tap()
        app.buttons["Add food"].tap(); app.buttons["Create food"].tap()
        fill(app, "Name", "Synthetic progress oats")
        fill(app, "Calories (kcal)", "200")
        fill(app, "Protein (g)", "10")
        fill(app, "Carbohydrates (g)", "30")
        fill(app, "Fat (g)", "5")
        app.buttons["Save & log"].tap()
        XCTAssertTrue(app.navigationBars["Log portion"].waitForExistence(timeout: 5))
        app.navigationBars["Log portion"].buttons["Save"].tap()
        app.tabBars.buttons["Progress"].tap()
        let chart = app.descendants(matching: .any)["progress.energyChart"].firstMatch
        reveal(chart, app: app)
        for _ in 0..<10 {
            if chart.exists && chart.frame.minY >= 110 && chart.frame.maxY < app.frame.height - 110 { break }
            let down = chart.exists && chart.frame.minY < 110
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.55))
                .press(forDuration: 0.1, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: down ? 0.7 : 0.4)))
        }
        XCTAssertTrue(chart.frame.minY >= 110 && chart.frame.maxY < app.frame.height - 110)
        chart.coordinate(withNormalizedOffset: CGVector(dx: 0.45, dy: 0.5))
            .press(forDuration: 0.2, thenDragTo: chart.coordinate(withNormalizedOffset: CGVector(dx: 0.55, dy: 0.5)))
        let details = app.descendants(matching: .any)["progress.energySelection"].firstMatch
        for _ in 0..<4 where !details.isHittable {
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.70))
                .press(forDuration: 0.1, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.58)))
        }
        XCTAssertTrue(details.waitForExistence(timeout: 5))
        XCTAssertTrue(details.label.contains("Logged intake"), details.label)
        capture(app, "progress-sparse")

        app.tabBars.buttons["Food"].tap()
        app.buttons["Previous diary day"].tap()
        app.buttons["Add food"].tap()
        let repeatPortion = app.buttons["Repeat portion"].firstMatch
        XCTAssertTrue(repeatPortion.waitForExistence(timeout: 5)); repeatPortion.tap()
        app.tabBars.buttons["Progress"].tap()
        reveal(chart, app: app)
        capture(app, "progress-populated")

        app.tabBars.buttons["Today"].tap()
        app.buttons["Quick actions"].tap(); app.buttons["quick.weight"].tap()
        let weight = app.textFields["Body weight (kg)"]
        XCTAssertTrue(weight.waitForExistence(timeout: 5)); focusWeight(weight, app: app)
        weight.typeText("80")
        app.navigationBars["Manual weight"].buttons["Save"].tap()
        app.tabBars.buttons["Progress"].tap()
        let weightChart = app.descendants(matching: .any)["progress.weightChart"].firstMatch
        reveal(weightChart, app: app)
        XCTAssertTrue(weightChart.isHittable)
        capture(app, "progress-weight")
    }

    @MainActor private func capture(_ app: XCUIApplication, _ name: String) {
        let image = XCTAttachment(screenshot: app.screenshot()); image.name = name; image.lifetime = .keepAlways; add(image)
    }
    @MainActor private func reveal(_ element: XCUIElement, app: XCUIApplication) {
        for _ in 0..<12 {
            if element.exists && element.isHittable { return }
            app.swipeUp()
        }
        XCTAssertTrue(element.exists && element.isHittable)
    }
    @MainActor private func fill(_ app: XCUIApplication, _ title: String, _ value: String) {
        if app.buttons["Done editing"].isHittable { app.buttons["Done editing"].tap() }
        let field = app.textFields[title]
        reveal(field, app: app)
        focusWeight(field, app: app)
        let old = field.value as? String ?? ""
        let count = old == title || old == "Required" ? 0 : old.count
        if count > 0 { field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: count)) }
        field.typeText(value)
        XCTAssertEqual(field.value as? String, value)
    }
    @MainActor
    func testSleepIsOptInAndDashboardShortcutTransfersHistoricalDate() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--nutrition-ui-test-store", UUID().uuidString,
            "-health.readRequestCompleted.v1", "NO", "-health.sleepReadRequestCompleted.v1", "NO"]
        app.launch()
        XCTAssertTrue(app.buttons["Sleep"].waitForExistence(timeout: 15))
        app.buttons["Sleep"].tap()
        XCTAssertTrue(app.buttons["Enable sleep insights"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["Review sleep access"].exists)
        app.navigationBars["Sleep & context"].buttons.element(boundBy: 0).tap()
        app.buttons["Previous day"].tap()
        app.buttons["Log food"].tap()
        let expected = Calendar.current.date(byAdding: .day, value: -1, to: Date.now)!
            .formatted(.dateTime.weekday(.wide).month(.wide).day().year())
        XCTAssertEqual(app.staticTexts["diary.selectedDate"].label, expected)
    }

    @MainActor func testHistoricalManualWeightEditingAndDailyMissingDataDetail() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--nutrition-ui-test-store", UUID().uuidString, "-health.readRequestCompleted.v1", "NO"]
        app.launch()
        XCTAssertTrue(app.tabBars.buttons["Progress"].waitForExistence(timeout: 15))
        app.tabBars.buttons["Progress"].tap()
        app.buttons["progress.period"].tap()
        app.buttons["Day"].tap()
        app.buttons["Previous"].tap()
        let history = app.buttons["Weight history & manual entry"]
        for _ in 0..<6 {
            if history.isHittable { break }
            app.swipeUp()
        }
        XCTAssertTrue(history.waitForExistence(timeout: 10)); history.tap()
        app.buttons["Add manual weight"].tap()
        let field = app.textFields["Body weight (kg)"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        focusWeight(field, app: app)
        for character in "80.2" { field.typeText(String(character)) }
        app.buttons["Save"].tap()
        let row = app.buttons.containing(NSPredicate(format: "label CONTAINS %@", "80.2 kg")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        for _ in 0..<5 {
            if row.isHittable && row.frame.maxY < app.frame.height - 110 { break }
            app.swipeUp()
        }
        XCTAssertTrue(row.isHittable && row.frame.maxY < app.frame.height - 110)
        row.tap()
        focusWeight(field, app: app)
        field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 4))
        for character in "81" { field.typeText(String(character)) }
        app.buttons["Save"].tap()
        XCTAssertTrue(app.buttons.containing(NSPredicate(format: "label CONTAINS %@", "81 kg")).firstMatch.waitForExistence(timeout: 10))
        try app.performAccessibilityAudit(for: .sufficientElementDescription)
        let image = XCTAttachment(screenshot: app.screenshot()); image.name = "Isolated progress manual-weight fixture"; image.lifetime = .keepAlways; add(image)
        app.navigationBars["Weight history"].buttons.element(boundBy: 0).tap()
        app.swipeUp()
        let day = app.buttons.containing(NSPredicate(format: "label CONTAINS %@", "No food data logged")).firstMatch
        XCTAssertTrue(day.waitForExistence(timeout: 10)); if !day.isHittable { app.swipeUp() }; day.tap()
        let missing = app.staticTexts["No food is recorded. Intake is unknown, not confirmed zero."]
        for _ in 0..<5 { if missing.exists { break }; app.swipeUp() }
        XCTAssertTrue(missing.waitForExistence(timeout: 5))
        app.terminate(); app.launch(); app.tabBars.buttons["Progress"].tap()
        app.buttons["progress.period"].tap(); app.buttons["Day"].tap(); app.buttons["Previous"].tap()
        for _ in 0..<6 {
            if history.isHittable { break }; app.swipeUp()
        }
        XCTAssertTrue(history.waitForExistence(timeout: 10)); history.tap()
        XCTAssertTrue(app.buttons.containing(NSPredicate(format: "label CONTAINS %@", "81 kg")).firstMatch.waitForExistence(timeout: 10))
    }
    @MainActor func testDashboardAccessibilityAtDefaultTextSize() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--nutrition-ui-test-store", UUID().uuidString, "-health.readRequestCompleted.v1", "NO"]
        app.launch()
        XCTAssertTrue(app.buttons["Connect Apple Health"].waitForExistence(timeout: 15))
        // Contrast and clipping diagnostics on this simulator are retained in
        // ENGINEERING_AUDIT.md; this regression verifies accessible descriptions.
        for _ in 0..<4 {
            try app.performAccessibilityAudit(for: .sufficientElementDescription)
            let scroll = app.scrollViews.firstMatch
            scroll.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.70))
                .press(forDuration: 0.1, thenDragTo: scroll.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.40)))
        }
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Audit dashboard metrics"; screenshot.lifetime = .keepAlways; add(screenshot)
    }

    @MainActor private func focusWeight(_ field: XCUIElement, app: XCUIApplication) {
        for _ in 0..<3 {
            field.tap()
            field.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.5)).tap()
            if app.keyboards.firstMatch.waitForExistence(timeout: 2) { return }
        }
        XCTFail("Weight field must receive keyboard focus before entering a measurement")
    }

}
