import XCTest
@testable import PaperSaverKit

final class StoreCodecTests: XCTestCase {

    func testEveryFixtureDecodesAndRoundTrips() throws {
        for name in Fixtures.storeNames {
            let decoded = try Fixtures.store(name)
            let reencoded = StoreCodec.encode(decoded)
            let again = try StoreCodec.decode(reencoded)
            XCTAssertEqual(decoded, again, "\(name): decode(encode(decode(x))) must equal decode(x)")
        }
    }

    func testLinkedDefaultFixture() throws {
        let store = try Fixtures.store("store-linked-default")
        let section = try XCTUnwrap(store.allSpacesAndDisplays)
        XCTAssertEqual(section.type, .linked)
        XCTAssertNil(section.desktop)
        XCTAssertNil(section.idle)
        XCTAssertEqual(section.linked?.provider, .placeholder)
        XCTAssertEqual(section.linked?.provider?.isPlaceholder, true)
        XCTAssertEqual(section.linked?.optionValues, .null, "the agent writes the placeholder with the $null string")
        XCTAssertEqual(section.linked?.shuffle, .null)
        XCTAssertTrue(store.isAllSpacesMode)
        XCTAssertFalse(store.hasAnyDesktopChoice)
    }

    /// Written by WallpaperAgent itself after an NSWorkspace image write on one display.
    func testAgentWrittenPerSpaceFixture() throws {
        let store = try Fixtures.store("store-agent-perspace-image")
        let all = try XCTUnwrap(store.allSpacesAndDisplays)
        XCTAssertEqual(all.type, .idle)
        XCTAssertNil(all.desktop)
        XCTAssertEqual(all.idle?.provider, .placeholder, "the agent uses Type = idle with a placeholder when desktops are per Space")
        XCTAssertEqual(all.idle?.optionValues, .null)
        XCTAssertEqual(store.systemDefault?.type, .linked)
        XCTAssertFalse(store.isAllSpacesMode)
        XCTAssertTrue(store.hasAnyDesktopChoice)
        let imageSections = store.allSections.filter { $0.desktop?.provider == .image }
        XCTAssertEqual(imageSections.count, 2, "the current Space's Default and its display section")
        for section in imageSections {
            XCTAssertEqual(section.type, .individual)
            XCTAssertEqual(section.desktop?.optionValues.values?.placement, .sizeToFit, "the image was set with NSWorkspace scaling 'fit'")
            XCTAssertNotNil(section.desktop?.optionValues.values?.backgroundColor, "the agent's own image choice uses the two-level colour path")
            XCTAssertEqual(section.idle?.provider, .placeholder)
        }
        XCTAssertNil(ScreensaverInfo(slot: try XCTUnwrap(all.idle)), "a placeholder is not a screensaver")
    }

