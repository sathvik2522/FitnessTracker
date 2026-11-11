import XCTest

final class NutritionFlowTests: XCTestCase {
    @MainActor
    func testCreateAndLogFromDiary() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--nutrition-ui-test-store", UUID().uuidString, "-health.readRequestCompleted.v1", "NO"]
        app.launch()
        XCTAssertTrue(app.tabBars.buttons["Food"].waitForExistence(timeout: 15))
        app.tabBars.buttons["Food"].tap()
        app.buttons["Previous diary day"].tap()
        let day = app.staticTexts["diary.selectedDate"].label
        app.buttons["Add food"].tap()
        // The redesigned search scopes and empty-state explanation scroll on
        // compact screens. Verify the same creation action remains reachable.
        let create = app.buttons["Create food"]
        for _ in 0..<6 {
            if create.exists && create.isHittable { break }
            app.swipeUp()
        }
        XCTAssertTrue(create.exists && create.isHittable)
        create.tap()
        XCTAssertTrue(app.buttons["Save & log"].waitForExistence(timeout: 5), "Creation must offer an explicit continuation into portion logging")
        fill(app, "Name", "New flow oats")
        app.navigationBars["New food"].buttons["Cancel"].tap()
        XCTAssertTrue(app.buttons["Discard changes"].waitForExistence(timeout: 3))
        app.buttons["Keep editing"].tap()
        XCTAssertEqual(app.textFields["Name"].value as? String, "New flow oats")
        fill(app, "Calories (kcal)", "200")
        fill(app, "Protein (g)", "10")
        fill(app, "Carbohydrates (g)", "30")
        fill(app, "Fat (g)", "5")
        app.buttons["Save & log"].tap()
        XCTAssertTrue(app.navigationBars["Log portion"].waitForExistence(timeout: 5))
        fill(app, "Quantity", "50")
        if app.buttons["Done editing"].isHittable { app.buttons["Done editing"].tap() }
        let meal = app.buttons["diary.meal"]
        for _ in 0..<8 {
            if meal.exists && meal.isHittable && meal.frame.minY >= 110 { break }
            app.swipeDown()
        }
        XCTAssertTrue(meal.exists && meal.isHittable)
        meal.tap()
        app.buttons["Breakfast"].tap()
        app.buttons["Save"].tap()
        assertTotal(app, "100 kcal")
        XCTAssertEqual(app.staticTexts["diary.selectedDate"].label, day)
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "Breakfast ·")).firstMatch.exists)
        app.terminate(); app.launch()
        app.tabBars.buttons["Food"].tap()
        app.buttons["Previous diary day"].tap()
        assertTotal(app, "100 kcal")
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "Breakfast ·")).firstMatch.exists)
        app.buttons["Food library"].tap()
        let search = app.searchFields.firstMatch
        search.tap(); search.typeText("New flow oats")
        row(app, "New flow oats").tap()
        fill(app, "Name", "Renamed oats")
        app.navigationBars["Edit food"].buttons["Save"].tap()
        XCTAssertTrue(row(app, "Renamed oats").waitForExistence(timeout: 5), "A stale filter must not hide the saved rename")
        backToDiary(app)
        assertTotal(app, "100 kcal")
        XCTAssertTrue(row(app, "New flow oats").exists, "The diary retains its original name/nutrition snapshot")
        app.buttons["Add food"].tap()
        let repeatPortion = app.buttons["Repeat portion"].firstMatch
        XCTAssertTrue(repeatPortion.waitForExistence(timeout: 5))
        repeatPortion.tap()
        assertTotal(app, "200 kcal")
        app.terminate(); app.launch(); app.tabBars.buttons["Food"].tap(); app.buttons["Previous diary day"].tap()
        assertTotal(app, "200 kcal")
        app.buttons["Add food"].tap()
        let favorite = app.buttons["Add Renamed oats to favorites"]
        for _ in 0..<8 where !favorite.isHittable { app.swipeUp() }
        XCTAssertTrue(favorite.isHittable); favorite.tap()
        for _ in 0..<8 where !app.buttons["Favorites"].isHittable { app.swipeDown() }
        app.buttons["Favorites"].tap()
        XCTAssertTrue(row(app, "Renamed oats").waitForExistence(timeout: 5))
        app.navigationBars["Add food"].buttons["Cancel"].tap()
        assertTotal(app, "200 kcal")
        let breakfast = app.buttons["diary.meal.Breakfast"]
        // Breakfast starts just below the viewport. Full-screen swipes can
        // overshoot it and evict the lazy List row before the next lookup.
        let list = app.collectionViews.firstMatch
        XCTAssertTrue(list.waitForExistence(timeout: 5))
        for _ in 0..<8 where !breakfast.isHittable {
            list.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.70))
                .press(forDuration: 0.1, thenDragTo: list.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.48)))
        }
        XCTAssertTrue(breakfast.isHittable)
        breakfast.tap(); XCTAssertEqual(breakfast.value as? String, "Collapsed")
        breakfast.tap(); XCTAssertEqual(breakfast.value as? String, "Expanded")
    }

    @MainActor
    func testAccessibilitySizeFoodEditor() {
        let app = XCUIApplication()
        app.launchArguments = ["--nutrition-ui-test-store", UUID().uuidString,
                               "-health.readRequestCompleted.v1", "NO",
                               "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        app.launch()
        XCTAssertTrue(app.tabBars.buttons["Food"].waitForExistence(timeout: 15))
        app.tabBars.buttons["Food"].tap()
        app.buttons["Food library"].tap()
        app.buttons["Create library item"].tap()
        app.buttons["New food"].tap()
        fill(app, "Name", "Long whole grain oats with berries and toasted almonds")
        if app.buttons["Done editing"].isHittable { app.buttons["Done editing"].tap() }
        // Form rows are lazy; on a small iPhone at XXXL they start offscreen.
        func reveal(_ element: XCUIElement, name: String) {
            for _ in 0..<8 {
                if element.exists && element.isHittable { break }
                app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.70))
                    .press(forDuration: 0.1, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.40)))
            }
            XCTAssertTrue(element.exists && element.isHittable, "Reachable control: \(name)")
        }
        reveal(app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", "Not specified")).firstMatch,
               name: "Not specified preparation")
        let preparationImage = XCTAttachment(screenshot: app.screenshot())
        preparationImage.name = "Inline preparation at accessibility XXXL"; preparationImage.lifetime = .keepAlways; add(preparationImage)
        for title in ["Reference quantity", "Calories (kcal)"] {
            reveal(app.textFields[title], name: title)
        }
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Isolated editor accessibility XXXL"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }

    @MainActor
    func testFoodHistoricalEditingRecipeQuickAddAndRelaunch() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--nutrition-ui-test-store", UUID().uuidString, "-health.readRequestCompleted.v1", "NO"]
        app.launch()
        XCTAssertTrue(app.tabBars.buttons["Food"].waitForExistence(timeout: 15))
        app.tabBars.buttons["Food"].tap()
        app.buttons["Food library"].tap()
        app.buttons["Create library item"].tap()
        app.buttons["New food"].tap()
        let editorImage = XCTAttachment(screenshot: app.screenshot())
        editorImage.name = "Isolated saved-food editor"
        editorImage.lifetime = .keepAlways
        add(editorImage)
        app.buttons["Save"].tap()
        XCTAssertTrue(app.alerts["Unable to save"].waitForExistence(timeout: 5))
        app.alerts.buttons["OK"].tap()
        fill(app, "Name", "UI Test Oats")
        fill(app, "Calories (kcal)", "200")
        fill(app, "Protein (g)", "10")
        fill(app, "Carbohydrates (g)", "30")
        fill(app, "Fat (g)", "5")
        app.buttons["Save"].tap()
        XCTAssertTrue(row(app, "UI Test Oats").waitForExistence(timeout: 5))
        backToDiary(app)
        app.buttons["Previous diary day"].tap()
        let historicalDate = app.staticTexts["diary.selectedDate"].label
        app.buttons["Add food"].tap()
        row(app, "UI Test Oats").tap()
        fill(app, "Quantity", "50")
        app.buttons["Save"].tap()
        assertTotal(app, "100 kcal")

        // Editing the library must not rewrite the diary snapshot.
        app.buttons["Food library"].tap()
        row(app, "UI Test Oats").tap()
        fill(app, "Calories (kcal)", "400")
        app.buttons["Save"].tap()
        backToDiary(app)
        assertTotal(app, "100 kcal")
        row(app, "UI Test Oats").tap()
        fill(app, "Quantity", "25")
        app.buttons["Save"].tap()
        assertTotal(app, "50 kcal")
        XCTAssertEqual(app.staticTexts["diary.selectedDate"].label, historicalDate)

        // Choosing the updated version of the SAME food changes its snapshot,
        // even when source ID, date and quantity match the old entry.
        row(app, "UI Test Oats").tap()
        app.buttons["Change food or meal"].tap()
        row(app, "UI Test Oats").tap()
        fill(app, "Quantity", "25")
        app.navigationBars["Log portion"].buttons["Cancel"].tap()
        XCTAssertTrue(app.alerts["Discard unsaved changes?"].waitForExistence(timeout: 5))
        app.alerts.buttons["Discard changes"].tap()
        assertTotal(app, "50 kcal")

        // Recipe nutrition uses the edited library definition, then snapshots it.
        app.buttons["Food library"].tap()
        app.buttons["Create library item"].tap()
        app.buttons["New recipe"].tap()
        fill(app, "Name", "UI Test Recipe")
        fill(app, "Total servings produced", "2")
        app.buttons["Add ingredient"].tap()
        row(app, "UI Test Oats").tap()
        app.navigationBars["Ingredient quantity"].buttons["Save"].tap()
        XCTAssertTrue(app.navigationBars["New recipe"].waitForExistence(timeout: 5))
        app.navigationBars["New recipe"].buttons["Save"].tap()
        XCTAssertTrue(row(app, "UI Test Recipe").waitForExistence(timeout: 5))
        backToDiary(app)
        app.buttons["Add food"].tap()
        row(app, "UI Test Recipe").tap()
        app.buttons["Save"].tap()
        assertTotal(app, "250 kcal")
        app.buttons["Add food"].tap()
        for _ in 0..<8 where !row(app, "Quick add UI Test Recipe").isHittable { app.swipeUp() }
        row(app, "Quick add UI Test Recipe").tap()
        assertTotal(app, "450 kcal")
        app.tabBars.buttons["Today"].tap()
        app.buttons["Previous day"].tap()
        assertLabel(app, "dashboard.calories", "450 kcal")
        assertLabel(app, "dashboard.protein", "12.5 g")
        app.tabBars.buttons["Food"].tap()
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Isolated nutrition UI test diary"
        screenshot.lifetime = .keepAlways
        add(screenshot)

        app.terminate()
        app.launch()
        app.tabBars.buttons["Food"].tap()
        app.buttons["Previous diary day"].tap()
        assertTotal(app, "450 kcal")
        XCTAssertEqual(app.staticTexts["diary.selectedDate"].label, historicalDate)
        row(app, "UI Test Recipe").tap()
        let deleteEntry = app.buttons["Delete diary entry"]
        for _ in 0..<8 {
            if deleteEntry.exists && deleteEntry.isHittable { break }
            app.swipeUp()
        }
        XCTAssertTrue(deleteEntry.exists && deleteEntry.isHittable)
        deleteEntry.tap()
        let confirmDelete = app.buttons["Delete entry"]
        XCTAssertTrue(confirmDelete.waitForExistence(timeout: 5))
        confirmDelete.tap()
        assertTotal(app, "250 kcal")
        app.buttons["Add food"].tap()
        for _ in 0..<8 where !row(app, "Quick add UI Test Oats").isHittable { app.swipeUp() }
        row(app, "Quick add UI Test Oats").tap()
        assertTotal(app, "650 kcal")
    }

    @MainActor
    private func row(_ app: XCUIApplication, _ name: String) -> XCUIElement {
        let matches = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", name))
        // Presented sheets can leave matching background rows in the AX tree.
        return matches.allElementsBoundByIndex.first(where: { $0.isHittable }) ?? matches.firstMatch
    }

    @MainActor
    private func fill(_ app: XCUIApplication, _ title: String, _ value: String) {
        let field = app.textFields[title]
        if app.keyboards.firstMatch.exists && app.buttons["Done editing"].exists {
            app.buttons["Done editing"].tap()
        }
        _ = field.waitForExistence(timeout: 2)
        func fullyPresented() -> Bool {
            guard field.exists && field.isHittable else { return false }
            // AX can report a lazy Form field behind a safe-area action strip as
            // hittable. Put its entire frame above the keyboard/footer region.
            return field.frame.minY >= 110 && field.frame.maxY < app.frame.height * 0.60
        }
        for _ in 0..<12 {
            if fullyPresented() { break }
            // On a short screen, an app-wide swipe can land on the keyboard
            // instead of the form. Dismiss it before revealing another input.
            if app.keyboards.firstMatch.exists && app.buttons["Done editing"].exists {
                app.buttons["Done editing"].tap()
                if fullyPresented() { break }
            }
            // Short drags avoid skipping a row after the keyboard disappears.
            let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.55))
            let movingDown = field.exists && field.frame.midY < 110
            let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: movingDown ? 0.75 : 0.35))
            start.press(forDuration: 0.1, thenDragTo: end)
        }
        if !fullyPresented() {
            let attachment = XCTAttachment(screenshot: app.screenshot())
            attachment.name = "Unreachable input \(title)"; attachment.lifetime = .keepAlways; add(attachment)
        }
        XCTAssertTrue(fullyPresented(), "Fully visible input: \(title)")
        for _ in 0..<3 {
            field.tap()
            // Place the caret after an existing right-aligned value.
            field.coordinate(withNormalizedOffset: CGVector(dx: 0.99, dy: 0.5)).tap()
            if app.keyboards.firstMatch.waitForExistence(timeout: 2) { break }
        }
        XCTAssertTrue(app.keyboards.firstMatch.exists, "Keyboard focus before typing: \(title)")
        let old = field.value as? String ?? ""
        let count = old == title || old == "Required" ? 0 : old.count
        field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: count))
        for character in value { field.typeText(String(character)) }
        XCTAssertEqual(field.value as? String, value)
    }

    @MainActor
    private func backToDiary(_ app: XCUIApplication) {
        let navigation = app.navigationBars["Food library"]
        // Native search mode puts Close ahead of the back button on iOS 27.
        // End search before navigating; do not mistake Close for Back.
        if navigation.buttons["Close"].exists { navigation.buttons["Close"].tap() }
        navigation.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(app.buttons["Add food"].waitForExistence(timeout: 5))
    }

    @MainActor
    private func assertLabel(_ app: XCUIApplication, _ identifier: String, _ text: String) {
        let element = app.descendants(matching: .any)[identifier].firstMatch
        XCTAssertTrue(element.waitForExistence(timeout: 5))
        expectation(for: NSPredicate(format: "label CONTAINS %@", text), evaluatedWith: element)
        waitForExpectations(timeout: 5)
    }

    @MainActor
    private func assertTotal(_ app: XCUIApplication, _ calories: String) {
        let total = app.descendants(matching: .any)["diary.totals"].firstMatch
        for _ in 0..<10 {
            if total.exists && total.isHittable { break }
            app.swipeDown()
        }
        XCTAssertTrue(total.waitForExistence(timeout: 5))
        let predicate = NSPredicate(format: "label CONTAINS %@", calories)
        expectation(for: predicate, evaluatedWith: total)
        waitForExpectations(timeout: 5)
    }
}
