import XCTest

final class RedesignFlowTests: XCTestCase {
    @MainActor func testQualityGateSyntheticScreens() throws {
        let app = launch()
        app.tabBars.buttons["Food"].tap()
        app.buttons["Add food"].tap()
        app.buttons["Create food"].tap()
        fill(app, "Name", "Sample oats with berries")
        fill(app, "Calories (kcal)", "200")
        fill(app, "Protein (g)", "10")
        fill(app, "Carbohydrates (g)", "30")
        fill(app, "Fat (g)", "5")
        if app.buttons["Done editing"].isHittable { app.buttons["Done editing"].tap() }
        reveal(app.textFields["Name"], app: app, down: true)
        capture(app, "quality-food-edit")
        app.buttons["Save & log"].tap()
        XCTAssertTrue(app.navigationBars["Log portion"].waitForExistence(timeout: 5))
        app.navigationBars["Log portion"].buttons["Save"].tap()
        XCTAssertTrue(app.buttons["Add food"].waitForExistence(timeout: 5))
        capture(app, "quality-food-diary")
        app.buttons["Add food"].tap()
        XCTAssertTrue(app.navigationBars["Add food"].waitForExistence(timeout: 5))
        capture(app, "quality-food-search")
        app.navigationBars["Add food"].buttons["Cancel"].tap()
        app.tabBars.buttons["Today"].tap()
        capture(app, "quality-today")
        app.tabBars.buttons["Training"].tap()
        capture(app, "quality-training")
        app.buttons["Start workout"].tap()
        XCTAssertTrue(app.buttons["Close & keep active"].waitForExistence(timeout: 5))
        reveal(app.buttons["Add exercise"], app: app)
        app.buttons["Add exercise"].tap()
        app.buttons["New exercise"].tap()
        fill(app, "Exercise name", "Sample squat")
        app.navigationBars["New exercise"].buttons["Save"].tap()
        XCTAssertTrue(app.buttons["Close & keep active"].waitForExistence(timeout: 5))
        capture(app, "quality-active-workout")
    }
    @MainActor private func launch(large: Bool = false) -> XCUIApplication {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--nutrition-ui-test-store", UUID().uuidString,
            "-health.readRequestCompleted.v1", "NO", "-health.sleepReadRequestCompleted.v1", "NO"]
        if large { app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"] }
        app.launch()
        XCTAssertTrue(app.tabBars.buttons["Today"].waitForExistence(timeout: 20))
        return app
    }
    @MainActor func testDashboardQuickActionsOpenEditorsAndResumeOneActiveWorkout() throws {
        let app = launch()
        app.buttons["Log food"].tap()
        XCTAssertTrue(app.navigationBars["Add food"].waitForExistence(timeout: 5))
        app.navigationBars["Add food"].buttons["Cancel"].tap()
        XCTAssertTrue(app.tabBars.buttons["Food"].isSelected)
        app.tabBars.buttons["Today"].tap()
        app.buttons["Previous day"].tap()
        let yesterday = try XCTUnwrap(Calendar.current.date(byAdding: .day, value: -1, to: Date.now))
        app.buttons["Quick actions"].tap(); app.buttons["quick.food"].tap()
        let loggingDay = "Logging to " + yesterday.formatted(date: .abbreviated, time: .omitted) + " · Unassigned"
        XCTAssertTrue(app.staticTexts[loggingDay].waitForExistence(timeout: 5))
        app.navigationBars["Add food"].buttons["Cancel"].tap()
        XCTAssertEqual(app.staticTexts["diary.selectedDate"].label, yesterday.formatted(.dateTime.weekday(.wide).month(.wide).day().year()))
        app.tabBars.buttons["Today"].tap()
        app.buttons["Quick actions"].tap(); app.buttons["quick.weight"].tap()
        XCTAssertTrue(app.navigationBars["Manual weight"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.textFields["Body weight (kg)"].exists)
        app.navigationBars["Manual weight"].buttons["Cancel"].tap()
        for (action, title) in [("quick.cardio", "Log cardio"), ("quick.stairs", "Stair climber")] {
            app.tabBars.buttons["Today"].tap()
            app.buttons["Quick actions"].tap(); app.buttons[action].tap()
            XCTAssertTrue(app.navigationBars[title].waitForExistence(timeout: 5))
            app.navigationBars[title].buttons["Cancel"].tap()
        }
        app.tabBars.buttons["Today"].tap()
        app.buttons["Quick actions"].tap(); app.buttons["quick.strength"].tap()
        XCTAssertTrue(app.buttons["Close & keep active"].waitForExistence(timeout: 5))
        app.buttons["Close & keep active"].tap()
        XCTAssertEqual(app.buttons.matching(identifier: "Resume Strength workout").count, 1)
        app.tabBars.buttons["Today"].tap()
        app.buttons["Quick actions"].tap(); app.buttons["quick.strength"].tap()
        XCTAssertTrue(app.buttons["Close & keep active"].waitForExistence(timeout: 5))
        app.buttons["Close & keep active"].tap()
        XCTAssertEqual(app.buttons.matching(identifier: "Resume Strength workout").count, 1)
    }
    @MainActor func testRingsGoalsValidationAppearanceAndRelaunch() throws {
        let app = launch()
        for name in ["Today", "Food", "Training", "Progress", "More"] { XCTAssertTrue(app.tabBars.buttons[name].exists) }
        for identifier in ["ring.strain", "ring.recovery", "ring.balance"] {
            let ring = app.buttons[identifier]
            XCTAssertTrue(ring.exists)
            XCTAssertTrue(ring.label.contains(identifier == "ring.strain" ? "Log activity" : identifier == "ring.recovery" ? "Build baseline" : "Record intake"))
            XCTAssertFalse(ring.label.contains("%"))
        }
        capture(app, "Today dark truthful empty states")
        app.buttons["ring.recovery"].tap()
        XCTAssertTrue(app.staticTexts["Build your baseline"].waitForExistence(timeout: 5))
        app.navigationBars["Recovery"].buttons.element(boundBy: 0).tap()
        app.tabBars.buttons["More"].tap()
        app.buttons["Nutrition & activity goals"].tap()
        fill(app, "Calorie goal (kcal)", "0")
        app.buttons["Save goals"].tap()
        XCTAssertTrue(app.alerts["Unable to save"].waitForExistence(timeout: 5)); app.alerts.buttons["OK"].tap()
        XCTAssertEqual(app.textFields["Calorie goal (kcal)"].value as? String, "0")
        fill(app, "Calorie goal (kcal)", "2000")
        app.buttons["Save goals"].tap()
        XCTAssertTrue(app.navigationBars["More"].waitForExistence(timeout: 5))
        app.buttons["settings.appearance"].tap(); app.buttons["Light"].tap()
        capture(app, "More light appearance")
        app.tabBars.buttons["Today"].tap()
        capture(app, "Today light appearance")
        app.terminate(); app.launch()
        app.tabBars.buttons["More"].tap(); app.buttons["Nutrition & activity goals"].tap()
        XCTAssertEqual(app.textFields["Calorie goal (kcal)"].value as? String, "2000")
        app.buttons["Cancel"].tap()
        app.buttons["settings.appearance"].tap(); app.buttons["System"].tap()
        app.tabBars.buttons["Food"].tap()
        XCTAssertTrue(app.staticTexts["Goal 2,000 kcal"].exists)
        try app.performAccessibilityAudit(for: .sufficientElementDescription)
        capture(app, "Food overview system appearance")
    }
    @MainActor func testHistoricalDraftSurvivesActivationErrorsCancelAndMealCopy() throws {
        let app = launch()
        app.tabBars.buttons["Food"].tap(); app.buttons["Previous diary day"].tap()
        let day = app.staticTexts["diary.selectedDate"].label
        app.buttons["Add food"].tap(); app.buttons["Create food"].tap()
        fill(app, "Name", "Draft safety food")
        fill(app, "Calories (kcal)", "200")
        fill(app, "Protein (g)", "0")
        fill(app, "Carbohydrates (g)", "0")
        fill(app, "Fat (g)", "0")
        XCUIDevice.shared.press(.home); app.activate()
        reveal(app.textFields["Name"], app: app, down: true)
        XCTAssertEqual(app.textFields["Name"].value as? String, "Draft safety food")
        // Native modal owns the draft: underlying tabs cannot interrupt it.
        XCTAssertFalse(app.tabBars.buttons["Training"].isHittable)
        app.buttons["Save & log"].tap()
        XCTAssertTrue(app.navigationBars["Log portion"].waitForExistence(timeout: 5))
        fill(app, "Quantity", "0")
        app.buttons["Save"].tap()
        XCTAssertTrue(app.alerts["Unable to save"].waitForExistence(timeout: 5)); app.alerts.buttons["OK"].tap()
        XCTAssertEqual(app.textFields["Quantity"].value as? String, "0")
        fill(app, "Quantity", "50")
        // Focusing Quantity scrolls this earlier row above the navigation bar.
        // XCUITest can report it hittable there without actually opening its menu.
        let meal = app.buttons["diary.meal"]
        for _ in 0..<8 {
            if meal.exists && meal.isHittable && meal.frame.minY >= 110 { break }
            app.swipeDown()
        }
        XCTAssertTrue(meal.isHittable && meal.frame.minY >= 110)
        meal.tap()
        XCTAssertTrue(app.buttons["Breakfast"].waitForExistence(timeout: 5))
        app.buttons["Breakfast"].tap()
        app.navigationBars["Log portion"].buttons["Cancel"].tap()
        XCTAssertTrue(app.alerts["Discard unsaved changes?"].waitForExistence(timeout: 5))
        app.alerts.buttons["Keep editing"].tap()
        XCTAssertEqual(app.textFields["Quantity"].value as? String, "50")
        let primary = app.buttons["Add to Diary"]
        XCTAssertTrue(primary.waitForExistence(timeout: 5) && primary.isHittable)
        XCTAssertGreaterThanOrEqual(primary.frame.height, 44)
        primary.tap()
        XCTAssertEqual(app.staticTexts["diary.selectedDate"].label, day)
        let row = app.buttons.containing(NSPredicate(format: "label CONTAINS %@", "Draft safety food")).firstMatch
        reveal(row, app: app); row.press(forDuration: 1)
        app.buttons["Move to meal"].tap(); app.buttons["Dinner"].tap()
        XCTAssertEqual(app.staticTexts["diary.selectedDate"].label, day)
        reveal(row, app: app)
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "Dinner · 50")).firstMatch.exists)
        reveal(row, app: app); row.press(forDuration: 1); app.buttons["Copy portion"].tap()
        XCTAssertTrue(app.navigationBars["Log portion"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.textFields["Quantity"].value as? String, "50")
        app.buttons["Save"].tap()
        let total = app.descendants(matching: .any).matching(identifier: "diary.totals").firstMatch
        reveal(total, app: app, down: true)
        XCTAssertTrue(total.label.contains("200 kcal"))
        XCTAssertEqual(app.staticTexts["diary.selectedDate"].label, day)
        capture(app, "Historical diary meal move and snapshot copy")
        app.terminate(); app.launch(); app.tabBars.buttons["Food"].tap(); app.buttons["Previous diary day"].tap()
        XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "diary.totals").firstMatch.label.contains("200 kcal"))
    }
    @MainActor func testDashboardHistoricalActionsAndBottomContent() throws {
        let app = launch()
        app.buttons["Previous day"].tap()
        XCTAssertTrue(app.buttons["Log food"].isEnabled)
        XCTAssertFalse(app.buttons["Start workout"].isEnabled)
        let bottom = app.descendants(matching: .any).matching(identifier: "dashboard.context").firstMatch
        reveal(bottom, app: app)
        app.swipeUp()
        XCTAssertTrue(bottom.isHittable)
        XCTAssertLessThanOrEqual(bottom.frame.maxY, app.tabBars.firstMatch.frame.minY + 2)
        XCTAssertFalse(app.staticTexts["No goal configured"].exists)
    }
    @MainActor func testLargeTextRingsAndBottomNavigationRemainReachable() throws {
        let app = launch(large: true)
        for identifier in ["ring.strain", "ring.recovery", "ring.balance"] {
            let ring = app.buttons[identifier]; reveal(ring, app: app)
            XCTAssertTrue(ring.isHittable)
            XCTAssertTrue(ring.label.contains(identifier == "ring.strain" ? "Log activity" : identifier == "ring.recovery" ? "Build baseline" : "Record intake"))
        }
        capture(app, "Today accessibility XXXL rings")
        app.tabBars.buttons["Food"].tap()
        let add = app.buttons["Add food"]
        XCTAssertTrue(add.isHittable); add.tap()
        XCTAssertTrue(app.searchFields.firstMatch.waitForExistence(timeout: 5))
        capture(app, "Search accessibility XXXL")
        app.navigationBars["Add food"].buttons["Cancel"].tap()
        for tab in ["Training", "Progress", "More", "Today"] {
            XCTAssertTrue(app.tabBars.buttons[tab].isHittable); app.tabBars.buttons[tab].tap()
        }
        try app.performAccessibilityAudit(for: .sufficientElementDescription)
    }
    @MainActor private func reveal(_ element: XCUIElement, app: XCUIApplication, down: Bool = false) {
        for _ in 0..<10 {
            if element.exists && element.isHittable { return }
            let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: down ? 0.35 : 0.7))
            let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: down ? 0.7 : 0.35))
            start.press(forDuration: 0.1, thenDragTo: end)
        }
        XCTAssertTrue(element.exists && element.isHittable)
    }
    @MainActor private func fill(_ app: XCUIApplication, _ title: String, _ text: String) {
        if app.buttons["Done editing"].isHittable { app.buttons["Done editing"].tap() }
        let field = app.textFields[title]; reveal(field, app: app)
        for _ in 0..<3 {
            field.tap(); field.coordinate(withNormalizedOffset: CGVector(dx: 0.99, dy: 0.5)).tap()
            if app.keyboards.firstMatch.waitForExistence(timeout: 2) { break }
        }
        XCTAssertTrue(app.keyboards.firstMatch.exists)
        let old = field.value as? String ?? ""
        let count = ["Required", "Optional", title].contains(old) ? 0 : old.count
        if count > 0 { field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: count)) }
        for value in text { field.typeText(String(value)) }
        XCTAssertEqual(field.value as? String, text)
        if app.buttons["Done editing"].isHittable { app.buttons["Done editing"].tap() }
    }
    @MainActor private func capture(_ app: XCUIApplication, _ name: String) {
        let image = XCTAttachment(screenshot: app.screenshot()); image.name = name; image.lifetime = .keepAlways; add(image)
    }
}
