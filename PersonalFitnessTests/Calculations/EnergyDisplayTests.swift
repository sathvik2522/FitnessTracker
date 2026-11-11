import XCTest
#if SWIFT_PACKAGE
@testable import PersonalFitnessCore
#else
@testable import PersonalFitness
#endif

final class EnergyDisplayTests: XCTestCase {
    func testWholeKcalUsesConsistentTiesAwayFromZero() {
        let locale = Locale(identifier: "en_US")
        XCTAssertEqual(EnergyDisplay.kilocalories(100.5, locale: locale), "101")
        XCTAssertEqual(EnergyDisplay.kilocalories(-100.5, locale: locale), "-101")
        XCTAssertEqual(EnergyDisplay.kilocalories(100.49, locale: locale), "100")
    }

    func testNegativeZeroIsNormalizedAndNearZeroIsNotCalledAnExactBalance() {
        XCTAssertEqual(EnergyDisplay.kilocalories(-0.4, locale: Locale(identifier: "en_US")), "0")
        XCTAssertEqual(EnergyDisplay.balanceTitle(-0.4), "Approximately balanced")
        XCTAssertEqual(EnergyDisplay.balanceTitle(0), "Estimated balance")
        XCTAssertEqual(EnergyDisplay.balanceTitle(-10), "Estimated deficit")
        XCTAssertEqual(EnergyDisplay.balanceTitle(10), "Estimated surplus")
    }

    func testMissingAndInvalidDoNotDisplayZero() {
        XCTAssertEqual(EnergyDisplay.kilocalories(nil), "Unavailable")
        XCTAssertEqual(EnergyDisplay.kilocalories(.infinity), "Unavailable")
        XCTAssertEqual(EnergyDisplay.kilocalories(.nan), "Unavailable")
    }
}
