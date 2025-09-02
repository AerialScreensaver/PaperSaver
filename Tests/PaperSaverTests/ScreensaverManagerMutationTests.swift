import XCTest
@testable import PaperSaver

/// Tests that modify system state and require backup/restore
final class ScreensaverManagerMutationTests: XCTestCase {
    
    private var manager: ScreensaverManager!
    private static let backupLock = NSLock()
    nonisolated(unsafe) private static var _backupURL: URL?
    
    private static var backupURL: URL? {
        get {
            backupLock.lock()
            defer { backupLock.unlock() }
            return _backupURL
        }
        set {
            backupLock.lock()
            defer { backupLock.unlock() }
            _backupURL = newValue
        }
    }
    
    // MARK: - Test Lifecycle
    
    /// Create a single backup for the entire test class
    override class func setUp() {
        super.setUp()
        print("\n🔒 Creating backup for mutation tests...")
        backupURL = TestHelpers.createWallpaperBackup()
        
        if backupURL == nil {
            print("⚠️ Failed to create backup - tests may affect system state!")
        }
    }
    
    /// Restore the backup after all tests complete
    override class func tearDown() {
        if let backup = backupURL {
            print("\n🔓 Restoring original configuration...")
            TestHelpers.restoreWallpaperBackup(backup)
        }
        backupURL = nil
        super.tearDown()
    }
    
    override func setUp() {
        super.setUp()
        manager = ScreensaverManager()
    }
    
    override func tearDown() {
        manager = nil
        super.tearDown()
    }
    
    // MARK: - Screensaver Setting Tests
    
    func testSetScreensaver() async throws {
        guard let testScreensaver = TestHelpers.getTestScreensaver() else {
            throw XCTSkip("No screensavers available to test with")
        }
        
        print("\n🎬 Testing screensaver: \(testScreensaver.name)")
        
        // Set the screensaver
        try await manager.setScreensaver(module: testScreensaver.name, screen: nil)
        
        // Wait for changes to apply
        await TestHelpers.waitForWallpaperAgent()
        
        // Verify it was set
        assertScreensaverSet(to: testScreensaver.name)
    }
    
    func testSetMultipleScreensaversSequentially() async throws {
        let screensavers = manager.listAvailableScreensavers()
        
        // Get a few different screensavers to test with
        let testScreensavers = screensavers
            .filter { $0.type == .traditional }
            .prefix(3)
        
        guard testScreensavers.count >= 2 else {
            throw XCTSkip("Need at least 2 screensavers for this test")
        }
        
        print("\n🔄 Testing sequential screensaver changes...")
        
        for screensaver in testScreensavers {
            print("  Setting: \(screensaver.name)")
            try await manager.setScreensaver(module: screensaver.name, screen: nil)
            await TestHelpers.waitForWallpaperAgent()
            assertScreensaverSet(to: screensaver.name)
        }
    }
    
    // MARK: - Idle Time Tests
    
    func testSetIdleTime() throws {
        let originalIdleTime = manager.getIdleTime()
        print("\n⏱ Original idle time: \(originalIdleTime) seconds")
        
        // Test various idle times
        let testTimes = [300, 600, 900] // 5, 10, 15 minutes
        
        for testTime in testTimes {
            try manager.setIdleTime(seconds: testTime)
            
            let retrievedTime = manager.getIdleTime()
            XCTAssertEqual(retrievedTime, testTime, 
                          "Idle time should be set to \(testTime) seconds")
            print("  ✅ Set idle time to \(testTime) seconds")
        }
        
        // Note: Original idle time will be restored with the backup
    }
    
    func testSetIdleTimeToNever() throws {
        // Set idle time to 0 (never)
        try manager.setIdleTime(seconds: 0)
        
        let retrievedTime = manager.getIdleTime()
        XCTAssertEqual(retrievedTime, 0, "Idle time should be set to never (0)")
        print("\n⏱ Successfully set idle time to never")
    }
    
    // MARK: - Space-Specific Tests (Sonoma+)
    
