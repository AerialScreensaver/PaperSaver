import XCTest
@testable import PaperSaver

final class ScreensaverManagerTests: XCTestCase {
    
    func testListAvailableScreensavers() {
        let manager = ScreensaverManager()
        let screensavers = manager.listAvailableScreensavers()
        
        XCTAssertFalse(screensavers.isEmpty, "Should find at least one screensaver")
        
        print("\nAvailable screensavers:")
        for saver in screensavers {
            print("  - \(saver.name) (\(saver.isSystem ? "System" : "User"))")
        }
    }
    
    func testGetCurrentScreensaver() {
        let manager = ScreensaverManager()
        
        if let current = manager.getActiveScreensaver(for: nil) {
            print("\nCurrent screensaver: \(current.name)")
            XCTAssertFalse(current.name.isEmpty, "Screensaver name should not be empty")
        } else {
            print("\nNo screensaver currently set")
        }
    }
    
    func testGetIdleTime() {
        let manager = ScreensaverManager()
        let idleTime = manager.getIdleTime()
        
        print("\nCurrent idle time: \(idleTime) seconds")
        XCTAssertGreaterThanOrEqual(idleTime, 0, "Idle time should be non-negative")
    }
    
    func testSetAndGetScreensaver() async throws {
        let manager = ScreensaverManager()
        
        let screensavers = manager.listAvailableScreensavers()
        guard let testScreensaver = screensavers.first(where: { $0.name == "Fliqlo" }) ?? screensavers.first else {
            XCTFail("No screensavers available to test with")
            return
        }
        
        print("\nTesting with screensaver: \(testScreensaver.name)")
        
        try await manager.setScreensaver(module: testScreensaver.name, screen: nil)
        
        try await Task.sleep(nanoseconds: 1_000_000_000)
        
        if let current = manager.getActiveScreensaver(for: nil) {
            print("Successfully set screensaver to: \(current.name)")
            XCTAssertEqual(current.name, testScreensaver.name, "Screensaver should be set to \(testScreensaver.name)")
        } else {
            XCTFail("Could not retrieve current screensaver after setting")
        }
    }
    
    func testSetIdleTime() throws {
        let manager = ScreensaverManager()
        let testIdleTime = 300
        
        try manager.setIdleTime(seconds: testIdleTime)
        
        let retrievedIdleTime = manager.getIdleTime()
        XCTAssertEqual(retrievedIdleTime, testIdleTime, "Idle time should be set to \(testIdleTime) seconds")
        
        print("\nSuccessfully set idle time to \(retrievedIdleTime) seconds")
    }
    
    func testSetSpace() async throws {
        let manager = ScreensaverManager()
        
        let screensavers = manager.listAvailableScreensavers()
        guard let testScreensaver = screensavers.first(where: { $0.name == "ScreenSaverMinimal" }) ?? screensavers.first else {
            XCTFail("No screensavers available to test with")
            return
        }
        
        try await manager.setScreensaverForDisplaySpace(module: testScreensaver.name, displayNumber: 1, spaceNumber: 4)
    }
    
