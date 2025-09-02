import XCTest
@testable import PaperSaver

/// Tests that only read system state without modifying it
/// These tests don't require backup/restore
final class ScreensaverManagerReadOnlyTests: XCTestCase {
    
    private var manager: ScreensaverManager!
    
    override func setUp() {
        super.setUp()
        manager = ScreensaverManager()
    }
    
    override func tearDown() {
        manager = nil
        super.tearDown()
    }
    
    // MARK: - Listing Tests
    
    func testListAvailableScreensavers() {
        let screensavers = manager.listAvailableScreensavers()
        
        XCTAssertFalse(screensavers.isEmpty, "Should find at least one screensaver")
        
        // Verify basic properties
        for saver in screensavers {
            XCTAssertFalse(saver.name.isEmpty, "Screensaver name should not be empty")
            XCTAssertFalse(saver.identifier.isEmpty, "Screensaver identifier should not be empty")
            XCTAssertTrue(FileManager.default.fileExists(atPath: saver.path.path),
                         "Screensaver file should exist at path: \(saver.path.path)")
        }
        
        print("\n📋 Found \(screensavers.count) screensavers")
    }
    
    func testListScreensaversByType() {
        let screensavers = manager.listAvailableScreensavers()
        let groupedByType = Dictionary(grouping: screensavers, by: { $0.type })
        
        print("\n📊 Screensavers by type:")
        for type in ScreensaverType.allCases {
            let count = groupedByType[type]?.count ?? 0
            if count > 0 {
                print("  \(type.displayName): \(count)")
            }
        }
        
        // At minimum, we should have traditional screensavers
        let traditionalCount = groupedByType[.traditional]?.count ?? 0
        XCTAssertGreaterThan(traditionalCount, 0, "Should have at least one traditional screensaver")
    }
    
    func testSystemVsUserScreensavers() {
        let screensavers = manager.listAvailableScreensavers()
        let systemScreensavers = screensavers.filter { $0.isSystem }
        let userScreensavers = screensavers.filter { !$0.isSystem }
        
        print("\n🖥 System screensavers: \(systemScreensavers.count)")
        print("👤 User screensavers: \(userScreensavers.count)")
        
        // System should have at least some screensavers
        XCTAssertGreaterThan(systemScreensavers.count, 0, "Should have at least one system screensaver")
    }
    
    // MARK: - Current State Tests
    
    func testGetCurrentScreensaver() {
        if let current = manager.getActiveScreensaver(for: nil) {
            print("\n🎬 Current screensaver: \(current.name)")
            XCTAssertFalse(current.name.isEmpty, "Screensaver name should not be empty")
            
            // Verify it exists in the list of available screensavers
            let available = manager.listAvailableScreensavers()
            let exists = available.contains { $0.name == current.name }
            XCTAssertTrue(exists, "Current screensaver should be in available list")
        } else {
            print("\n⚠️ No screensaver currently set")
        }
    }
    
    func testGetIdleTime() {
        let idleTime = manager.getIdleTime()
        
        print("\n⏱ Current idle time: \(formatIdleTime(idleTime))")
        XCTAssertGreaterThanOrEqual(idleTime, 0, "Idle time should be non-negative")
        
        // Typical values are between 60 seconds and 1 hour
        if idleTime > 0 {
            XCTAssertGreaterThanOrEqual(idleTime, 60, "Idle time is typically at least 1 minute")
            XCTAssertLessThanOrEqual(idleTime, 3600 * 24, "Idle time is typically less than 24 hours")
        }
    }
    
    // MARK: - Space Tests (Sonoma+)
    
    @available(macOS 14.0, *)
    func testListSpaces() {
        let spaces = manager.listSpaces()
        
        if spaces.isEmpty {
            print("\n⚠️ No spaces found (requires macOS 14.0+)")
        } else {
            print("\n🪟 Found \(spaces.count) spaces")
            
            for space in spaces.prefix(3) {
                print("  Space: \(space.name ?? "Unnamed")")
                print("    UUID: \(space.uuid)")
                print("    Displays: \(space.displayCount)")
            }
        }
    }
    
    @available(macOS 14.0, *)
    func testListDisplays() {
        let displays = manager.listDisplays()
        
        XCTAssertFalse(displays.isEmpty, "Should find at least one display")
        
        let connected = displays.filter { $0.isConnected }
        let historical = displays.filter { !$0.isConnected }
        
        print("\n🖥 Displays:")
        print("  Connected: \(connected.count)")
        print("  Historical: \(historical.count)")
        
        // Should have at least one connected display
        XCTAssertGreaterThan(connected.count, 0, "Should have at least one connected display")
        
        // Verify connected displays have required properties
        for display in connected {
            XCTAssertFalse(display.uuid.isEmpty, "Display UUID should not be empty")
            XCTAssertNotNil(display.displayID, "Connected display should have display ID")
        }
    }
    
    @available(macOS 14.0, *)
    func testGetActiveSpace() {
        guard let activeSpace = manager.getActiveSpace() else {
            print("\n⚠️ Could not get active space")
            return
        }
        
        print("\n📍 Active space:")
        print("  Name: \(activeSpace.name ?? "Current")")
        print("  UUID: \(activeSpace.uuid)")
        print("  Display count: \(activeSpace.displayCount)")
        
        XCTAssertGreaterThan(activeSpace.displayCount, 0, "Active space should have at least one display")
    }
    
    @available(macOS 14.0, *)
    func testGetNativeSpaceTree() {
        let spaceTree = manager.getNativeSpaceTree()
        
        XCTAssertFalse(spaceTree.isEmpty, "Space tree should not be empty")
        
        guard let monitors = spaceTree["monitors"] as? [[String: Any]] else {
            XCTFail("Space tree should have monitors")
            return
        }
        
        print("\n🌳 Space tree:")
        print("  Monitors: \(monitors.count)")
        
        for monitor in monitors {
            if let displayNumber = monitor["display_number"] as? Int,
               let name = monitor["name"] as? String,
               let spaces = monitor["spaces"] as? [[String: Any]] {
                print("  Display \(displayNumber): \(name)")
                print("    Spaces: \(spaces.count)")
            }
        }
        
        XCTAssertGreaterThan(monitors.count, 0, "Should have at least one monitor")
    }
    
    // MARK: - Helper Methods
    
    private func formatIdleTime(_ seconds: Int) -> String {
        if seconds == 0 {
            return "Never"
        } else if seconds < 60 {
            return "\(seconds) seconds"
        } else if seconds < 3600 {
            let minutes = seconds / 60
            return "\(minutes) minute\(minutes == 1 ? "" : "s")"
        } else {
            let hours = seconds / 3600
            let remainingMinutes = (seconds % 3600) / 60
            if remainingMinutes == 0 {
                return "\(hours) hour\(hours == 1 ? "" : "s")"
            } else {
                return "\(hours)h \(remainingMinutes)m"
            }
        }
    }
}