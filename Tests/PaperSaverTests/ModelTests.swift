import XCTest
import AppKit
@testable import PaperSaverKit

final class ModelTests: XCTestCase {

    func testAppExtensionScreensaversUseTheScreenSaverProvider() {
        XCTAssertEqual(ScreensaverType.appExtension.provider, .screenSaver)
        XCTAssertEqual(ScreensaverType.traditional.provider, .screenSaver)
        XCTAssertNil(ScreensaverType.wallpaperExtension.provider)
        XCTAssertEqual(ScreensaverType(bundleURL: URL(fileURLWithPath: "/x/A.appex")), .appExtension)
        XCTAssertEqual(ScreensaverType(bundleURL: URL(fileURLWithPath: "/x/A.saver")), .traditional)
    }

    func testScreensaverInfoFromSlots() throws {
        let saverSlot = SlotConfiguration(choice: try WallpaperChoice(
            provider: .screenSaver, configuration: .screenSaver(moduleURL: URL(fileURLWithPath: "/Library/Screen Savers/Fliqlo.saver"))))
        let info = try XCTUnwrap(ScreensaverInfo(slot: saverSlot, displayUUID: "D"))
        XCTAssertEqual(info.name, "Fliqlo")
        XCTAssertEqual(info.identifier, "Fliqlo.saver")
        XCTAssertEqual(info.kind, .traditional)
        XCTAssertEqual(info.displayUUID, "D")

        let ext = SlotConfiguration(choice: WallpaperChoice(provider: ChoiceProvider(rawValue: "com.example.Ext"), configuration: Data("t".utf8)))
        XCTAssertEqual(ScreensaverInfo(slot: ext)?.kind, .wallpaperExtension)

        XCTAssertNil(ScreensaverInfo(slot: SystemDefaults.neptuneOne()))
        XCTAssertNil(ScreensaverInfo(slot: SlotConfiguration(choice: WallpaperChoice(provider: .placeholder))))
        XCTAssertEqual(ScreensaverInfo(slot: SlotConfiguration(choice: WallpaperChoice(provider: .aerials)))?.kind, .sequoiaVideo)
    }

    func testPlacementRoundTripsThroughWorkspaceOptions() {
        for placement in WallpaperPlacement.allCases {
            XCTAssertEqual(WallpaperPlacement(workspaceOptions: placement.workspaceOptions), placement)
        }
        XCTAssertEqual(WallpaperPlacement(workspaceOptions: [:]), .fill)
    }

    /// Store ids read back from the agent after NSWorkspace writes (macOS 27.2, 2026-10-20).
    func testPlacementStoreIDs() {
        XCTAssertEqual(WallpaperPlacement.fill.storePlacement.rawValue, "Crop")
        XCTAssertEqual(WallpaperPlacement.fit.storePlacement.rawValue, "SizeToFit")
        XCTAssertEqual(WallpaperPlacement.stretch.storePlacement.rawValue, "FillScreen")
        XCTAssertEqual(WallpaperPlacement.center.storePlacement.rawValue, "Centered")
        for placement in WallpaperPlacement.allCases {
            XCTAssertEqual(WallpaperPlacement(storePlacement: placement.storePlacement), placement)
        }
        XCTAssertNil(WallpaperPlacement(storePlacement: OptionValues.Placement(rawValue: "Tile")))
    }

    func testDisplayInfoCodableSynthesis() throws {
        let info = DisplayInfo(uuid: "U", displayID: 1, frame: CGRect(x: 0, y: 0, width: 10, height: 20), isMain: true, isConnected: true,
                               resolution: CGSize(width: 3008, height: 1692), refreshRate: 60, scale: 2, displayName: "Studio")
        let data = try JSONEncoder().encode(info)
        XCTAssertEqual(try JSONDecoder().decode(DisplayInfo.self, from: data), info)
        XCTAssertEqual(info.displayDescription, "3008x1692 @ 60Hz @ 2x")
        XCTAssertEqual(info.friendlyName, "Studio (Main)")
    }

    func testAppExtensionIdentifierFromExecutablePath() {
        let flurry = "/System/Library/ExtensionKit/Extensions/Flurry.appex/Contents/MacOS/Flurry"
        if FileManager.default.fileExists(atPath: "/System/Library/ExtensionKit/Extensions/Flurry.appex") {
            XCTAssertEqual(WallpaperAgent.appExtensionBundleIdentifier(forExecutablePath: flurry), "com.apple.Flurry")
        }
        XCTAssertNil(WallpaperAgent.appExtensionBundleIdentifier(forExecutablePath: "/System/Library/CoreServices/WallpaperAgent.app/Contents/MacOS/WallpaperAgent"))
        XCTAssertNil(WallpaperAgent.appExtensionBundleIdentifier(forExecutablePath: "/nowhere/X.appex/Contents/MacOS/X"))
    }

    func testErrorsDescribeThemselves() {
        XCTAssertEqual(PaperSaverError.screensaverNotFound("X").errorDescription, "Screensaver not found: X")
        XCTAssertTrue(PaperSaverError.verificationFailed(expected: "e", rolledBack: true).errorDescription!.contains("restored"))
    }
}
