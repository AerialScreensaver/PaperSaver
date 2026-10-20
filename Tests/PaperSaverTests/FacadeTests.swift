import XCTest
@testable import PaperSaverKit

/// Facade tests on a temporary store with a no-op agent: nothing here touches the real store.
final class FacadeTests: XCTestCase {
    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("PaperSaverFacade-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    private func makeSaver(fixture: String) throws -> PaperSaver {
        let storeURL = directory.appendingPathComponent("Index.plist")
        try Fixtures.data(fixture, extension: "plist").write(to: storeURL)
        var configuration = PaperSaverConfiguration()
        configuration.storeURL = storeURL
        configuration.log = .silent
        configuration.systemDefault = fixedNeptune
        configuration.validatesWallpaperExtensions = false
        configuration.writeOptions.quietPeriod = .milliseconds(10)
        configuration.writeOptions.settleTimeout = .milliseconds(50)
        return PaperSaver(configuration: configuration, agent: NoopWallpaperAgent())
    }

    private let aerial = Fixtures.aerialBundleID

    func testReadsNamesAndExtensions() throws {
        let saver = try makeSaver(fixture: "store-mixed-allspaces-extension")
        XCTAssertEqual(saver.getActiveScreensavers(), ["AerialScreenSaverExtension", aerial].sorted())
        XCTAssertEqual(saver.getCurrentWallpaperExtension(), aerial)
        XCTAssertEqual(saver.getCurrentScreensaverExtension(), aerial)
        let info = try XCTUnwrap(saver.activeScreensaver())
        XCTAssertEqual(info.kind, .wallpaperExtension)
        XCTAssertEqual(info.identifier, aerial)
        XCTAssertEqual(saver.getCurrentWallpaperExtension(in: .space(uuid: "nope")), aerial, "an unknown Space falls back to AllSpacesAndDisplays")
    }

    func testImageDesktopIsNotReportedAsAnExtension() throws {
        let saver = try makeSaver(fixture: "store-idle-only-allspaces")
        XCTAssertNil(saver.getCurrentWallpaperExtension())
        XCTAssertEqual(saver.getCurrentScreensaverExtension(), aerial)
        XCTAssertEqual(saver.currentWallpaperChoice(slot: .desktop)?.provider, .image)
    }

    func testClearIfSameProviderIsAnOptIn() async throws {
        let saver = try makeSaver(fixture: "store-extension-both-slots")
        let outcome = try await saver.setWallpaperExtension(bundleID: aerial, configuration: Data("aerial".utf8), slot: .desktop,
                                                            otherSlot: .clearIfSameProvider)
        XCTAssertEqual(outcome, .applied)
        XCTAssertEqual(saver.getCurrentWallpaperExtension(), aerial)
        XCTAssertNil(saver.getCurrentScreensaverExtension())
        let store = try saver.readStore()
        XCTAssertEqual(store.allSpacesAndDisplays?.idle?.provider, .neptuneOne)
        XCTAssertEqual(store.allSpacesAndDisplays?.desktop?.optionValues.values?.backgroundColor, .opaqueBlack)
        XCTAssertEqual(store.allSpacesAndDisplays?.desktop?.optionValues.values?.placement, .crop)
    }

    /// Guillaume's 2026-10-20 report: Aerial as wallpaper, another screensaver; setting Aerial as
    /// screensaver must not reset the wallpaper, and setting the wallpaper must not reset the
    /// screensaver.
    func testSettingOneSlotKeepsTheOtherByDefault() async throws {
        let saver = try makeSaver(fixture: "store-mixed-allspaces-extension")
        let desktopBefore = try saver.readStore().allSpacesAndDisplays?.desktop
        try await saver.setWallpaperExtension(bundleID: aerial, configuration: Data("aerial".utf8), slot: .screensaver)
        XCTAssertEqual(try saver.readStore().allSpacesAndDisplays?.desktop, desktopBefore, "the wallpaper is untouched")
        XCTAssertEqual(saver.getCurrentScreensaverExtension(), aerial)
        XCTAssertEqual(saver.getCurrentWallpaperExtension(), aerial)

        let other = try makeSaver(fixture: "store-idle-only-allspaces")
        let idleBefore = try other.readStore().allSpacesAndDisplays?.idle
        try await other.setWallpaperExtension(bundleID: "com.example.Other.WallpaperExtension", slot: .desktop)
        XCTAssertEqual(try other.readStore().allSpacesAndDisplays?.idle, idleBefore, "the screensaver is untouched")
        XCTAssertEqual(other.getCurrentWallpaperExtension(), "com.example.Other.WallpaperExtension")
    }

