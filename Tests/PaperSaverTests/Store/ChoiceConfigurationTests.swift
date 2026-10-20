import XCTest
@testable import PaperSaverKit

final class ChoiceConfigurationTests: XCTestCase {

    func testScreenSaverRoundTrip() throws {
        let url = URL(fileURLWithPath: "/Applications/Aerial.app/Contents/PlugIns/AerialScreenSaverExtension.appex")
        let config = ChoiceConfiguration.screenSaver(moduleURL: url)
        let data = try config.encoded()
        let plist = try XCTUnwrap(PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any])
        XCTAssertEqual((plist["module"] as? [String: Any])?["relative"] as? String, url.absoluteString)
        XCTAssertEqual(ChoiceConfiguration(decoding: data), config)
    }

    func testSaverBundleUsesTheSameShape() throws {
        let url = URL(fileURLWithPath: "/Library/Screen Savers/Fliqlo.saver")
        let data = try ChoiceConfiguration.screenSaver(moduleURL: url).encoded()
        XCTAssertEqual(ChoiceConfiguration(decoding: data), .screenSaver(moduleURL: url))
    }

    func testImageFileRoundTrip() throws {
        let url = URL(fileURLWithPath: "/Users/user/Pictures/a b.jpg")
        let data = try ChoiceConfiguration.imageFile(url).encoded()
        let plist = try XCTUnwrap(PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any])
        XCTAssertEqual(plist["type"] as? String, "imageFile")
        XCTAssertEqual(ChoiceConfiguration(decoding: data), .imageFile(url))
    }

    func testPhotosCollectionRoundTrip() throws {
        let config = ChoiceConfiguration.photosCollection(identifier: "A5D97137-267A-4B4E-A4CF-C991B828AC53")
        XCTAssertEqual(ChoiceConfiguration(decoding: try config.encoded()), config)
    }

    func testEmptyAndOpaque() throws {
        XCTAssertEqual(ChoiceConfiguration(decoding: Data()), .empty)
        XCTAssertEqual(try ChoiceConfiguration.empty.encoded(), Data())
        let token = Data("aerial".utf8)
        XCTAssertEqual(ChoiceConfiguration(decoding: token), .opaque(token))
        XCTAssertEqual(try ChoiceConfiguration.opaque(token).encoded(), token)
    }

    func testUnknownPlistShapeStaysOpaque() throws {
        let data = try PropertyListSerialization.data(fromPropertyList: ["assetID": "x"], format: .binary, options: 0)
        XCTAssertEqual(ChoiceConfiguration(decoding: data), .opaque(data))
    }

    func testProviderClassification() {
        XCTAssertTrue(ChoiceProvider.image.isAppleProvided)
        XCTAssertTrue(ChoiceProvider.neptuneOne.isAppleProvided)
        XCTAssertTrue(ChoiceProvider.placeholder.isPlaceholder)
        XCTAssertFalse(ChoiceProvider.placeholder.isThirdPartyExtension)
        XCTAssertTrue(ChoiceProvider(rawValue: Fixtures.aerialBundleID).isThirdPartyExtension)
    }
}
