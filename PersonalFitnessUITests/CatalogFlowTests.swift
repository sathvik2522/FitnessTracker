import XCTest

final class CatalogFlowTests: XCTestCase {
    @MainActor
    func testRealBundledOfflineCatalogCanLogFoodAndChooseExerciseAfterRelaunch() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--nutrition-ui-test-store", UUID().uuidString, "--with-offline-catalog", "-health.readRequestCompleted.v1", "NO"]
        app.launch()
        XCTAssertTrue(app.tabBars.buttons["Food"].waitForExistence(timeout: 40), "Background catalog import must finish")
        app.tabBars.buttons["Food"].tap(); app.buttons["Add food"].tap()
        let search = app.searchFields.firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 5)); search.tap(); search.typeText("moong raw")
        let food = app.buttons.containing(NSPredicate(format: "label CONTAINS %@", "Mung beans, mature seeds, raw")).firstMatch
        XCTAssertTrue(food.waitForExistence(timeout: 5)); food.tap()
        XCTAssertTrue(app.navigationBars["Log portion"].waitForExistence(timeout: 5))
        app.buttons["Save"].tap()
        XCTAssertTrue(app.buttons.containing(NSPredicate(format: "label CONTAINS %@", "Mung beans, mature seeds, raw")).firstMatch.waitForExistence(timeout: 5))
        app.terminate(); app.launch()
        XCTAssertTrue(app.tabBars.buttons["Food"].waitForExistence(timeout: 40))
        app.tabBars.buttons["Food"].tap()
        XCTAssertTrue(app.buttons.containing(NSPredicate(format: "label CONTAINS %@", "Mung beans, mature seeds, raw")).firstMatch.waitForExistence(timeout: 5))
        app.tabBars.buttons["Training"].tap(); app.buttons["New routine"].tap()
        app.buttons["Add exercise"].tap()
        XCTAssertTrue(search.waitForExistence(timeout: 5)); search.tap(); search.typeText("Bulgarian")
        let exercise = app.buttons.containing(NSPredicate(format: "label CONTAINS %@", "Split Squat with Dumbbells")).firstMatch
        XCTAssertTrue(exercise.waitForExistence(timeout: 5)); exercise.tap()
        XCTAssertTrue(app.staticTexts["Split Squat with Dumbbells"].waitForExistence(timeout: 5))
    }
}