    func testBothSlotsInOneWrite() async throws {
        let saver = try makeSaver(fixture: "store-linked-default")
        let before = try Data(contentsOf: saver.configuration.storeURL)
        let outcome = try await saver.setWallpaperExtension(bundleID: aerial, configuration: Data("aerial".utf8), slots: [.desktop, .screensaver])
        XCTAssertEqual(outcome, .applied)
        let store = try saver.readStore()
        for section in [store.allSpacesAndDisplays, store.systemDefault].compactMap({ $0 }) {
            XCTAssertEqual(section.type, .individual)
            XCTAssertEqual(section.desktop?.provider?.rawValue, aerial)
            XCTAssertEqual(section.idle?.provider?.rawValue, aerial)
            XCTAssertEqual(section.desktop?.optionValues.values?.placement, .crop)
            XCTAssertNotNil(section.desktop?.optionValues.values?.backgroundColor)
            XCTAssertEqual(section.idle?.optionValues, .values(.empty), "no placement in the screensaver slot")
            XCTAssertNil(section.linked)
        }
        XCTAssertEqual(try Data(contentsOf: saver.configuration.storeURL.appendingPathExtension("backup")), before,
                       "one write: the backup is the store before the call")
        do {
            try await saver.setWallpaperExtension(bundleID: aerial, slots: [])
            XCTFail("expected invalidConfiguration")
        } catch PaperSaverError.invalidConfiguration {}
    }

    func testScreensaverOnlyFromDefaultMaterializesTheSystemDesktop() async throws {
        let saver = try makeSaver(fixture: "store-linked-default")
        try await saver.setWallpaperExtension(bundleID: aerial, slot: .screensaver)
        XCTAssertEqual(saver.getCurrentScreensaverExtension(), aerial)
        XCTAssertNil(saver.getCurrentWallpaperExtension())
        let section = try XCTUnwrap(try saver.readStore().allSpacesAndDisplays)
        XCTAssertEqual(section.type, .individual, "no desktop anywhere: the agent rejects idle-only sections")
        XCTAssertEqual(section.desktop?.provider, .neptuneOne)
        XCTAssertNil(section.linked)
    }

    func testScreensaverOnlyKeepsIdleSectionsInPerSpaceStores() async throws {
        let saver = try makeSaver(fixture: "store-agent-perspace-image")
        try await saver.setWallpaperExtension(bundleID: aerial, slot: .screensaver)
        XCTAssertEqual(saver.getCurrentScreensaverExtension(), aerial)
        let section = try XCTUnwrap(try saver.readStore().allSpacesAndDisplays)
        XCTAssertEqual(section.type, .idle)
        XCTAssertNil(section.desktop)
    }

    func testScreensaverOnlyCanBeForcedToAnIdleSection() async throws {
        let saver0 = try makeSaver(fixture: "store-linked-default")
        var configuration = saver0.configuration
        configuration.screensaverOnlyStrategy = .idleSection
        let saver = PaperSaver(configuration: configuration, agent: NoopWallpaperAgent())
        try await saver.setWallpaperExtension(bundleID: aerial, slot: .screensaver)
        let section = try XCTUnwrap(try saver.readStore().allSpacesAndDisplays)
        XCTAssertEqual(section.type, .idle)
        XCTAssertNil(section.desktop)
    }

    func testClearWallpaperExtension() async throws {
        let saver = try makeSaver(fixture: "store-extension-both-slots")
        try await saver.clearWallpaperExtension(slot: .screensaver)
        XCTAssertNil(saver.getCurrentScreensaverExtension())
        XCTAssertEqual(saver.getCurrentWallpaperExtension(), aerial)
        XCTAssertEqual(saver.currentWallpaperChoice(slot: .screensaver)?.provider, .neptuneOne)
        XCTAssertNil(saver.activeScreensaver(), "the system default is not a screensaver")
    }