    func testMixedFixtureShapes() throws {
        let store = try Fixtures.store("store-mixed-allspaces-extension")
        XCTAssertFalse(store.isAllSpacesMode)

        // AllSpacesAndDisplays was written by PaperSaver 0.3.1: the mis-nested colour must land
        // in `other`, untouched, not be mistaken for a background colour.
        let all = try XCTUnwrap(store.allSpacesAndDisplays)
        XCTAssertEqual(all.type, .individual)
        XCTAssertEqual(all.desktop?.provider?.rawValue, Fixtures.aerialBundleID)
        XCTAssertEqual(all.desktop?.provider?.isThirdPartyExtension, true)
        let badValues = try XCTUnwrap(all.desktop?.optionValues.values)
        XCTAssertEqual(badValues.placement, .crop)
        XCTAssertNil(badValues.backgroundColor)
        XCTAssertNotNil(badValues.other["color"]?["color"]?["color"]?["_0"], "0.3.1 nesting is preserved verbatim")
        XCTAssertEqual(all.desktop?.configuration, .opaque(Data("aerial".utf8)))
        XCTAssertEqual(all.idle?.optionValues, .values(.empty))

        // SystemDefault was written by System Settings.
        let system = try XCTUnwrap(store.systemDefault)
        XCTAssertEqual(system.desktop?.provider, .image)
        guard case .imageFile(let url)? = system.desktop?.configuration else { return XCTFail("image configuration expected") }
        XCTAssertEqual(url.pathExtension, "jpg")
        let values = try XCTUnwrap(system.desktop?.optionValues.values)
        XCTAssertEqual(values.placement, .crop)
        let color = try XCTUnwrap(values.backgroundColor)
        XCTAssertEqual(color.colorSpaceName, "kCGColorSpaceGenericRGB")
        XCTAssertEqual(color.components.count, 4)
        XCTAssertEqual(color.components[0], 0.2549, accuracy: 0.001)
        XCTAssertEqual(color.components[3], 1.0)
        XCTAssertTrue(values.other.isEmpty)

        XCTAssertEqual(system.idle?.provider, .screenSaver)
        XCTAssertEqual(system.idle?.optionValues, .null, "System Settings writes the string $null for screensaver choices")
        guard case .screenSaver(let moduleURL)? = system.idle?.configuration else { return XCTFail("screen-saver configuration expected") }
        XCTAssertEqual(moduleURL.lastPathComponent, "AerialScreenSaverExtension.appex")

        XCTAssertEqual(store.spaces.count, 3)
        XCTAssertEqual(store.displays.count, 3)
        XCTAssertNotNil(store.spaces[""]?.default, "the first Space uses the empty key")
    }

    func testIdleOnlyFixture() throws {
        let store = try Fixtures.store("store-idle-only-allspaces")
        let all = try XCTUnwrap(store.allSpacesAndDisplays)
        XCTAssertEqual(all.type, .idle)
        XCTAssertNil(all.desktop)
        XCTAssertEqual(all.idle?.provider?.rawValue, Fixtures.aerialBundleID)
        XCTAssertEqual(store.systemDefault?.type, .individual)
        XCTAssertEqual(store.systemDefault?.desktop?.provider, .image)
        for entry in store.spaces.values {
            XCTAssertEqual(entry.default?.type, .individual)
            XCTAssertEqual(entry.default?.desktop?.provider, .image)
            XCTAssertFalse(entry.displays.isEmpty)
            for section in entry.displays.values {
                XCTAssertEqual(section.type, .individual)
                XCTAssertEqual(section.desktop?.provider, .image)
            }
        }
    }

    func testPhotosFixture() throws {
        let store = try Fixtures.store("store-photos-collection")
        let all = try XCTUnwrap(store.allSpacesAndDisplays)
        XCTAssertEqual(all.desktop?.provider, .photos)
        guard case .photosCollection(let identifier)? = all.desktop?.configuration else { return XCTFail("collection expected") }
        XCTAssertEqual(identifier.count, 36)
        XCTAssertEqual(all.desktop?.optionValues.values?.shuffleFrequency, "shuffle_every_1_hour")
        let idleValues = try XCTUnwrap(all.idle?.optionValues.values)
        XCTAssertEqual(idleValues.appearance, "automatic")
        XCTAssertEqual(idleValues.shuffleRandomly, true)
        XCTAssertEqual(idleValues.placement, .crop)
        XCTAssertNotNil(idleValues.backgroundColor)
    }

    func testBothSlotsFixture() throws {
        let store = try Fixtures.store("store-extension-both-slots")
        XCTAssertTrue(store.isAllSpacesMode)
        XCTAssertEqual(store.allSpacesAndDisplays?.desktop?.provider?.rawValue, Fixtures.aerialBundleID)
        XCTAssertEqual(store.allSpacesAndDisplays?.idle?.provider?.rawValue, Fixtures.aerialBundleID)
    }