    func testGetScreensaverForSpace() async throws {
        let manager = ScreensaverManager()
        let plistManager = PlistManager.shared
        
        // First, set a screensaver for a specific space
        let screensavers = manager.listAvailableScreensavers()
        guard let testScreensaver = screensavers.first(where: { $0.name == "Aerial" }) ?? screensavers.first else {
            XCTFail("No screensavers available to test with")
            return
        }
        
        print("\n=== Testing Get Screensaver for Space ===")
        
        // Get the space tree to find the UUID
        let spaceTree = manager.getNativeSpaceTree()
        guard let monitors = spaceTree["monitors"] as? [[String: Any]],
              let firstMonitor = monitors.first(where: { ($0["display_number"] as? Int) == 1 }),
              let spaces = firstMonitor["spaces"] as? [[String: Any]],
              let firstSpace = spaces.first(where: { ($0["space_number"] as? Int) == 4 }),
              let spaceUUID = firstSpace["uuid"] as? String else {
            XCTFail("Could not find space UUID for Display 1, Space 4")
            return
        }
        
        print("Found space UUID: '\(spaceUUID)' (length: \(spaceUUID.count))")
        
        // Check if UUID is empty
        if spaceUUID.isEmpty {
            print("⚠️ Warning: Space UUID is empty!")
        }
        
        // Now test retrieving the screensaver for this space
        let indexPath = SystemPaths.wallpaperIndexPath
        guard let plist = try? plistManager.read(at: indexPath) else {
            XCTFail("Could not read wallpaper index plist")
            return
        }
        
        print("\n=== Plist Structure Debug ===")
        
        // Check Spaces structure
        if let spaces = plist["Spaces"] as? [String: Any] {
            print("Spaces has \(spaces.count) entries")
            print("Spaces keys (first 5): \(Array(spaces.keys.sorted().prefix(5)))")
            
            // Check for empty string key
            if spaces[""] != nil {
                print("⚠️ Found entry with empty string key in Spaces!")
            }
            
            // Try both the UUID and empty string as keys
            let keysToTry = [spaceUUID, ""]
            var foundConfig = false
            
            for keyToTry in keysToTry {
                if let spaceConfig = spaces[keyToTry] as? [String: Any] {
                    foundConfig = true
                    print("\n✅ Found config using key: '\(keyToTry)' (empty: \(keyToTry.isEmpty))")
                    print("Top-level keys: \(spaceConfig.keys.sorted())")
                    
                    // Try to navigate to screensaver config
                    for (displayKey, displayValue) in spaceConfig {
                        print("\n  Display key: \(displayKey)")
                        if let displayConfig = displayValue as? [String: Any] {
                            print("    Display config keys: \(displayConfig.keys.sorted())")
                            
                            if let idle = displayConfig["Idle"] as? [String: Any] {
                                print("    Idle config found!")
                                print("      Idle keys: \(idle.keys.sorted())")
                                
                                if let content = idle["Content"] as? [String: Any] {
                                    print("      Content keys: \(content.keys.sorted())")
                                    
                                    if let choices = content["Choices"] as? [[String: Any]] {
                                        print("      Choices count: \(choices.count)")
                                        
                                        if let firstChoice = choices.first {
                                            print("      First choice keys: \(firstChoice.keys.sorted())")
                                            
                                            if let configData = firstChoice["Configuration"] as? Data {
                                                print("      Configuration data size: \(configData.count) bytes")
                                                
                                                if let moduleName = try? plistManager.decodeScreensaverConfiguration(from: configData) {
                                                    print("      ✅ Decoded screensaver: \(moduleName)")
                                                    XCTAssertEqual(moduleName, testScreensaver.name, "Should get the screensaver we just set")
                                                } else {
                                                    print("      ❌ Could not decode configuration data")
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                    break  // Found config, no need to try other keys
                }
            }
            
            if !foundConfig {
                print("\n❌ No config found for space UUID: '\(spaceUUID)'")
                print("Available space UUIDs in Spaces (showing if empty):")
                for uuid in spaces.keys.sorted().prefix(10) {
                    if uuid.isEmpty {
                        print("  - (empty string)")
                    } else {
                        print("  - \(uuid)")
                    }
                }
            }
        } else {
            print("❌ No Spaces key in plist")
            print("Top-level plist keys: \(plist.keys.sorted())")
        }
    }
    
    @available(macOS 14.0, *)
    func testDebugPlistStructure() throws {
        let plistManager = PlistManager.shared
        let indexPath = SystemPaths.wallpaperIndexPath
        
        print("\n=== Debug Plist Structure ===")
        
        guard let plist = try? plistManager.read(at: indexPath) else {
            XCTFail("Could not read wallpaper index plist at: \(indexPath)")
            return
        }
        
        print("Top-level keys in plist:")
        for key in plist.keys.sorted() {
            print("  - \(key)")
        }
        
        // Check Spaces structure
        if let spaces = plist["Spaces"] as? [String: Any] {
            print("\nSpaces has \(spaces.count) entries")
            
            // Sample first space to understand structure
            if let firstSpaceUUID = spaces.keys.first,
               let firstSpace = spaces[firstSpaceUUID] as? [String: Any] {
                print("\nSample space UUID: \(firstSpaceUUID)")
                print("Space config keys: \(firstSpace.keys.sorted())")
                
                // Check if it has display configs
                for (key, value) in firstSpace {
                    if let displayConfig = value as? [String: Any] {
                        print("\n  Display/Key '\(key)' structure:")
                        print("    Keys: \(displayConfig.keys.sorted())")
                    }
                }
            }
        }
        
        // Also check the space tree to compare UUIDs
        let manager = ScreensaverManager()
        let spaceTree = manager.getNativeSpaceTree()
        
        print("\n=== Space Tree UUIDs ===")
        if let monitors = spaceTree["monitors"] as? [[String: Any]] {
            for monitor in monitors {
                if let displayNumber = monitor["display_number"] as? Int,
                   let spaces = monitor["spaces"] as? [[String: Any]] {
                    print("\nDisplay \(displayNumber):")
                    for space in spaces {
                        if let spaceNumber = space["space_number"] as? Int,
                           let uuid = space["uuid"] as? String {
                            print("  Space \(spaceNumber): \(uuid)")
                        }
                    }
                }
            }
        }
    }
}
