import XCTest
@testable import PaperSaverKit

/// Pure-transform tests for the wallpaper/screensaver extension API.
///
/// These validate the in-memory plist transformation that `setWallpaperExtension` performs,
/// WITHOUT touching the real wallpaper store or restarting WallpaperAgent. They lock in the
/// non-obvious requirements WallpaperAgent imposes (see project memory):
///   - `Type` forced to "individual" and any "Linked" (automatic-mode) block removed,
///   - both Desktop and Idle slots written for `.both`,
///   - the desktop slot's option values include BOTH placement and a background color,
///   - the idle slot's option values are empty.
final class WallpaperExtensionTests: XCTestCase {

    private let manager = WallpaperManager()
    private let bundleID = "com.example.App.MyWallpaperExtension"
    private let token = Data("aerial".utf8)

    // MARK: Slot structure

    func testDesktopSlotStructureMatchesSystemFormat() throws {
        let slot = try manager.makeExtensionSlotConfiguration(
            provider: bundleID, configuration: token,
            optionValues: manager.defaultDesktopOptionValues())

        XCTAssertNotNil(slot["LastSet"])
        XCTAssertNotNil(slot["LastUse"])

        let content = try XCTUnwrap(slot["Content"] as? [String: Any])
        XCTAssertEqual(content["Shuffle"] as? String, "$null")

        let choice = try XCTUnwrap((content["Choices"] as? [[String: Any]])?.first)
        XCTAssertEqual(choice["Provider"] as? String, bundleID)
        XCTAssertEqual(choice["Configuration"] as? Data, token)
        XCTAssertEqual((choice["Files"] as? [Any])?.count, 0)

        let values = try decodeValues(content)
        XCTAssertNotNil(values["placement"], "desktop options must include placement")
        XCTAssertNotNil(values["color"], "desktop options must include a background color — WallpaperAgent rejects the choice without it")
    }

    func testIdleSlotUsesEmptyOptionValues() throws {
        let slot = try manager.makeExtensionSlotConfiguration(
            provider: bundleID, configuration: token, optionValues: [:])
        let content = try XCTUnwrap(slot["Content"] as? [String: Any])
        let values = try decodeValues(content)
        XCTAssertTrue(values.isEmpty, "idle/screensaver slot should use empty option values")
    }

    // MARK: Section transform

    /// The critical case: applying slots onto an automatic/"linked" section (what the agent
    /// leaves when no wallpaper is set) must force individual mode and drop the Linked block,
    /// or the agent ignores the Desktop/Idle choices.
    func testApplyForcesIndividualAndDropsLinked() throws {
        let linkedSection: [String: Any] = [
            "Type": "linked",
            "Linked": ["Content": ["Choices": [["Provider": "default", "Files": [], "Configuration": Data()]]]]
        ]
        let plist: [String: Any] = [
            "AllSpacesAndDisplays": linkedSection,
            "SystemDefault": linkedSection,
            "Spaces": [String: Any](),
            "Displays": [String: Any]()
        ]

        let desktop = try manager.makeExtensionSlotConfiguration(
            provider: bundleID, configuration: token, optionValues: manager.defaultDesktopOptionValues())
        let idle = try manager.makeExtensionSlotConfiguration(
            provider: bundleID, configuration: token, optionValues: [:])

        let out = manager.applyExtensionSlots(to: plist, desktop: desktop, idle: idle)

        for section in ["AllSpacesAndDisplays", "SystemDefault"] {
            let s = try XCTUnwrap(out[section] as? [String: Any], "\(section) missing")
            XCTAssertEqual(s["Type"] as? String, "individual", "\(section): Type must be forced to individual")
            XCTAssertNil(s["Linked"], "\(section): Linked (automatic-mode) block must be removed")
            XCTAssertEqual(providerOfSlot(s["Desktop"]), bundleID, "\(section): Desktop provider")
            XCTAssertEqual(providerOfSlot(s["Idle"]), bundleID, "\(section): Idle provider")
        }
    }

    /// Setting only the desktop slot preserves an existing idle slot rather than clobbering it.
    func testApplyDesktopOnlyPreservesExistingIdle() throws {
        let existingIdle: [String: Any] = ["Content": ["Choices": [["Provider": "com.existing.saver", "Files": [], "Configuration": Data()]]]]
        let plist: [String: Any] = [
            "AllSpacesAndDisplays": ["Type": "individual", "Idle": existingIdle],
            "SystemDefault": ["Type": "individual", "Idle": existingIdle]
        ]
        let desktop = try manager.makeExtensionSlotConfiguration(
            provider: bundleID, configuration: token, optionValues: manager.defaultDesktopOptionValues())

        let out = manager.applyExtensionSlots(to: plist, desktop: desktop, idle: nil)

        let s = try XCTUnwrap(out["AllSpacesAndDisplays"] as? [String: Any])
        XCTAssertEqual(providerOfSlot(s["Desktop"]), bundleID, "desktop set to our extension")
        XCTAssertEqual(providerOfSlot(s["Idle"]), "com.existing.saver", "existing idle must be preserved")
    }