    func testUnknownKeysSurvive() throws {
        var plist = try Fixtures.plist("store-extension-both-slots")
        plist["FutureTopLevelKey"] = ["a": 1]
        var section = try XCTUnwrap(plist["AllSpacesAndDisplays"] as? [String: Any])
        section["FutureSectionKey"] = "x"
        var desktop = try XCTUnwrap(section["Desktop"] as? [String: Any])
        desktop["FutureSlotKey"] = 2
        var content = try XCTUnwrap(desktop["Content"] as? [String: Any])
        content["FutureContentKey"] = true
        desktop["Content"] = content
        section["Desktop"] = desktop
        plist["AllSpacesAndDisplays"] = section

        let store = try StoreCodec.decode(plist)
        XCTAssertEqual(store.extra["FutureTopLevelKey"], .dictionary(["a": .int(1)]))
        XCTAssertEqual(store.allSpacesAndDisplays?.extra["FutureSectionKey"], .string("x"))
        XCTAssertEqual(store.allSpacesAndDisplays?.desktop?.extra["FutureSlotKey"], .int(2))
        XCTAssertEqual(store.allSpacesAndDisplays?.desktop?.contentExtra["FutureContentKey"], .bool(true))

        let out = StoreCodec.encode(store)
        XCTAssertNotNil(out["FutureTopLevelKey"])
        let outSection = try XCTUnwrap(out["AllSpacesAndDisplays"] as? [String: Any])
        XCTAssertEqual(outSection["FutureSectionKey"] as? String, "x")
        let outDesktop = try XCTUnwrap(outSection["Desktop"] as? [String: Any])
        XCTAssertEqual(outDesktop["FutureSlotKey"] as? Int, 2)
        XCTAssertEqual((outDesktop["Content"] as? [String: Any])?["FutureContentKey"] as? Bool, true)
    }

    func testNullStringsAndAbsentKeysRoundTrip() throws {
        let plist: [String: Any] = [
            "AllSpacesAndDisplays": [
                "Type": "individual",
                "Idle": ["Content": ["Choices": [["Provider": "com.apple.wallpaper.choice.screen-saver", "Configuration": Data(), "Files": []]],
                                     "EncodedOptionValues": "$null", "Shuffle": "$null"]],
                "Desktop": ["Content": ["Choices": [["Provider": "default", "Configuration": Data(), "Files": []]]]],
            ],
        ]
        let store = try StoreCodec.decode(plist)
        XCTAssertEqual(store.allSpacesAndDisplays?.idle?.optionValues, .null)
        XCTAssertEqual(store.allSpacesAndDisplays?.idle?.shuffle, .null)
        XCTAssertEqual(store.allSpacesAndDisplays?.desktop?.optionValues, .absent)
        XCTAssertEqual(store.allSpacesAndDisplays?.desktop?.shuffle, .absent)
        let out = StoreCodec.encode(store)
        let section = try XCTUnwrap(out["AllSpacesAndDisplays"] as? [String: Any])
        let idleContent = try XCTUnwrap((section["Idle"] as? [String: Any])?["Content"] as? [String: Any])
        XCTAssertEqual(idleContent["EncodedOptionValues"] as? String, "$null")
        let desktopContent = try XCTUnwrap((section["Desktop"] as? [String: Any])?["Content"] as? [String: Any])
        XCTAssertNil(desktopContent["EncodedOptionValues"])
        XCTAssertNil(desktopContent["Shuffle"])
    }

    func testPlistValueNumberKinds() {
        XCTAssertEqual(PlistValue(any: true), .bool(true))
        XCTAssertEqual(PlistValue(any: 3), .int(3))
        XCTAssertEqual(PlistValue(any: 2.5), .double(2.5))
        XCTAssertEqual(PlistValue(any: NSNumber(value: 1.0)), .double(1.0))
        XCTAssertEqual(PlistValue(any: "s"), .string("s"))
        XCTAssertNil(PlistValue(any: NSObject()))
    }
}
