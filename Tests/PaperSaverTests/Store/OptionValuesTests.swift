import XCTest
@testable import PaperSaverKit

final class OptionValuesTests: XCTestCase {

    private func decodeValues(_ data: Data) throws -> [String: Any] {
        let plist = try XCTUnwrap(PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any])
        return try XCTUnwrap(plist["values"] as? [String: Any])
    }

    /// The exact path System Settings writes: values.color.color._0.color.{components, colorSpace}.
    /// PaperSaver 0.3.1 wrote values.color.color.color._0…, which WallpaperAgent rejects with
    /// "Key '_0' not found … Path: values.color.color".
    func testImageOptionsEncodeTheSystemColorPath() throws {
        let values = try decodeValues(try OptionValues.image().encoded())

        let placement = try XCTUnwrap(values["placement"] as? [String: Any])
        XCTAssertEqual(((placement["picker"] as? [String: Any])?["_0"] as? [String: Any])?["id"] as? String, "Crop")

        let color = try XCTUnwrap(values["color"] as? [String: Any])
        let inner = try XCTUnwrap(color["color"] as? [String: Any])
        XCTAssertNil(inner["color"], "there must be exactly two 'color' levels above '_0'")
        let zero = try XCTUnwrap(inner["_0"] as? [String: Any])
        let payload = try XCTUnwrap(zero["color"] as? [String: Any])
        XCTAssertEqual(payload["components"] as? [Double], [0, 0, 0, 1])
        let spaceData = try XCTUnwrap(payload["colorSpace"] as? Data)
        XCTAssertEqual(try PropertyListSerialization.propertyList(from: spaceData, format: nil) as? String, "kCGColorSpaceGenericRGB")
        XCTAssertEqual(values.count, 2)
    }

    func testSystemWrittenBytesDecode() throws {
        let data = try Fixtures.data("optionvalues-image-system", extension: "bplist")
        let values = try OptionValues(decoding: data)
        XCTAssertEqual(values.placement, .crop)
        let color = try XCTUnwrap(values.backgroundColor)
        XCTAssertEqual(color.colorSpaceName, "kCGColorSpaceGenericRGB")
        XCTAssertEqual(color.components.count, 4)
        XCTAssertEqual(color.components[1], 0.4117, accuracy: 0.001)
        XCTAssertTrue(values.other.isEmpty)
        XCTAssertEqual(try OptionValues(decoding: try values.encoded()), values)
    }

    func testEmptyEncodesEmptyValues() throws {
        let values = try decodeValues(try OptionValues.empty.encoded())
        XCTAssertTrue(values.isEmpty)
        XCTAssertEqual(try OptionValues(decoding: try OptionValues.empty.encoded()), .empty)
    }

    func testLegacyNestingIsKeptVerbatim() throws {
        let legacy: [String: Any] = [
            "placement": ["picker": ["_0": ["id": "Crop"]]],
            "color": ["color": ["color": ["_0": ["color": ["components": [0.0, 0.0, 0.0, 1.0], "colorSpace": Data()]]]]],
        ]
        let values = OptionValues(values: legacy)
        XCTAssertEqual(values.placement, .crop)
        XCTAssertNil(values.backgroundColor)
        XCTAssertNotNil(values.other["color"])
        let out = try values.valuesDictionary()
        XCTAssertNotNil(((out["color"] as? [String: Any])?["color"] as? [String: Any])?["color"], "unknown shapes are written back unchanged")
    }

    func testPickersAndToggleRoundTrip() throws {
        var values = OptionValues()
        values.appearance = "automatic"
        values.shuffleFrequency = "shuffle_every_1_hour"
        values.shuffleRandomly = true
        values.other["custom"] = .dictionary(["k": .string("v")])
        let decoded = try OptionValues(decoding: try values.encoded())
        XCTAssertEqual(decoded, values)
        let dict = try decodeValues(try values.encoded())
        XCTAssertEqual((((dict["shuffleRandomly"] as? [String: Any])?["toggle"] as? [String: Any])?["_0"] as? [String: Any])?["isOn"] as? Bool, true)
    }

    func testMalformedPayloadThrows() {
        XCTAssertThrowsError(try OptionValues(decoding: Data("aerial".utf8)))
    }
}

extension OptionValuesTests {
    /// The 0.3.1 payload: one `color` level too many above `_0`.
    private func legacyValues() throws -> OptionValues {
        let colorSpace = try PropertyListSerialization.data(fromPropertyList: "kCGColorSpaceGenericRGB", format: .binary, options: 0)
        return OptionValues(values: [
            "placement": ["picker": ["_0": ["id": "Crop"]]],
            "color": ["color": ["color": ["_0": ["color": ["components": [0.0, 0.0, 0.0, 1.0], "colorSpace": colorSpace]]]]]
        ])
    }

    func testRepairingLegacyBackgroundColorMovesItToTheSystemPath() throws {
        let legacy = try legacyValues()
        XCTAssertNil(legacy.backgroundColor, "the decoder does not read the 0.3.1 shape as a colour")
        XCTAssertNotNil(legacy.other["color"])

        let repaired = try XCTUnwrap(legacy.repairingLegacyBackgroundColor())
        XCTAssertEqual(repaired.backgroundColor, .opaqueBlack)
        XCTAssertEqual(repaired.placement, .crop)
        XCTAssertTrue(repaired.other.isEmpty)
        XCTAssertEqual(repaired, .image(), "a repaired 0.3.1 desktop matches what 0.4 writes")
        XCTAssertNil(repaired.repairingLegacyBackgroundColor(), "repairing twice is a no-op")
    }

    func testRepairingLeavesOtherShapesAlone() {
        XCTAssertNil(OptionValues.image().repairingLegacyBackgroundColor(), "the system shape needs no repair")
        XCTAssertNil(OptionValues.empty.repairingLegacyBackgroundColor())
        let junk = OptionValues(values: ["color": ["color": ["something": "else"]]])
        XCTAssertNil(junk.repairingLegacyBackgroundColor(), "an unknown colour shape is kept, not guessed at")
    }
}
