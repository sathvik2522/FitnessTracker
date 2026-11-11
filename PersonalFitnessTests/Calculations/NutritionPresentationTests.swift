import XCTest
#if SWIFT_PACKAGE
@testable import PersonalFitnessCore
#else
@testable import PersonalFitness
#endif

final class NutritionPresentationTests: XCTestCase {
    func testGoalProgressMissingZeroNegativeAndNonfiniteAreNotMeasuredZero() {
        for goal in [0, -1, Double.nan, .infinity] { XCTAssertNil(GoalProgress(amount: 100, goal: goal).fraction) }
        for amount in [Double.nan, .infinity, -1] { XCTAssertNil(GoalProgress(amount: amount, goal: 100).fraction) }
        XCTAssertNil(GoalProgress(amount: nil, goal: 100).remaining)
        XCTAssertNil(GoalProgress(amount: 100, goal: nil).fraction)
        XCTAssertEqual(GoalProgress(amount: 0, goal: 100).fraction, 0)
    }
    func testOverGoalClampsDrawingButKeepsSignedRemainingAndPrecision() {
        let progress = GoalProgress(amount: 125.25, goal: 100)
        XCTAssertEqual(progress.fraction, 1); XCTAssertEqual(progress.remaining, -25.25)
        XCTAssertEqual(GoalProgress(amount: .greatestFiniteMagnitude, goal: .leastNonzeroMagnitude).fraction, 1)
        XCTAssertEqual(GoalProgress(amount: 1, goal: 3).fraction!, 1 / 3, accuracy: 1e-12)
    }
    func testExplicitGoalsValidateWithoutInferredTargets() throws {
        XCTAssertEqual(try NutritionGoals().validated(), NutritionGoals())
        for goal in [0, -1, Double.nan, .infinity] { XCTAssertThrowsError(try NutritionGoals(calories: goal).validated()) }
        let goals = NutritionGoals(calories: 2000, protein: 120, carbohydrates: 250, fat: 65, steps: 9000)
        XCTAssertEqual(try JSONDecoder().decode(NutritionGoals.self, from: JSONEncoder().encode(goals)), goals)
    }
    func testUnscoredStrainAndRecoveryOfferSetupWithoutInventedNumbers() {
        for kind in [DashboardRingKind.strain, .recovery] {
            let state = DashboardRingState.make(kind, balance: -420, partial: true)
            XCTAssertEqual(state.value, kind == .strain ? "Start" : "Build"); XCTAssertEqual(state.unit, "")
            XCTAssertFalse(state.value.contains("%"))
        }
        XCTAssertEqual(DashboardRingState.make(.recovery, balance: nil, partial: false).status, "Build baseline")
    }
    func testBalanceRingSignsUnitsMissingAndPartialDay() {
        XCTAssertEqual(DashboardRingState.make(.balance, balance: -420, partial: true).value, "-420")
        XCTAssertEqual(DashboardRingState.make(.balance, balance: 420, partial: false).value, "+420")
        XCTAssertEqual(DashboardRingState.make(.balance, balance: 0, partial: false).value, "0")
        XCTAssertEqual(DashboardRingState.make(.balance, balance: -0.4, partial: false).value, "0")
        XCTAssertEqual(DashboardRingState.make(.balance, balance: -1, partial: true).status, "Provisional")
        for value in [Double.nan, .infinity] { XCTAssertEqual(DashboardRingState.make(.balance, balance: value, partial: false).value, "—") }
        XCTAssertEqual(DashboardRingState.make(.balance, balance: nil, partial: false).status, "Unavailable")
        XCTAssertEqual(DashboardRingState.make(.balance, balance: 5, partial: true).unit, "kcal")
    }
    func testSearchRanksExactBeforePrefixAndSupportsAliasesAndTokenOrder() {
        XCTAssertEqual(FoodSearchRanking.score(name: "Rice", aliases: [], query: "rice"), 0)
        XCTAssertEqual(FoodSearchRanking.score(name: "Rice, cooked", aliases: [], query: "rice"), 1)
        XCTAssertEqual(FoodSearchRanking.score(name: "Mung beans, raw", aliases: ["moong"], query: "moong"), 2)
        XCTAssertEqual(FoodSearchRanking.score(name: "Mung beans, raw", aliases: ["moong"], query: "raw moong"), 3)
        XCTAssertNil(FoodSearchRanking.score(name: "Rice", aliases: [], query: "chicken"))
    }
}
