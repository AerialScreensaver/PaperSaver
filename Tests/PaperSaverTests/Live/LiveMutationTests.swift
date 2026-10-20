import XCTest
@testable import PaperSaverKit

/// Rewrites the real store and restarts WallpaperAgent, then puts everything back.
/// Run with `PAPERSAVER_MUTATION=1 swift test --filter LiveMutationTests` on a Mac whose desktop
/// may flicker; never in CI.
final class LiveMutationTests: XCTestCase {
    private var original: Data!
    private var file: StoreFile!

    override func setUpWithError() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["PAPERSAVER_MUTATION"] == "1",
                          "set PAPERSAVER_MUTATION=1 to rewrite the live store")
        file = StoreFile()
        original = try file.readRaw()
        let keep = FileManager.default.temporaryDirectory.appendingPathComponent("Index.plist.\(Int(Date().timeIntervalSince1970)).bak")
        try original.write(to: keep)
        print("live store backed up to \(keep.path)")
    }

    override func tearDown() async throws {
        guard let original else { return }
        try file.writeRaw(original)
        try await WallpaperAgent().restart()
    }

    func testSetAndRestoreScreensaver() async throws {
        let saver = PaperSaver()
        let before = saver.getActiveScreensavers()
        let outcome = try await saver.setScreensaver(module: "Flurry")
        XCTAssertEqual(outcome, .applied)
        XCTAssertEqual(saver.getActiveScreensavers(), ["Flurry"])
        XCTAssertNotEqual(before, ["Flurry"], "pick a different starting screensaver for a meaningful run")
    }
}
