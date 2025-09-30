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
    
    
    
}

/// XCTestCase extension for easier backup/restore in tests
extension XCTestCase {
    
    
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