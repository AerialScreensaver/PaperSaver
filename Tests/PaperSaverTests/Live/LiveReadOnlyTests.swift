import XCTest
@testable import PaperSaverKit

/// Reads the real store, pluginkit and the window server. Nothing is written.
/// Run with `PAPERSAVER_INTEGRATION=1 swift test --filter LiveReadOnlyTests`.
final class LiveReadOnlyTests: XCTestCase {

    override func setUpWithError() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["PAPERSAVER_INTEGRATION"] == "1",
                          "set PAPERSAVER_INTEGRATION=1 to read the live system")
    }

    func testRealStoreDecodesAndRoundTrips() throws {
        let saver = PaperSaver()
        let store = try saver.readStore()
        XCTAssertNotNil(store.allSpacesAndDisplays ?? store.systemDefault)
        XCTAssertEqual(try StoreCodec.decode(StoreCodec.encode(store)), store)
        _ = saver.getActiveScreensavers()
        _ = saver.activeScreensaver()
        _ = saver.getCurrentWallpaperExtension()
        _ = saver.getCurrentScreensaverExtension()
    }

    func testPluginkitListsAppleScreensavers() async throws {
        let modules = await PaperSaver().listAvailableScreensavers()
        XCTAssertTrue(modules.contains { $0.name == "Flurry" && $0.type == .appExtension && $0.isSystem })
        XCTAssertFalse(modules.contains { $0.bundleIdentifier?.contains("legacyScreenSaver") == true })
    }

    func testTopologyAndSpaces() async throws {
        let saver = PaperSaver()
        let displays = saver.displaySpaces()
        XCTAssertFalse(displays.isEmpty)
        XCTAssertTrue(displays.allSatisfy { !$0.spaces.isEmpty })
        let listed = await MainActor.run { saver.listDisplays() }
        XCTAssertTrue(listed.contains { $0.isConnected && $0.isMain })
        let spaces = saver.listSpaces()
        XCTAssertFalse(spaces.isEmpty)
        XCTAssertNotNil(saver.getActiveSpace())
    }

    func testRunningExtensionsAreListed() {
        let running = WallpaperAgent.runningExtensionBundleIdentifiers()
        XCTAssertFalse(WallpaperAgent.runningProcessIdentifiers().isEmpty, "WallpaperAgent should be running")
        print("running app extensions: \(running.sorted())")
    }

    func testWallpaperExtensionRegistry() async throws {
        let saver = PaperSaver()
        let extensions = try await saver.listWallpaperExtensions()
        XCTAssertTrue(extensions.contains { $0.bundleIdentifier == ChoiceProvider.neptuneOne.rawValue })
        let screensavers = try await PluginkitCatalog().extensions()
        XCTAssertNotNil(PaperSaver.wallpaperExtensionError(bundleID: "Flurry", wallpaperExtensions: extensions, screensaverExtensions: screensavers))
    }

    func testIdleTimeReads() {
        XCTAssertGreaterThanOrEqual(PaperSaver().getIdleTime(), 0)
    }
}
