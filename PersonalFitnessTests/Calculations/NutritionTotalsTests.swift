import XCTest
#if SWIFT_PACKAGE
@testable import PersonalFitnessCore
#else
@testable import PersonalFitness
#endif

final class NutritionTotalsTests: XCTestCase {
    func testEmptyDiaryHasZeroLoggedNutrients() {
        let totals = NutritionTotals(portions: [])
        XCTAssertEqual(totals.entryCount, 0)
        XCTAssertEqual(totals.calories, 0)
        XCTAssertEqual(totals.protein, 0)
        XCTAssertEqual(totals.carbohydrates, 0)
        XCTAssertEqual(totals.fat, 0)
    }

    func testWholePortionsAreSummedWithoutRounding() {
        let totals = NutritionTotals(portions: [
            NutritionPortion(calories: 150.5, protein: 10.25, carbohydrates: 20, fat: 3),
            NutritionPortion(calories: 50, protein: 2, carbohydrates: 5, fat: 1)
        ])
        XCTAssertEqual(totals.entryCount, 2)
        XCTAssertEqual(totals.calories, 200.5)
        XCTAssertEqual(totals.protein, 12.25)
        XCTAssertEqual(totals.carbohydrates, 25)
        XCTAssertEqual(totals.fat, 4)
    }

    func testCorruptNutrientDoesNotInventATotalOrHideOtherNutrients() {
        for invalid in [-1.0, Double.nan, Double.infinity] {
            let totals = NutritionTotals(portions: [
                NutritionPortion(calories: invalid, protein: 10, carbohydrates: 20, fat: 3)
            ])
            XCTAssertNil(totals.calories)
            XCTAssertEqual(totals.protein, 10)
        }
    }

    func testOverflowIsUnavailable() {
        let portion = NutritionPortion(calories: .greatestFiniteMagnitude, protein: 0, carbohydrates: 0, fat: 0)
        XCTAssertNil(NutritionTotals(portions: [portion, portion]).calories)
    }
}
