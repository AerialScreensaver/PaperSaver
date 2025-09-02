import XCTest
import Foundation
@testable import PaperSaver

/// Helper utilities for PaperSaver tests
enum TestHelpers {
    
    /// Creates a backup of the current wallpaper/screensaver configuration
    /// - Returns: URL of the backup file if successful
    static func createWallpaperBackup() -> URL? {
        let plistManager = PlistManager.shared
        let originalPath = SystemPaths.wallpaperIndexPath
        let backupPath = originalPath + ".test-backup-\(UUID().uuidString)"
        
        // Clean up any existing backup files to avoid conflicts
        let potentialBackupPath = originalPath + ".backup"
        if FileManager.default.fileExists(atPath: potentialBackupPath) {
            try? FileManager.default.removeItem(atPath: potentialBackupPath)
            print("🧹 Cleaned up existing backup file")
        }
        
        do {
            // Use the plistManager's backup method
            let backupURL = try plistManager.backup(at: originalPath)
            // Move to our test-specific location
            let testBackupURL = URL(fileURLWithPath: backupPath)
            try FileManager.default.moveItem(at: backupURL, to: testBackupURL)
            print("✅ Created backup at: \(testBackupURL.lastPathComponent)")
            return testBackupURL
        } catch {
            print("❌ Failed to create backup: \(error)")
            return nil
        }
    }
    
    /// Restores wallpaper/screensaver configuration from a backup
    /// - Parameter backupURL: URL of the backup file to restore
    static func restoreWallpaperBackup(_ backupURL: URL) {
        let plistManager = PlistManager.shared
        let originalPath = SystemPaths.wallpaperIndexPath
        
        do {
            try plistManager.restore(
                backupAt: backupURL.path,
                to: originalPath
            )
            // Clean up the backup file
            try? FileManager.default.removeItem(at: backupURL)
            print("✅ Restored configuration from backup")
        } catch {
            print("❌ Failed to restore backup: \(error)")
        }
    }
    
    /// Creates a lightweight checkpoint of just the screensaver configuration
    /// Useful for tests that only modify screensaver settings
    static func createScreensaverCheckpoint() -> Data? {
        let manager = ScreensaverManager()
        guard let current = manager.getActiveScreensaver(for: nil) else {
            return nil
        }
        
        // Store current screensaver info as JSON
        let checkpoint = [
            "name": current.name,
            "idleTime": manager.getIdleTime()
        ] as [String : Any]
        
        return try? JSONSerialization.data(withJSONObject: checkpoint, options: [])
    }
    
    /// Restores screensaver from a checkpoint
    static func restoreScreensaverCheckpoint(_ checkpoint: Data) async {
        guard let info = try? JSONSerialization.jsonObject(with: checkpoint, options: []) as? [String: Any],
              let name = info["name"] as? String,
              let idleTime = info["idleTime"] as? Int else {
            return
        }
        
        let manager = ScreensaverManager()
        try? await manager.setScreensaver(module: name, screen: nil)
        try? manager.setIdleTime(seconds: idleTime)
    }
    
    /// Waits for wallpaper agent to process changes
    static func waitForWallpaperAgent() async {
        // Give the wallpaper agent time to process changes
        try? await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds
    }
    
    /// Gets a test screensaver that's safe to use for testing
    /// Prefers "Aerial" if available, otherwise returns first available
    static func getTestScreensaver() -> ScreensaverModule? {
        let manager = ScreensaverManager()
        let screensavers = manager.listAvailableScreensavers()
        
        // Prefer Aerial for testing as it's commonly available
        if let aerial = screensavers.first(where: { $0.name == "Aerial" }) {
            return aerial
        }
        
        // Fallback to first available
        return screensavers.first
    }
    
    /// Checks if we're running on macOS 14.0 or later (Sonoma+)
    static var isSonomaOrLater: Bool {
        if #available(macOS 14.0, *) {
            return true
        }
        return false
    }
    
    /// Gets the current space UUID for testing space-specific features
    @available(macOS 14.0, *)
    static func getCurrentSpaceUUID() -> String? {
        let manager = ScreensaverManager()
        return manager.getActiveSpace()?.uuid
    }
    
    /// Finds a specific space by display and space number
    @available(macOS 14.0, *)
    static func findSpace(displayNumber: Int, spaceNumber: Int) -> (uuid: String, id: Int)? {
        let manager = ScreensaverManager()
        let spaceTree = manager.getNativeSpaceTree()
        
        guard let monitors = spaceTree["monitors"] as? [[String: Any]],
              let monitor = monitors.first(where: { ($0["display_number"] as? Int) == displayNumber }),
              let spaces = monitor["spaces"] as? [[String: Any]],
              let space = spaces.first(where: { ($0["space_number"] as? Int) == spaceNumber }),
              let uuid = space["uuid"] as? String,
              let id = space["id"] as? NSNumber else {
            return nil
        }
        
        return (uuid: uuid, id: id.intValue)
    }
}

/// XCTestCase extension for easier backup/restore in tests
extension XCTestCase {
    
    /// Creates a backup and returns a cleanup function to be called in tearDown
    func setupWithBackup() -> (() -> Void)? {
        guard let backupURL = TestHelpers.createWallpaperBackup() else {
            XCTFail("Failed to create backup for test")
            return nil
        }
        
        return {
            TestHelpers.restoreWallpaperBackup(backupURL)
        }
    }
    
    /// Asserts that a screensaver is set correctly
    func assertScreensaverSet(to expectedName: String, file: StaticString = #filePath, line: UInt = #line) {
        let manager = ScreensaverManager()
        guard let current = manager.getActiveScreensaver(for: nil) else {
            XCTFail("No screensaver currently set", file: file, line: line)
            return
        }
        
        XCTAssertEqual(current.name, expectedName, 
                      "Expected screensaver '\(expectedName)' but got '\(current.name)'",
                      file: file, line: line)
    }
}