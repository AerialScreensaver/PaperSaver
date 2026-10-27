import XCTest
@testable import PaperSaverKit

final class DisplaySleepParserTests: XCTestCase {

    func testPlainValue() {
        XCTAssertEqual(DisplaySleep.parse(pmsetOutput: " displaysleep         10\n"), 10)
    }

    func testPreventedBySuffix() {
        let output = """
        System-wide power settings:
        Currently in use:
         standby              1
         Sleep On Power Button 1
         disksleep            10
         sleep                1 (sleep prevented by caffeinate, powerd, sharingd)
         displaysleep         30 (display sleep prevented by firefox)
         womp                 1
        """
        XCTAssertEqual(DisplaySleep.parse(pmsetOutput: output), 30)
    }

    func testZeroIsNever() {
        XCTAssertEqual(DisplaySleep.parse(pmsetOutput: " displaysleep         0\n"), 0)
    }

    func testMissingLine() {
        XCTAssertNil(DisplaySleep.parse(pmsetOutput: " sleep                1\n disksleep            10\n"))
        XCTAssertNil(DisplaySleep.parse(pmsetOutput: ""))
    }
}
