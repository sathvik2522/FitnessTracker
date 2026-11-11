import XCTest

final class WorkoutFlowTests: XCTestCase {
    @MainActor
    func testCustomExerciseCreationContinuesIntoRoutineWithoutLosingName() {
        continueAfterFailure = false
        let app = launch()
        app.buttons["New routine"].tap()
        fill(app, "Routine name", "Picker-created routine")
        app.buttons["Add exercise"].tap()
        app.buttons["New exercise"].tap()
        fill(app, "Exercise name", "Custom band pull")
        app.navigationBars["New exercise"].buttons["Save"].tap()
        XCTAssertTrue(app.navigationBars["Workout routine"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.textFields["Routine name"].value as? String, "Picker-created routine")
        XCTAssertTrue(app.staticTexts["Custom band pull"].exists)
        app.buttons["Save"].tap()
        XCTAssertTrue(app.staticTexts["Picker-created routine"].waitForExistence(timeout: 5))
        app.terminate(); app.launch()
        app.tabBars.buttons["Training"].tap()
        XCTAssertTrue(app.staticTexts["Picker-created routine"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testRoutineActiveRelaunchFinishAndProgression() {
        continueAfterFailure = false
        let app = launch()
        app.buttons["Exercise library & progression"].tap()
        app.buttons["New exercise"].tap()
        fill(app, "Exercise name", "UI Push-up")
        enable(app.switches["Bodyweight exercise"])
        app.buttons["Save"].tap()
        app.navigationBars["Exercises"].buttons.element(boundBy: 0).tap()
        app.buttons["New routine"].tap()
        fill(app, "Routine name", "UI Gym routine")
        app.buttons["Add exercise"].tap()
        app.buttons["UI Push-up"].tap()
        app.buttons["Save"].tap()
        app.buttons["Start routine"].tap()
        XCTAssertTrue(app.buttons["Close & keep active"].waitForExistence(timeout: 5))
        app.buttons["Exercises"].tap()
        XCTAssertTrue(app.navigationBars["Session exercises"].waitForExistence(timeout: 5))
        app.buttons["Save"].tap()
        app.swipeUp()
        fill(app, "Reps", "10")
        fill(app, "Extra weight (kg)", "5")
        enable(app.switches["Set 1 completed"])
        let progress = app.descendants(matching: .any).matching(identifier: "workout.progress").firstMatch
        for _ in 0..<6 where !progress.isHittable { app.swipeDown() }
        XCTAssertTrue(progress.exists)
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Isolated strength logging fixture"
        screenshot.lifetime = .keepAlways
        add(screenshot)
        app.buttons["Close & keep active"].tap()
        app.terminate()
        app.launch()
        app.tabBars.buttons["Training"].tap()
        app.buttons["Resume UI Gym routine"].tap()
        app.swipeUp()
        XCTAssertEqual(app.textFields["Reps"].value as? String, "10")
        XCTAssertEqual(app.textFields["Extra weight (kg)"].value as? String, "5")
        XCTAssertEqual(app.switches["Set 1 completed"].value as? String, "1")
        if !app.buttons["Finish workout"].isHittable { app.swipeUp() }
        app.buttons["Finish workout"].tap()
        XCTAssertTrue(app.alerts["Workout saved"].waitForExistence(timeout: 5))
        app.alerts["Workout saved"].buttons["Done"].tap()
        XCTAssertTrue(app.buttons["Start empty workout"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["Resume UI Gym routine"].exists)
        app.buttons["Exercise library & progression"].tap()
        // The library row includes the new Starter/Custom metadata label.
        let exercise = app.buttons.containing(NSPredicate(format: "label BEGINSWITH %@", "UI Push-up")).firstMatch
        XCTAssertTrue(exercise.waitForExistence(timeout: 5)); exercise.tap()
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "50 kg·reps")).firstMatch.waitForExistence(timeout: 5))
        app.navigationBars.buttons.element(boundBy: 0).tap()
        app.navigationBars["Exercises"].buttons.element(boundBy: 0).tap()
        app.buttons["Start routine"].tap()
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "Last completed")).firstMatch.waitForExistence(timeout: 5))
        for _ in 0..<6 where !app.buttons["Cancel workout"].isHittable { app.swipeUp() }
        app.buttons["Cancel workout"].tap()
        app.sheets.buttons["Cancel workout"].tap()
        let cancelled = app.buttons.containing(NSPredicate(format: "label CONTAINS %@", "Cancelled")).firstMatch
        for _ in 0..<6 where !cancelled.exists { app.swipeUp() }
        XCTAssertTrue(cancelled.waitForExistence(timeout: 5))
    }

    @MainActor
    func testStairClimberLoggingAndEditingPersists() {
        continueAfterFailure = false
        let app = launch()
        app.buttons["Log stair climber"].tap()
        fill(app, "Duration (minutes)", "10")
        fill(app, "Level / resistance", "5")
        if !app.textFields["Reported calories (kcal)"].isHittable { app.swipeUp() }
        fill(app, "Reported calories (kcal)", "100")
        app.buttons["Save"].tap()
        app.swipeUp()
        let row = app.buttons.containing(NSPredicate(format: "label CONTAINS %@", "Machine estimate: 100 kcal")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        row.tap()
        fill(app, "Duration (minutes)", "12")
        app.buttons["Save"].tap()
        app.terminate()
        app.launch()
        app.tabBars.buttons["Training"].tap()
        app.swipeUp()
        XCTAssertTrue(app.buttons.containing(NSPredicate(format: "label CONTAINS %@", "12 min")).firstMatch.waitForExistence(timeout: 5))
        XCTAssertEqual(app.buttons.containing(NSPredicate(format: "label CONTAINS %@", "Machine estimate: 100 kcal")).count, 1)
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Isolated cardio history fixture"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }

    @MainActor func testLargeTextWorkoutEntryRemainsReachable() {
        continueAfterFailure = false
        let app = launch(large: true)
        app.buttons["Start workout"].tap()
        XCTAssertTrue(app.buttons["Close & keep active"].waitForExistence(timeout: 5))
        for _ in 0..<6 where !app.buttons["Add exercise"].isHittable { app.swipeUp() }
        app.buttons["Add exercise"].tap()
        app.buttons["New exercise"].tap()
        fill(app, "Exercise name", "Large text squat")
        app.navigationBars["New exercise"].buttons["Save"].tap()
        fill(app, "Reps", "8")
        fill(app, "Weight (kg)", "25")
        enable(app.switches["Set 1 completed"])
        XCTAssertTrue(app.buttons["Close & keep active"].isHittable)
        app.buttons["Close & keep active"].tap()
        for _ in 0..<6 where !app.buttons["Resume workout"].isHittable { app.swipeDown() }
        XCTAssertTrue(app.buttons["Resume workout"].isHittable)
    }

    @MainActor private func launch(large: Bool = false) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--nutrition-ui-test-store", UUID().uuidString, "-health.readRequestCompleted.v1", "NO"]
        if large { app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"] }
        app.launch()
        XCTAssertTrue(app.tabBars.buttons["Training"].waitForExistence(timeout: 15))
        app.tabBars.buttons["Training"].tap()
        return app
    }
    @MainActor private func enable(_ toggle: XCUIElement) {
        let app = XCUIApplication()
        if app.buttons["Done editing"].exists { app.buttons["Done editing"].tap() }
        // Wait for the native control's accessibility state, rather than assuming
        // a coordinate tap has already changed it during keyboard transitions.
        XCTAssertTrue(toggle.waitForExistence(timeout: 5))
        for _ in 0..<3 {
            if toggle.value as? String == "1" { return }
            toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
            let enabled = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", "1"), object: toggle)
            if XCTWaiter.wait(for: [enabled], timeout: 2) == .completed { return }
        }
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Switch interaction failure"
        screenshot.lifetime = .keepAlways
        add(screenshot)
        print(app.debugDescription)
        XCTAssertEqual(toggle.value as? String, "1")
    }
    @MainActor private func fill(_ app: XCUIApplication, _ title: String, _ value: String) {
        let field = app.textFields[title]
        if app.keyboards.firstMatch.exists && app.buttons["Done editing"].exists {
            app.buttons["Done editing"].tap()
        }
        _ = field.waitForExistence(timeout: 2)
        for _ in 0..<8 {
            if field.exists && field.isHittable { break }
            if app.keyboards.firstMatch.exists && app.buttons["Done editing"].exists {
                app.buttons["Done editing"].tap()
                if field.exists && field.isHittable { break }
            }
            let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.55))
            let down = field.exists && field.frame.midY < 110
            start.press(forDuration: 0.1, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: down ? 0.75 : 0.35)))
        }
        XCTAssertTrue(field.exists && field.isHittable, "Reachable input: \(title)")
        field.tap()
        field.coordinate(withNormalizedOffset: CGVector(dx: 0.99, dy: 0.5)).tap()
        let old = field.value as? String ?? ""
        let placeholder = old == title || old == "Required" || old == "Optional"
        field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: placeholder ? 0 : old.count))
        for character in value { field.typeText(String(character)) }
        XCTAssertEqual(field.value as? String, value)
    }
}
