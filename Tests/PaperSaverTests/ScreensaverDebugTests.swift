import XCTest
@testable import PaperSaver

/// Debug and analysis tests - not meant to be run automatically
/// These tests are for debugging and exploring the system
/// Mark them with XCTSkip or use test plans to exclude from regular runs
final class ScreensaverDebugTests: XCTestCase {
    
    // Skip these tests by default
    override func invokeTest() {
        // Only run if explicitly requested via environment variable
        if ProcessInfo.processInfo.environment["RUN_DEBUG_TESTS"] != "1" {
            print("ℹ️ Skipping debug tests. Set RUN_DEBUG_TESTS=1 to run them.")
            return
        }
        super.invokeTest()
    }
    
    // MARK: - Plist Structure Analysis
    
    @available(macOS 14.0, *)
    func testAnalyzePlistStructure() throws {
        print("\n🔬 === ANALYZING PLIST STRUCTURE ===")
        
        let plistManager = PlistManager.shared
        let indexPath = SystemPaths.wallpaperIndexPath
        
        guard let plist = try? plistManager.read(at: indexPath) else {
            XCTFail("Could not read wallpaper index plist")
            return
        }
        
        print("\n📋 Top-level keys:")
        for key in plist.keys.sorted() {
            let value = plist[key]
            let type = String(describing: type(of: value))
            print("  - \(key): \(type)")
        }
        
        // Analyze Spaces structure
        if let spaces = plist["Spaces"] as? [String: Any] {
            print("\n🪟 Spaces structure:")
            print("  Total spaces: \(spaces.count)")
            
            // Sample first few spaces
            for (index, (uuid, value)) in spaces.enumerated().prefix(3) {
                print("\n  Space \(index + 1):")
                print("    UUID: \(uuid.isEmpty ? "(empty)" : uuid)")
                
                if let spaceConfig = value as? [String: Any] {
                    print("    Keys: \(spaceConfig.keys.sorted())")
                    
                    // Check display configuration
                    let displayCount = spaceConfig.compactMap { _, v in
                        v as? [String: Any]
                    }.count
                    print("    Display configs: \(displayCount)")
                }
            }
        }
        
        // Analyze Displays structure
        if let displays = plist["Displays"] as? [String: Any] {
            print("\n🖥 Displays structure:")
            print("  Total displays: \(displays.count)")
            
            for (uuid, value) in displays.prefix(3) {
                print("\n  Display UUID: \(uuid)")
                if let displayConfig = value as? [String: Any] {
                    print("    Keys: \(displayConfig.keys.sorted())")
                }
            }
        }
    }
    
    // MARK: - New Format Analysis
    
    @available(macOS 14.0, *)
    func testAnalyzeNewScreensaverFormats() throws {
        print("\n🔬 === ANALYZING NEW SCREENSAVER FORMATS ===")
        
        let plistManager = PlistManager.shared
        
        guard let plist = try? plistManager.read(at: SystemPaths.wallpaperIndexPath),
              let spaces = plist["Spaces"] as? [String: Any] else {
            XCTFail("Could not read plist")
            return
        }
        
        // Collect all unique provider types and their configurations
        var providerAnalysis: [String: [(config: Data, displayUUID: String, spaceUUID: String)]] = [:]
        
        for (spaceUUID, spaceValue) in spaces {
            guard let spaceConfig = spaceValue as? [String: Any] else { continue }
            
            for (displayKey, displayValue) in spaceConfig {
                guard let displayConfig = displayValue as? [String: Any],
                      let idle = displayConfig["Idle"] as? [String: Any],
                      let content = idle["Content"] as? [String: Any],
                      let choices = content["Choices"] as? [[String: Any]],
                      let firstChoice = choices.first,
                      let provider = firstChoice["Provider"] as? String else {
                    continue
                }
                
                let configData = firstChoice["Configuration"] as? Data ?? Data()
                
                if providerAnalysis[provider] == nil {
                    providerAnalysis[provider] = []
                }
                
                providerAnalysis[provider]?.append(
                    (config: configData, displayUUID: displayKey, spaceUUID: spaceUUID)
                )
            }
        }
        
        // Analyze each provider type
        print("\n📊 Provider Analysis:")
        for (provider, instances) in providerAnalysis.sorted(by: { $0.key < $1.key }) {
            print("\n🔸 Provider: \(provider)")
            print("   Instances: \(instances.count)")
            
            // Analyze first instance
            if let first = instances.first {
                print("   Config size: \(first.config.count) bytes")
                
                if first.config.count > 0 {
                    if let configPlist = try? plistManager.readBinaryPlist(from: first.config) {
                        print("   Config structure:")
                        for (key, value) in configPlist.prefix(5) {
                            let valueType = String(describing: type(of: value))
                            print("     - \(key): \(valueType)")
                            
                            // Show nested structure for dictionaries
                            if let dict = value as? [String: Any] {
                                for (subKey, _) in dict.prefix(3) {
                                    print("       • \(subKey)")
                                }
                            }
                        }
                    }
                } else {
                    print("   Config: (empty)")
                }
            }
            
            // Show which screensaver type this maps to
            if let type = mapProviderToType(provider) {
                print("   Maps to: \(type.displayName)")
            } else {
                print("   ⚠️ Unknown provider type!")
            }
        }
    }
    