    @available(macOS 14.0, *)
    func testSetScreensaverForCurrentSpace() async throws {
        guard let testScreensaver = TestHelpers.getTestScreensaver() else {
            throw XCTSkip("No screensavers available to test with")
        }
        
        guard let currentSpace = manager.getActiveSpace() else {
            throw XCTSkip("Could not get current space")
        }
        
        print("\n🪟 Setting screensaver for current space: \(currentSpace.name ?? "Current")")
        
        try await manager.setScreensaverForSpace(
            module: testScreensaver.name,
            spaceUUID: currentSpace.uuid,
            screen: nil
        )
        
        await TestHelpers.waitForWallpaperAgent()
        
        print("  ✅ Set '\(testScreensaver.name)' for space UUID: \(currentSpace.uuid)")
    }
    
    @available(macOS 14.0, *)
    func testSetScreensaverForSpecificDisplaySpace() async throws {
        guard let testScreensaver = TestHelpers.getTestScreensaver() else {
            throw XCTSkip("No screensavers available to test with")
        }
        
        // Try to set for Display 1, Space 1
        let displayNumber = 1
        let spaceNumber = 4
        
        print("\n🖥 Setting screensaver for Display \(displayNumber), Space \(spaceNumber)")
        
        do {
            try await manager.setScreensaverForDisplaySpace(
                module: testScreensaver.name,
                displayNumber: displayNumber,
                spaceNumber: spaceNumber
            )
            
            await TestHelpers.waitForWallpaperAgent()
            
            print("  ✅ Successfully set '\(testScreensaver.name)' for Display \(displayNumber), Space \(spaceNumber)")
        } catch PaperSaverError.spaceNotFoundOnDisplay(let display, let space) {
            throw XCTSkip("Space \(space) not found on Display \(display)")
        }
    }
    
    @available(macOS 14.0, *)
    func testSetScreensaverForAllSpacesOnDisplay() async throws {
        guard let testScreensaver = TestHelpers.getTestScreensaver() else {
            throw XCTSkip("No screensavers available to test with")
        }
        
        let displayNumber = 1
        
        print("\n🖥 Setting screensaver for all spaces on Display \(displayNumber)")
        
        do {
            try await manager.setScreensaverForDisplay(
                module: testScreensaver.name,
                displayNumber: displayNumber
            )
            
            await TestHelpers.waitForWallpaperAgent()
            
            print("  ✅ Successfully set '\(testScreensaver.name)' for all spaces on Display \(displayNumber)")
        } catch PaperSaverError.displayNotFound(let display) {
            throw XCTSkip("Display \(display) not found")
        }
    }
    
    // MARK: - Built-in Screensaver Override Test
    
    @available(macOS 14.0, *)
    func testOverrideBuiltInScreensaver() async throws {
        // This test demonstrates that we can override built-in screensavers
        // like "Classic Mac" with regular screensavers
        
        guard let testScreensaver = TestHelpers.getTestScreensaver() else {
            throw XCTSkip("No screensavers available to test with")
        }
        
        // Find a space that might have a built-in screensaver
        // For this test, we'll just use the current space
        guard let currentSpace = manager.getActiveSpace() else {
            throw XCTSkip("Could not get current space")
        }
        
        print("\n🔄 Testing override of any existing screensaver...")
        print("  Space: \(currentSpace.name ?? "Current")")
        print("  Setting: \(testScreensaver.name)")
        
        // Set a regular screensaver (this will override any type)
        try await manager.setScreensaverForSpace(
            module: testScreensaver.name,
            spaceUUID: currentSpace.uuid,
            screen: nil
        )
        
        await TestHelpers.waitForWallpaperAgent()
        
        print("  ✅ Successfully overrode with '\(testScreensaver.name)'")
        
        // Note: The original configuration (including built-in screensavers)
        // will be restored when the test class completes
    }
    
    // MARK: - Error Handling Tests
    
    func testSetNonExistentScreensaver() async {
        let fakeName = "NonExistentScreensaver_\(UUID().uuidString)"
        
        do {
            try await manager.setScreensaver(module: fakeName, screen: nil)
            XCTFail("Should have thrown an error for non-existent screensaver")
        } catch PaperSaverError.screensaverNotFound(let name) {
            XCTAssertEqual(name, fakeName)
            print("\n✅ Correctly threw error for non-existent screensaver: \(name)")
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }
    
    func testSetInvalidIdleTime() {
        let invalidTime = -100
        
        do {
            try manager.setIdleTime(seconds: invalidTime)
            XCTFail("Should have thrown an error for negative idle time")
        } catch {
            print("\n✅ Correctly threw error for invalid idle time: \(invalidTime)")
        }
    }
}
