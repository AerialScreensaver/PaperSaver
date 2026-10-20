import XCTest
@testable import PaperSaverKit

final class PluginkitParserTests: XCTestCase {

    func testParsesCapturedOutput() throws {
        let output = String(decoding: try Fixtures.data("pluginkit-output", extension: "txt"), as: UTF8.self)
        let entryLines = output.split(separator: "\n").filter { $0.contains("\t") }
        let extensions = PluginkitOutputParser.parse(output)
        XCTAssertEqual(extensions.count, entryLines.count, "every tab-separated line is an entry; the '(N plug-ins)' trailer is not")
        XCTAssertEqual(extensions.count, 16)
        for ext in extensions {
            XCTAssertTrue(ext.path.path.hasPrefix("/"))
            XCTAssertEqual(ext.uuid.count, 36)
            XCTAssertFalse(ext.bundleIdentifier.isEmpty)
            XCTAssertFalse(ext.bundleIdentifier.hasPrefix("+"))
        }
        let flurry = try XCTUnwrap(extensions.first { $0.bundleIdentifier == "com.apple.Flurry" })
        XCTAssertEqual(flurry.version, "1.0")
        XCTAssertEqual(flurry.displayName, "Flurry")
        XCTAssertTrue(flurry.isSystem)
    }

    func testNullVersionsFromTheWallpaperExtensionPoint() {
        let output = "     com.apple.wallpaper.extension.gradient((null))\tD7475F70-6E9F-5FBC-A7CA-387537741B7A\t2026-10-13 20:36:38 +0000\t/System/Library/ExtensionKit/Extensions/WallpaperGradientExtension.appex\n (1 plug-in)\n"
        let extensions = PluginkitOutputParser.parse(output)
        XCTAssertEqual(extensions.count, 1)
        XCTAssertEqual(extensions.first?.bundleIdentifier, "com.apple.wallpaper.extension.gradient")
        XCTAssertEqual(extensions.first?.version, "")
    }

    func testStatusMarkersAndSpacesInPaths() {
        let output = """
        +    com.example.One(2.1)\tAAAAAAAA-0000-0000-0000-000000000000\t2026-10-13 20:36:35 +0000\t/Applications/My App.app/Contents/PlugIns/One.appex
        -    com.example.Two(1.0)\tBBBBBBBB-0000-0000-0000-000000000000\t2026-10-13 20:36:35 +0000\t/Users/user/Library/Developer/Xcode/DerivedData/x/Two.appex
             not an entry
        """
        let extensions = PluginkitOutputParser.parse(output)
        XCTAssertEqual(extensions.count, 2)
        XCTAssertEqual(extensions[0].status, "+")
        XCTAssertEqual(extensions[0].bundleIdentifier, "com.example.One")
        XCTAssertEqual(extensions[0].path.path, "/Applications/My App.app/Contents/PlugIns/One.appex")
        XCTAssertEqual(extensions[0].displayName, "One")
        XCTAssertFalse(extensions[0].isSystem)
        XCTAssertEqual(extensions[1].status, "-")
    }
}