    /// Setting only the screensaver preserves an existing desktop wallpaper (the common
    /// "screensaver only" case — must NOT wipe the user's wallpaper).
    func testScreensaverOnlyPreservesExistingDesktop() throws {
        let existingDesktop: [String: Any] = ["Content": ["Choices": [["Provider": "com.apple.wallpaper.choice.image", "Files": [], "Configuration": Data()]]]]
        let plist: [String: Any] = ["AllSpacesAndDisplays": ["Type": "individual", "Desktop": existingDesktop]]
        let idle = try manager.makeExtensionSlotConfiguration(provider: bundleID, configuration: token, optionValues: [:])

        let out = manager.applyExtensionSlots(to: plist, desktop: nil, idle: idle)

        let s = try XCTUnwrap(out["AllSpacesAndDisplays"] as? [String: Any])
        XCTAssertEqual(providerOfSlot(s["Idle"]), bundleID, "screensaver set to our extension")
        XCTAssertEqual(providerOfSlot(s["Desktop"]), "com.apple.wallpaper.choice.image", "existing desktop wallpaper must be preserved")
    }

    /// Single-slot from automatic/"linked" mode materializes the user's real linked wallpaper
    /// into the missing slot rather than wiping it.
    func testScreensaverOnlyFromAutomaticModeMaterializesLinkedWallpaper() throws {
        let linked: [String: Any] = ["Content": ["Choices": [["Provider": "com.apple.wallpaper.choice.dynamic", "Files": [], "Configuration": Data()]]]]
        let plist: [String: Any] = ["AllSpacesAndDisplays": ["Type": "linked", "Linked": linked]]
        let idle = try manager.makeExtensionSlotConfiguration(provider: bundleID, configuration: token, optionValues: [:])

        let out = manager.applyExtensionSlots(to: plist, desktop: nil, idle: idle)

        let s = try XCTUnwrap(out["AllSpacesAndDisplays"] as? [String: Any])
        XCTAssertNil(s["Linked"])
        XCTAssertEqual(s["Type"] as? String, "individual")
        XCTAssertEqual(providerOfSlot(s["Idle"]), bundleID)
        XCTAssertEqual(providerOfSlot(s["Desktop"]), "com.apple.wallpaper.choice.dynamic", "linked wallpaper must be materialized into Desktop, not wiped")
    }

    /// With no real wallpaper to preserve (the "default"/none placeholder), single-slot
    /// mirrors the slot we set into the other slot — never leaves a slot missing.
    func testSingleSlotFromDefaultMirrors() throws {
        let linkedDefault: [String: Any] = ["Content": ["Choices": [["Provider": "default", "Files": [], "Configuration": Data()]]]]
        let plist: [String: Any] = ["AllSpacesAndDisplays": ["Type": "linked", "Linked": linkedDefault]]
        let idle = try manager.makeExtensionSlotConfiguration(provider: bundleID, configuration: token, optionValues: [:])

        let out = manager.applyExtensionSlots(to: plist, desktop: nil, idle: idle)

        let s = try XCTUnwrap(out["AllSpacesAndDisplays"] as? [String: Any])
        XCTAssertEqual(providerOfSlot(s["Idle"]), bundleID)
        XCTAssertEqual(providerOfSlot(s["Desktop"]), bundleID, "no real wallpaper to preserve → mirror the set slot")
    }

    // MARK: Helpers

    private func decodeValues(_ content: [String: Any]) throws -> [String: Any] {
        let eov = try XCTUnwrap(content["EncodedOptionValues"] as? Data)
        let decoded = try PropertyListSerialization.propertyList(from: eov, options: [], format: nil) as? [String: Any]
        return (decoded?["values"] as? [String: Any]) ?? [:]
    }

    private func providerOfSlot(_ slot: Any?) -> String? {
        guard let slot = slot as? [String: Any],
              let content = slot["Content"] as? [String: Any],
              let choices = content["Choices"] as? [[String: Any]] else { return nil }
        return choices.first?["Provider"] as? String
    }
}