    // MARK: - Space Configuration Deep Dive
    
    @available(macOS 14.0, *)
    func testDeepDiveSpaceConfiguration() throws {
        print("\n🔬 === DEEP DIVE: SPACE CONFIGURATION ===")
        
        let manager = ScreensaverManager()
        let plistManager = PlistManager.shared
        
        // Get current space
        guard let currentSpace = manager.getActiveSpace() else {
            print("Could not get current space")
            return
        }
        
        print("\n📍 Current Space:")
        print("  UUID: \(currentSpace.uuid)")
        print("  Name: \(currentSpace.name ?? "unnamed")")
        
        // Read its configuration
        guard let plist = try? plistManager.read(at: SystemPaths.wallpaperIndexPath),
              let spaces = plist["Spaces"] as? [String: Any],
              let spaceConfig = spaces[currentSpace.uuid] as? [String: Any] else {
            print("  ❌ Could not read configuration")
            return
        }
        
        print("\n📋 Configuration:")
        for (displayUUID, displayValue) in spaceConfig {
            print("\n  Display: \(displayUUID)")
            
            guard let displayConfig = displayValue as? [String: Any] else {
                print("    Invalid config")
                continue
            }
            
            // Desktop configuration
            if let desktop = displayConfig["Desktop"] as? [String: Any],
               let content = desktop["Content"] as? [String: Any],
               let choices = content["Choices"] as? [[String: Any]],
               let first = choices.first {
                print("    Desktop provider: \(first["Provider"] ?? "unknown")")
            }
            
            // Idle (screensaver) configuration
            if let idle = displayConfig["Idle"] as? [String: Any],
               let content = idle["Content"] as? [String: Any],
               let choices = content["Choices"] as? [[String: Any]],
               let first = choices.first {
                
                print("    Screensaver provider: \(first["Provider"] ?? "unknown")")
                
                if let configData = first["Configuration"] as? Data {
                    print("    Config size: \(configData.count) bytes")
                    
                    // Try to decode
                    if let (name, type) = try? plistManager.decodeScreensaverConfigurationWithType(from: configData) {
                        print("    Decoded: \(name ?? "unknown") (\(type.displayName))")
                    }
                }
                
                if let files = first["Files"] as? [String], !files.isEmpty {
                    print("    Files: \(files.count) file(s)")
                }
            }
        }
    }
    
    // MARK: - Performance Testing
    
    func testScreensaverListingPerformance() {
        print("\n⚡ === PERFORMANCE TEST: SCREENSAVER LISTING ===")
        
        let manager = ScreensaverManager()
        
        measure {
            _ = manager.listAvailableScreensavers()
        }
        
        // Also measure with multiple iterations
        let iterations = 100
        let start = Date()
        
        for _ in 0..<iterations {
            _ = manager.listAvailableScreensavers()
        }
        
        let elapsed = Date().timeIntervalSince(start)
        let average = elapsed / Double(iterations)
        
        print("\n📊 Performance Results:")
        print("  Total time for \(iterations) iterations: \(String(format: "%.3f", elapsed))s")
        print("  Average per call: \(String(format: "%.3f", average * 1000))ms")
    }
    
    // MARK: - System State Dump
    
    func testDumpSystemState() {
        print("\n📸 === SYSTEM STATE DUMP ===")
        print("  Date: \(Date())")
        print("  macOS Version: \(ProcessInfo.processInfo.operatingSystemVersionString)")
        
        let manager = ScreensaverManager()
        
        // Current screensaver
        if let current = manager.getActiveScreensaver(for: nil) {
            print("\n🎬 Current Screensaver:")
            print("  Name: \(current.name)")
            print("  Screen: \(current.screen?.displayID ?? 0)")
        }
        
        // Idle time
        print("\n⏱ Idle Time: \(manager.getIdleTime()) seconds")
        
        // Available screensavers summary
        let screensavers = manager.listAvailableScreensavers()
        let byType = Dictionary(grouping: screensavers, by: { $0.type })
        
        print("\n📦 Available Screensavers:")
        for type in ScreensaverType.allCases {
            let count = byType[type]?.count ?? 0
            if count > 0 {
                print("  \(type.displayName): \(count)")
            }
        }
        
        // Spaces (if available)
        if #available(macOS 14.0, *) {
            let spaces = manager.listSpaces()
            print("\n🪟 Spaces: \(spaces.count)")
            
            let displays = manager.listDisplays()
            let connected = displays.filter { $0.isConnected }
            print("🖥 Displays: \(connected.count) connected, \(displays.count) total")
        }
    }
    
    // MARK: - Helper Methods
    
    private func mapProviderToType(_ provider: String) -> ScreensaverType? {
        switch provider {
        case "com.apple.wallpaper.choice.screen-saver":
            return .traditional
        case "com.apple.NeptuneOneExtension":
            return .appExtension
        case "com.apple.wallpaper.choice.sequoia":
            return .sequoiaVideo
        case "com.apple.wallpaper.choice.macintosh":
            return .builtInMac
        case "default":
            return .defaultScreen
        default:
            return nil
        }
    }
}