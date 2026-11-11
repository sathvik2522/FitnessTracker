import XCTest
#if SWIFT_PACKAGE
@testable import PersonalFitnessCore
#else
@testable import PersonalFitness
#endif

final class FoodScalingTests: XCTestCase {
    private var food: FoodDefinition {
        FoodDefinition(name: "Test food", preparation: .raw,
            nutrients: FoodNutrients(calories: 200, protein: 10, carbohydrates: 30, fat: 5),
            referenceQuantity: 100, referenceUnit: .grams, equivalents: [.pieces: 2, .servings: 1])
    }

    func testScalingAndExplicitPieceEquivalent() throws {
        XCTAssertEqual(try food.scaled(quantity: 50, unit: .grams).calories, 100)
        XCTAssertEqual(try food.scaled(quantity: 1, unit: .pieces).protein, 5)
        XCTAssertEqual(try food.scaled(quantity: 2, unit: .servings).carbohydrates, 60)
        XCTAssertEqual(try food.scaled(quantity: 50, unit: .grams).fat, 2.5)
    }

    func testNoAssumedDensityOrServingConversion() throws {
        XCTAssertThrowsError(try food.scaled(quantity: 100, unit: .milliliters))
        var explicit = food
        explicit.equivalents[.milliliters] = 125
        XCTAssertEqual(try explicit.scaled(quantity: 125, unit: .milliliters).calories, 200)
        explicit.equivalents = [:]
        XCTAssertThrowsError(try explicit.scaled(quantity: 1, unit: .servings))
    }

    func testInvalidQuantitiesAndNutrientsAreRejected() {
        for invalid in [0.0, -1, Double.nan, .infinity] {
            XCTAssertThrowsError(try food.scaled(quantity: invalid, unit: .grams))
            var bad = food
            bad.referenceQuantity = invalid
            XCTAssertThrowsError(try bad.validated())
            XCTAssertThrowsError(try RecipeCalculation.perServing([RecipeIngredient(food: food, quantity: 100, unit: .grams)], servings: invalid))
        }
        for invalid in [-1.0, Double.nan, .infinity] {
            var bad = food
            bad.nutrients.protein = invalid
            XCTAssertThrowsError(try bad.validated())
        }
        var bad = food
        bad.equivalents[.milliliters] = -10
        XCTAssertThrowsError(try bad.validated())
        bad = food
        bad.name = "  "
        XCTAssertThrowsError(try bad.validated())
    }

    func testRecipeTotalsAndServingFractions() throws {
        let ingredients = [RecipeIngredient(food: food, quantity: 100, unit: .grams),
                           RecipeIngredient(food: food, quantity: 50, unit: .grams)]
        XCTAssertEqual(try RecipeCalculation.total(ingredients).calories, 300)
        let serving = try RecipeCalculation.perServing(ingredients, servings: 2)
        XCTAssertEqual(serving.calories, 150)
        XCTAssertEqual(serving.protein, 7.5)
        XCTAssertEqual(serving.carbohydrates, 22.5)
        XCTAssertEqual(serving.fat, 3.75)
        XCTAssertThrowsError(try RecipeCalculation.total([]))
    }

    func testSnapshotEncodingAndOverflow() throws {
        let decoded = try JSONDecoder().decode(FoodDefinition.self, from: JSONEncoder().encode(food))
        XCTAssertEqual(decoded, food)
        XCTAssertEqual(decoded.preparation, .raw)
        var huge = food
        huge.nutrients.calories = .greatestFiniteMagnitude
        XCTAssertThrowsError(try huge.scaled(quantity: 200, unit: .grams))
    }

    func testLocalizedStrictNumericInput() throws {
        XCTAssertEqual(try NutritionNumber.parse("12.5", locale: Locale(identifier: "en_US")), 12.5)
        XCTAssertEqual(try NutritionNumber.parse("12,5", locale: Locale(identifier: "de_DE")), 12.5)
        for value in ["", "nan", "infinity", "abc", "12abc"] {
            XCTAssertThrowsError(try NutritionNumber.parse(value))
        }
    }

    func testHistoricalDatesRetainLocalDayAcrossDST() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        let now = calendar.date(from: DateComponents(year: 2026, month: 11, day: 3, hour: 15))!
        for (month, day) in [(3, 8), (11, 1)] {
            let selected = calendar.date(from: DateComponents(year: 2026, month: month, day: day))!
            let timestamp = try DiaryDate.timestamp(for: selected, now: now, calendar: calendar)
            XCTAssertTrue(calendar.isDate(selected, inSameDayAs: timestamp))
            XCTAssertEqual(calendar.component(.hour, from: timestamp), 12)
        }
        XCTAssertEqual(try DiaryDate.timestamp(for: now, now: now, calendar: calendar), now)
        XCTAssertThrowsError(try DiaryDate.validate(now.addingTimeInterval(1), now: now))
    }
}
