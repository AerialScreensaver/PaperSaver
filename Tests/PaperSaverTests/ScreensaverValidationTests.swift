import XCTest
@testable import PaperSaver

/// Validation tests that check our static lists and assumptions against the actual system
/// These tests are useful for detecting when macOS updates add/remove screensavers
final class ScreensaverValidationTests: XCTestCase {
    
    // MARK: - ExtensionKit Screensaver List Validation
    
    func testExtensionKitScreensaverListIsUpToDate() throws {
        print("\n🔍 Validating ExtensionKit screensaver list...")
        
        let extensionKitPath = "/System/Library/ExtensionKit/Extensions"
        let fileManager = FileManager.default
        
        guard fileManager.fileExists(atPath: extensionKitPath) else {
            print("⚠️ ExtensionKit directory not found - skipping validation")
            throw XCTSkip("ExtensionKit directory not found on this system")
        }
        
        // Discover actual screensavers in ExtensionKit
        let actualScreensavers = try discoverExtensionKitScreensavers()
        
        // Our static list (from ScreensaverManager)
        let staticList = [
            "Album Artwork",
            "Arabesque",
            "Computer Name",
            "Drift",
            "Flurry",
            "Hello",
            "iLifeSlideshows",
            "Monterey",
            "Shell",
            "Ventura",
            "Word of the Day"
        ]
        
        // Compare
        let actualSet = Set(actualScreensavers)
        let staticSet = Set(staticList)
        
        let missing = actualSet.subtracting(staticSet)
        let extra = staticSet.subtracting(actualSet)
        
        // Report findings
        print("\n📊 Validation Results:")
        print("  Actual screensavers found: \(actualScreensavers.count)")
        print("  Static list count: \(staticList.count)")
        
        if !missing.isEmpty {
            print("\n⚠️ NEW screensavers not in static list:")
            for name in missing.sorted() {
                print("    - \(name)")
            }
            print("\n  👉 Run: swift Scripts/update-screensaver-list.swift")
        }
        
        if !extra.isEmpty {
            print("\n⚠️ REMOVED screensavers still in static list:")
            for name in extra.sorted() {
                print("    - \(name)")
            }
        }
        
        if missing.isEmpty && extra.isEmpty {
            print("\n✅ Static list is up to date!")
        } else {
            XCTFail("""
                Static screensaver list is out of date.
                Missing: \(missing.sorted())
                Extra: \(extra.sorted())
                Run: swift Scripts/update-screensaver-list.swift
                """)
        }
    }
    
    // MARK: - Provider Type Validation
    
    func testKnownProviderTypesExist() throws {
        print("\n🔍 Validating provider types...")
        
        let plistManager = PlistManager.shared
        
        // Try to read the wallpaper index to find actual providers
        guard let plist = try? plistManager.read(at: SystemPaths.wallpaperIndexPath),
              let spaces = plist["Spaces"] as? [String: Any] else {
            throw XCTSkip("Could not read wallpaper index plist")
        }
        
        var foundProviders = Set<String>()
        
        // Scan all spaces for provider types
        for (_, spaceValue) in spaces {
            guard let spaceConfig = spaceValue as? [String: Any] else { continue }
            
            for (_, displayValue) in spaceConfig {
                guard let displayConfig = displayValue as? [String: Any],
                      let idle = displayConfig["Idle"] as? [String: Any],
                      let content = idle["Content"] as? [String: Any],
                      let choices = content["Choices"] as? [[String: Any]] else {
                    continue
                }
                
                for choice in choices {
                    if let provider = choice["Provider"] as? String {
                        foundProviders.insert(provider)
                    }
                }
            }
        }
        
        print("\n📊 Found providers in system:")
        for provider in foundProviders.sorted() {
            print("  - \(provider)")
            
            // Check if we handle this provider
            let handled = isProviderHandled(provider)
            if !handled {
                print("    ⚠️ Not handled in our code!")
            }
        }
        
        // Verify all our known providers
        let knownProviders = [
            "com.apple.wallpaper.choice.screen-saver",
            "com.apple.NeptuneOneExtension",
            "com.apple.wallpaper.choice.sequoia",
            "com.apple.wallpaper.choice.macintosh",
            "default"
        ]
        
        print("\n✅ Known providers we handle:")
        for provider in knownProviders {
            print("  - \(provider)")
        }
    }
    
    // MARK: - Screensaver File Validation
    
