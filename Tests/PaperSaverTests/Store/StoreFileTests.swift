import XCTest
@testable import PaperSaverKit

final class StoreFileTests: XCTestCase {
    private var directory: URL!
    private var file: StoreFile!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("PaperSaverTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        file = StoreFile(url: directory.appendingPathComponent("Store/Index.plist"))
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    func testMissingFileThrowsFileNotFound() {
        XCTAssertThrowsError(try file.read()) { error in
            guard case PaperSaverError.fileNotFound(let url)? = error as? PaperSaverError else { return XCTFail("\(error)") }
            XCTAssertEqual(url, file.url)
        }
        XCTAssertNil(file.modificationStamp())
        XCTAssertNil(file.backupInfo())
    }

    func testWriteCreatesDirectoryAndRoundTrips() throws {
        let store = try Fixtures.store("store-extension-both-slots")
        let snapshot = try file.write(store)
        XCTAssertNil(snapshot.previousContents, "no previous file")
        XCTAssertEqual(try file.read(), store)
        XCTAssertNil(file.backupInfo(), "nothing to back up on the first write")
        XCTAssertNotNil(file.modificationStamp())
    }

    func testEverySubsequentWriteRefreshesTheBackup() throws {
        let first = try Fixtures.store("store-linked-default")
        let second = try Fixtures.store("store-extension-both-slots")
        let third = try Fixtures.store("store-photos-collection")
        try file.write(first)
        let firstBytes = try file.readRaw()

        let snapshot = try file.write(second)
        XCTAssertEqual(snapshot.previousContents, firstBytes)
        XCTAssertEqual(try Data(contentsOf: file.backupURL), firstBytes)
        let secondBytes = try file.readRaw()

        try file.write(third)
        XCTAssertEqual(try Data(contentsOf: file.backupURL), secondBytes, "the backup must follow every write, not only the first")
        XCTAssertEqual(file.backupInfo()?.size, secondBytes.count)
    }

    func testRestoreSnapshotPutsTheExactBytesBack() throws {
        try file.write(try Fixtures.store("store-linked-default"))
        let before = try file.readRaw()
        let snapshot = try file.write(try Fixtures.store("store-photos-collection"))
        try file.restore(snapshot)
        XCTAssertEqual(try file.readRaw(), before)
    }

    func testRestoreFromBackupFile() throws {
        try file.write(try Fixtures.store("store-linked-default"))
        let before = try file.readRaw()
        try file.write(try Fixtures.store("store-photos-collection"))
        try file.restoreFromBackupFile()
        XCTAssertEqual(try file.readRaw(), before)
    }

    func testWriterRollsBackWhenVerificationFails() async throws {
        try file.write(try Fixtures.store("store-linked-default"))
        let before = try file.readRaw()
        let writer = StoreWriter(file: file, agent: NoopWallpaperAgent(), log: .silent)
        var options = WriteOptions.default
        options.settleTimeout = .milliseconds(50)
        options.quietPeriod = .milliseconds(10)
        do {
            _ = try await writer.apply(expectation: "test", options: options,
                                       edit: { try $0.setting(.screensaver, to: .extensionChoice(slot: .screensaver), systemDefault: fixedNeptune) },
                                       verify: { _ in false })
            XCTFail("expected verificationFailed")
        } catch PaperSaverError.verificationFailed(_, let rolledBack) {
            XCTAssertTrue(rolledBack)
        }
        XCTAssertEqual(try file.readRaw(), before)
    }

    func testWriterAppliesAndVerifies() async throws {
        try file.write(try Fixtures.store("store-linked-default"))
        let writer = StoreWriter(file: file, agent: NoopWallpaperAgent(), log: .silent)
        var options = WriteOptions.default
        options.settleTimeout = .milliseconds(50)
        options.quietPeriod = .milliseconds(10)
        let outcome = try await writer.apply(expectation: "test", options: options,
                                             edit: { try $0.setting(.screensaver, to: .extensionChoice(slot: .screensaver), systemDefault: fixedNeptune) },
                                             verify: { $0.provider(of: .screensaver)?.rawValue == "com.example.Test.WallpaperExtension" })
        XCTAssertEqual(outcome, .applied)
        XCTAssertEqual(try file.read().allSpacesAndDisplays?.type, .individual, "no desktop anywhere: the system default is materialised")
        XCTAssertEqual(try file.read().allSpacesAndDisplays?.desktop?.provider, .neptuneOne)

        let noRestart = try await writer.apply(expectation: "test", options: .noRestart,
                                               edit: { $0 }, verify: { _ in false })
        XCTAssertEqual(noRestart, .writtenWithoutRestart)
    }
}