    func testEmptyBundleIDIsRejected() async throws {
        let saver = try makeSaver(fixture: "store-linked-default")
        do {
            try await saver.setWallpaperExtension(bundleID: "", slot: .desktop)
            XCTFail("expected invalidConfiguration")
        } catch PaperSaverError.invalidConfiguration {}
    }

    func testSetScreensaverEverywhereWithASystemExtension() async throws {
        let flurry = URL(fileURLWithPath: "/System/Library/ExtensionKit/Extensions/Flurry.appex")
        try XCTSkipUnless(FileManager.default.fileExists(atPath: flurry.path), "Flurry.appex not on this Mac")
        let saver = try makeSaver(fixture: "store-mixed-allspaces-extension")
        try await saver.setScreensaverEverywhere(module: "Flurry")
        XCTAssertTrue(saver.getActiveScreensavers().contains("Flurry"))
        XCTAssertEqual(saver.getActiveScreensavers().count, 1, "every section now names Flurry")
        let info = try XCTUnwrap(saver.activeScreensaver())
        XCTAssertEqual(info.name, "Flurry")
        XCTAssertEqual(info.kind, .appExtension)
        XCTAssertEqual(info.modulePath, flurry.path)
        let store = try saver.readStore()
        XCTAssertEqual(store.allSpacesAndDisplays?.idle?.optionValues, .null, "screensaver choices carry the $null string")
        XCTAssertEqual(store.allSpacesAndDisplays?.desktop?.provider?.rawValue, aerial, "the desktop is untouched")
        XCTAssertEqual(store.systemDefault?.desktop?.provider, .image)
        for section in store.allSections {
            XCTAssertEqual(section.idle?.provider, .screenSaver)
        }
    }

    func testUnknownModuleThrows() async throws {
        let saver = try makeSaver(fixture: "store-linked-default")
        do {
            try await saver.setScreensaverEverywhere(module: "NoSuchSaver-\(UUID().uuidString)")
            XCTFail("expected screensaverNotFound")
        } catch PaperSaverError.screensaverNotFound(let name) {
            XCTAssertTrue(name.hasPrefix("NoSuchSaver"))
        }
    }

    func testNoRestartWritesAndStops() async throws {
        let saver = try makeSaver(fixture: "store-linked-default")
        let outcome = try await saver.setWallpaperExtension(bundleID: aerial, slot: .desktop, options: .noRestart)
        XCTAssertEqual(outcome, .writtenWithoutRestart)
        XCTAssertEqual(saver.getCurrentWallpaperExtension(), aerial)
    }

    func testBackupFollowsWritesAndRestores() async throws {
        let saver = try makeSaver(fixture: "store-linked-default")
        XCTAssertNil(saver.backupInfo())
        try await saver.setWallpaperExtension(bundleID: aerial, slot: .desktop)
        XCTAssertNotNil(saver.backupInfo())
        try await saver.clearWallpaperExtension(slot: .desktop)
        XCTAssertNil(saver.getCurrentWallpaperExtension())
        try await saver.restoreFromBackup(restartAgent: false)
        XCTAssertEqual(saver.getCurrentWallpaperExtension(), aerial, "the backup is the state before the last write")
    }

    func testStoreImagePath() async throws {
        let image = directory.appendingPathComponent("wall.jpg")
        try Data([0xFF, 0xD8, 0xFF]).write(to: image)
        let saver = try makeSaver(fixture: "store-extension-both-slots")
        try await saver.setWallpaper(imageURL: image, target: .everywhere)
        let desktop = try XCTUnwrap(saver.currentWallpaperChoice(slot: .desktop))
        XCTAssertEqual(desktop.provider, .image)
        XCTAssertEqual(desktop.configuration, .imageFile(URL(string: image.absoluteString)!))
        XCTAssertEqual(desktop.optionValues.values?.placement, .crop)
        XCTAssertEqual(saver.getCurrentScreensaverExtension(), aerial, "keep policy leaves the screensaver")
        do {
            try await saver.setWallpaper(imageURL: directory.appendingPathComponent("missing.jpg"), target: .everywhere)
            XCTFail("expected fileNotFound")
        } catch PaperSaverError.fileNotFound {}
    }