    func testAllListedScreensaversExist() {
        print("\n🔍 Validating screensaver files exist...")
        
        let manager = ScreensaverManager()
        let screensavers = manager.listAvailableScreensavers()
        
        var missingFiles: [String] = []
        var validFiles = 0
        
        for screensaver in screensavers {
            if FileManager.default.fileExists(atPath: screensaver.path.path) {
                validFiles += 1
            } else {
                missingFiles.append("\(screensaver.name) at \(screensaver.path.path)")
            }
        }
        
        print("\n📊 File validation results:")
        print("  Valid files: \(validFiles)")
        print("  Missing files: \(missingFiles.count)")
        
        if !missingFiles.isEmpty {
            print("\n⚠️ Missing screensaver files:")
            for file in missingFiles {
                print("    - \(file)")
            }
            XCTFail("\(missingFiles.count) screensaver files are missing")
        } else {
            print("\n✅ All \(validFiles) screensaver files exist!")
        }
    }
    
    // MARK: - Directory Permission Validation
    
    func testScreensaverDirectoryPermissions() {
        print("\n🔍 Validating directory permissions...")
        
        // Common screensaver directories to check
        let directories = [
            "/System/Library/Screen Savers",
            "/Library/Screen Savers",
            NSHomeDirectory() + "/Library/Screen Savers",
            "/System/Library/ExtensionKit/Extensions"
        ]
        
        for directory in directories {
            let exists = FileManager.default.fileExists(atPath: directory)
            let readable = FileManager.default.isReadableFile(atPath: directory)
            print("\n📁 \(directory)")
            print("   Exists: \(exists ? "✅" : "❌")")
            if exists {
                print("   Readable: \(readable ? "✅" : "❌")")
            }
            
            if !readable && directory.contains("/System/") {
                // System directories might not be readable in newer macOS versions
                print("   Note: System directory may have restricted access")
            }
        }
    }
    
    // MARK: - Configuration Format Validation
    
    func testScreensaverConfigurationFormats() throws {
        print("\n🔍 Validating configuration formats...")
        
        let plistManager = PlistManager.shared
        
        // Test that we can encode/decode each type
        let testCases: [(URL, ScreensaverType, String)] = [
            (URL(string: "file:///Test.saver")!, .traditional, "Test"),
            (URL(string: "file:///Test.appex")!, .appExtension, "Test"),
        ]
        
        for (url, type, expectedName) in testCases {
            print("\n Testing \(type.displayName):")
            
            // Encode
            let data = try plistManager.createScreensaverConfiguration(
                moduleURL: url,
                type: type
            )
            
            // Decode
            let result = try plistManager.decodeScreensaverConfigurationWithType(from: data)
            
            print("   Encoded size: \(data.count) bytes")
            print("   Decoded name: \(result.name ?? "nil")")
            print("   Decoded type: \(result.type.displayName)")
            
            if type == .traditional {
                XCTAssertEqual(result.name, expectedName,
                              "\(type.displayName) should decode to correct name")
            }
            XCTAssertEqual(result.type, type,
                          "\(type.displayName) should decode to correct type")
        }
        
        print("\n✅ All configuration formats validated!")
    }
    
    // MARK: - Helper Methods
    
    private func discoverExtensionKitScreensavers() throws -> [String] {
        let extensionKitPath = "/System/Library/ExtensionKit/Extensions"
        let fileManager = FileManager.default
        
        guard let contents = try? fileManager.contentsOfDirectory(atPath: extensionKitPath) else {
            throw XCTSkip("Could not read ExtensionKit directory")
        }
        
        var screensavers: [String] = []
        
        for item in contents {
            guard item.hasSuffix(".appex") else { continue }
            
            let appexPath = "\(extensionKitPath)/\(item)"
            let infoPlistPath = "\(appexPath)/Contents/Info.plist"
            
            // Check if Info.plist exists and read it
            guard fileManager.fileExists(atPath: infoPlistPath),
                  let plistData = try? Data(contentsOf: URL(fileURLWithPath: infoPlistPath)),
                  let plist = try? PropertyListSerialization.propertyList(
                    from: plistData,
                    options: [],
                    format: nil
                  ) as? [String: Any] else {
                continue
            }
            
            // Check if this is a screensaver extension
            if let nsExtension = plist["NSExtension"] as? [String: Any],
               let pointIdentifier = nsExtension["NSExtensionPointIdentifier"] as? String,
               pointIdentifier == "com.apple.screensaver" {
                
                let name = String(item.dropLast(6)) // Remove .appex
                screensavers.append(name)
            }
        }
        
        return screensavers.sorted()
    }
    
    private func isProviderHandled(_ provider: String) -> Bool {
        // Check if we handle this provider in our code
        switch provider {
        case "com.apple.wallpaper.choice.screen-saver",
             "com.apple.NeptuneOneExtension",
             "com.apple.wallpaper.choice.sequoia",
             "com.apple.wallpaper.choice.macintosh",
             "com.apple.wallpaper.choice.image",
             "com.apple.wallpaper.choice.dynamic",
             "default":
            return true
        default:
            return false
        }
    }
}