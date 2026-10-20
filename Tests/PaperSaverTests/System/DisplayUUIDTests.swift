import XCTest
import CoreGraphics
@testable import PaperSaverKit

final class DisplayUUIDTests: XCTestCase {

    func testValidity() {
        XCTAssertTrue(DisplayUUID.isValid("37D8832A-2D66-02CA-B9F7-8F30A301B230"))
        XCTAssertTrue(DisplayUUID.isValid("37d8832a-2d66-02ca-b9f7-8f30a301b230"))
        XCTAssertFalse(DisplayUUID.isValid("Main"))
        XCTAssertFalse(DisplayUUID.isValid("69734662"))
        XCTAssertFalse(DisplayUUID.isValid(""))
    }

    func testMainDisplayRoundTrip() throws {
        let main = CGMainDisplayID()
        let uuid = try XCTUnwrap(DisplayUUID.uuid(for: main))
        XCTAssertTrue(DisplayUUID.isValid(uuid))
        XCTAssertEqual(DisplayUUID.displayID(for: uuid), main)
        XCTAssertEqual(DisplayUUID.main, uuid)
        XCTAssertNil(DisplayUUID.displayID(for: "00000000-0000-0000-0000-000000000000"))
        XCTAssertNil(DisplayUUID.displayID(for: "DEADBEEF-1234-4000-8000-000000000001"))
    }

    func testSnapshotListsConnectedDisplays() {
        let snapshot = DisplayTopology.snapshot()
        let connected = DisplayTopology.connectedDisplayIDs()
        XCTAssertFalse(connected.isEmpty)
        XCTAssertEqual(connected.first, CGMainDisplayID(), "main display comes first")
        XCTAssertEqual(snapshot.display(number: 1)?.uuid, DisplayUUID.main)
        for display in snapshot.displays {
            XCTAssertTrue(DisplayUUID.isValid(display.uuid), "\"Main\" must be resolved to a UUID")
            XCTAssertFalse(display.spaces.isEmpty)
        }
    }
}
