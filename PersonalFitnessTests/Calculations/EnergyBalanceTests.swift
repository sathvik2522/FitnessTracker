import XCTest
#if SWIFT_PACKAGE
@testable import PersonalFitnessCore
#else
@testable import PersonalFitness
#endif

final class EnergyBalanceTests: XCTestCase {
    func testTotalUsesRestingAndActiveEnergy() {
        let value = EnergyBalance(consumed: 1900, resting: 1600, active: 500)
        XCTAssertEqual(value.expenditure, 2100)
        XCTAssertEqual(value.net, -200)
    }

    func testSurplusAndExactBalance() {
        XCTAssertEqual(EnergyBalance(consumed: 2400, resting: 1600, active: 400).net, 400)
        XCTAssertEqual(EnergyBalance(consumed: 2000, resting: 1600, active: 400).net, 0)
    }

    func testMissingEnergyIsNotZero() {
        for value in [EnergyBalance(consumed: 0, resting: nil, active: 400),
                      EnergyBalance(consumed: 0, resting: 1600, active: nil),
                      EnergyBalance(consumed: 0, resting: nil, active: nil)] {
            XCTAssertNil(value.expenditure)
            XCTAssertNil(value.net)
        }
    }

    func testMissingConsumptionDoesNotHideKnownExpenditure() {
        let value = EnergyBalance(consumed: nil, resting: 1600, active: 400)
        XCTAssertEqual(value.expenditure, 2000)
        XCTAssertNil(value.net)
    }

    func testMeasuredZeroRemainsZero() {
        let value = EnergyBalance(consumed: 0, resting: 0, active: 0)
        XCTAssertEqual(value.expenditure, 0)
        XCTAssertEqual(value.net, 0)
    }

    func testInvalidInputsStayUnavailable() {
        for invalid in [-1.0, Double.nan, Double.infinity, -Double.infinity] {
            XCTAssertNil(EnergyBalance(consumed: invalid, resting: 1, active: 1).net)
            XCTAssertNil(EnergyBalance(consumed: 1, resting: invalid, active: 1).expenditure)
            XCTAssertNil(EnergyBalance(consumed: 1, resting: 1, active: invalid).expenditure)
        }
    }

    func testOverflowDoesNotProduceAnEstimate() {
        XCTAssertNil(EnergyBalance(consumed: 0, resting: .greatestFiniteMagnitude,
                                  active: .greatestFiniteMagnitude).expenditure)
    }
}