    func testStoreSummaryListsEverySection() throws {
        let saver = try makeSaver(fixture: "store-idle-only-allspaces")
        let summary = StoreSummary(try saver.readStore())
        XCTAssertEqual(summary.sections.count, try saver.readStore().allSections.count)
        let all = try XCTUnwrap(summary.sections.first { $0.path == "AllSpacesAndDisplays" })
        XCTAssertEqual(all.type, "idle")
        XCTAssertNil(all.desktop)
        XCTAssertEqual(all.idle?.provider, aerial)
        XCTAssertEqual(all.idle?.optionValues, "{}")
        XCTAssertNoThrow(try JSONEncoder().encode(summary))
    }

    func testWallpaperExtensionValidation() {
        let aerial = PluginkitExtension(bundleIdentifier: aerial, version: "4.1.8", uuid: "U", path: URL(fileURLWithPath: "/Applications/Aerial.app/Contents/Extensions/Aerial4WallpaperExtension.appex"))
        let sample = PluginkitExtension(bundleIdentifier: "net.aerialscreensaver.AppexSaverMinimal.Extension", version: "1.0", uuid: "V", path: URL(fileURLWithPath: "/x/AppexSaverMinimal.app/Contents/PlugIns/AppexSaverMinimalExtension.appex"))
        func check(_ id: String) -> PaperSaverError? {
            PaperSaver.wallpaperExtensionError(bundleID: id, wallpaperExtensions: [aerial], screensaverExtensions: [sample])
        }
        XCTAssertNil(check(self.aerial))
        for id in ["AppexSaverMinimalExtension", "net.aerialscreensaver.AppexSaverMinimal.Extension"] {
            guard case .wallpaperExtensionNotFound(let bundleID, let hint)? = check(id) else { return XCTFail("\(id) must be rejected") }
            XCTAssertEqual(bundleID, id)
            XCTAssertTrue(hint?.contains("set-saver AppexSaverMinimalExtension") == true, hint ?? "no hint")
        }
        guard case .wallpaperExtensionNotFound(_, let hint)? = check("Aerial4WallpaperExtension") else { return XCTFail() }
        XCTAssertTrue(hint?.contains(self.aerial) == true)
        guard case .wallpaperExtensionNotFound(_, let none)? = check("com.example.Nothing") else { return XCTFail() }
        XCTAssertNil(none)
        XCTAssertTrue(PaperSaverError.wallpaperExtensionNotFound(bundleID: "x", hint: nil).errorDescription!.contains("pluginkit"))
    }

    func testValidationRunsBeforeAnyWrite() async throws {
        let saver0 = try makeSaver(fixture: "store-extension-both-slots")
        var configuration = saver0.configuration
        configuration.validatesWallpaperExtensions = true
        let saver = PaperSaver(configuration: configuration, agent: NoopWallpaperAgent())
        let before = try saver.readStore()
        do {
            try await saver.setWallpaperExtension(bundleID: "com.example.NotRegistered.\(UUID().uuidString)", slot: .screensaver)
            XCTFail("expected wallpaperExtensionNotFound")
        } catch PaperSaverError.wallpaperExtensionNotFound {}
        XCTAssertEqual(try saver.readStore(), before, "a rejected identifier never touches the store")
    }

    func testSystemDefaultsByMacOSVersion() {
        let sequoia = SystemDefaults.slot(.desktop, on: OperatingSystemVersion(majorVersion: 15, minorVersion: 6, patchVersion: 0))
        XCTAssertEqual(sequoia.provider, .placeholder)
        XCTAssertEqual(sequoia.optionValues, .null)
        XCTAssertEqual(SystemDefaults.slot(.screensaver, on: OperatingSystemVersion(majorVersion: 26, minorVersion: 0, patchVersion: 0)).provider, .neptuneOne)
        XCTAssertNil(ScreensaverInfo(slot: sequoia))
    }
}
