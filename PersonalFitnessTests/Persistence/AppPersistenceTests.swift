import XCTest
import SwiftData
@testable import PersonalFitness

final class AppPersistenceTests: XCTestCase {
    @MainActor
    func testFoodEntryRoundTripInMemory() throws {
        let container = try AppPersistence.makeContainer(inMemory: true)
        let context = ModelContext(container)
        let date = Date(timeIntervalSince1970: 1_000)
        let entry = FoodEntry(name: "Test portion", calories: 300,
                              proteinGrams: 20, carbohydrateGrams: 30,
                              fatGrams: 11, loggedAt: date)
        context.insert(entry)
        try context.save()
        let reloaded = try ModelContext(container).fetch(FetchDescriptor<FoodEntry>())
        XCTAssertEqual(reloaded.count, 1)
        XCTAssertEqual(reloaded.first?.id, entry.id)
        XCTAssertEqual(reloaded.first?.calories, 300)
        XCTAssertEqual(reloaded.first?.loggedAt, date)
        XCTAssertEqual(reloaded.first?.proteinGrams, 20)
    }
}
