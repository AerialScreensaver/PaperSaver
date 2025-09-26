import XCTest
@testable import PaperSaver

/// Pure unit tests that don't interact with system state
final class ScreensaverUnitTests: XCTestCase {
    
    // MARK: - ScreensaverType Enum Tests
    
    func testScreensaverTypeFileExtensions() {
        XCTAssertEqual(ScreensaverType.traditional.fileExtension, "saver")
        XCTAssertEqual(ScreensaverType.appExtension.fileExtension, "appex")
        XCTAssertEqual(ScreensaverType.sequoiaVideo.fileExtension, "")
        XCTAssertEqual(ScreensaverType.builtInMac.fileExtension, "")
        XCTAssertEqual(ScreensaverType.defaultScreen.fileExtension, "")
    }
    
    func testScreensaverTypeProviderIdentifiers() {
        XCTAssertEqual(ScreensaverType.traditional.providerIdentifier,
                      "com.apple.wallpaper.choice.screen-saver")
        XCTAssertEqual(ScreensaverType.appExtension.providerIdentifier,
                      "com.apple.NeptuneOneExtension")
        XCTAssertEqual(ScreensaverType.sequoiaVideo.providerIdentifier,
                      "com.apple.wallpaper.choice.sequoia")
        XCTAssertEqual(ScreensaverType.builtInMac.providerIdentifier,
                      "com.apple.wallpaper.choice.macintosh")
        XCTAssertEqual(ScreensaverType.defaultScreen.providerIdentifier,
                      "default")
    }
    
    func testScreensaverTypeDisplayNames() {
        XCTAssertEqual(ScreensaverType.traditional.displayName, "Screen Saver")
        XCTAssertEqual(ScreensaverType.appExtension.displayName, "App Extension")
        XCTAssertEqual(ScreensaverType.sequoiaVideo.displayName, "Video Screensaver")
        XCTAssertEqual(ScreensaverType.builtInMac.displayName, "Classic Mac")
        XCTAssertEqual(ScreensaverType.defaultScreen.displayName, "Default")
    }
    
    func testScreensaverTypeAllCases() {
        let allCases = ScreensaverType.allCases
        
        XCTAssertEqual(allCases.count, 5)
        XCTAssertTrue(allCases.contains(.traditional))
        XCTAssertTrue(allCases.contains(.appExtension))
        XCTAssertTrue(allCases.contains(.sequoiaVideo))
        XCTAssertTrue(allCases.contains(.builtInMac))
        XCTAssertTrue(allCases.contains(.defaultScreen))
    }
    
    // MARK: - Configuration Encoding/Decoding Tests
    
    func testTraditionalScreensaverConfiguration() throws {
        let plistManager = PlistManager.shared
        let testURL = URL(string: "file:///System/Library/Screen%20Savers/Test.saver")!
        
        // Encode
        let data = try plistManager.createScreensaverConfiguration(
            moduleURL: testURL,
            type: .traditional
        )
        
        XCTAssertGreaterThan(data.count, 0, "Configuration data should not be empty")
        
        // Decode
        let result = try plistManager.decodeScreensaverConfigurationWithType(from: data)
        
        XCTAssertEqual(result.name, "Test")
        XCTAssertEqual(result.type, .traditional)
    }
    
    func testAppExtensionConfiguration() throws {
        let plistManager = PlistManager.shared
        let testURL = URL(string: "file:///System/Library/ExtensionKit/Extensions/Hello.appex")!
        
        // Encode
        let data = try plistManager.createScreensaverConfiguration(
            moduleURL: testURL,
            type: .appExtension
        )
        
        XCTAssertGreaterThan(data.count, 0, "Configuration data should not be empty")
        
        // Decode
        let result = try plistManager.decodeScreensaverConfigurationWithType(from: data)
        
        // App extensions have special handling
        XCTAssertEqual(result.type, .appExtension)
    }
    
    func testBuiltInScreensaverConfiguration() throws {
        let plistManager = PlistManager.shared
        
        // Built-in screensavers have empty configuration
        let data = try plistManager.createScreensaverConfiguration(
            moduleURL: URL(string: "builtin://classic-mac")!,
            type: .builtInMac
        )
        
        XCTAssertEqual(data.count, 0, "Built-in screensaver should have empty configuration")
    }
    
    func testScreensaverTypeDetectionFromURL() throws {
        let plistManager = PlistManager.shared
        
        // Test .saver extension
        let saverURL = URL(string: "file:///Test.saver")!
        let saverData = try plistManager.createScreensaverConfiguration(moduleURL: saverURL)
        let saverResult = try plistManager.decodeScreensaverConfigurationWithType(from: saverData)
        XCTAssertEqual(saverResult.type, .traditional)
        
        // .qtz extension support has been removed (deprecated Quartz Composer)
        
        // Test .appex extension
        let appexURL = URL(string: "file:///Test.appex")!
        let appexData = try plistManager.createScreensaverConfiguration(moduleURL: appexURL)
        let appexResult = try plistManager.decodeScreensaverConfigurationWithType(from: appexData)
        XCTAssertEqual(appexResult.type, .appExtension)
    }
    
    // MARK: - ScreensaverModule Tests
    
    func testScreensaverModuleInitialization() {
        let module = ScreensaverModule(
            name: "TestSaver",
            identifier: "com.test.screensaver",
            path: URL(fileURLWithPath: "/Test.saver"),
            type: .traditional,
            isSystem: true,
            thumbnail: nil
        )
        
        XCTAssertEqual(module.name, "TestSaver")
        XCTAssertEqual(module.identifier, "com.test.screensaver")
        XCTAssertEqual(module.path.lastPathComponent, "Test.saver")
        XCTAssertEqual(module.type, .traditional)
        XCTAssertTrue(module.isSystem)
        XCTAssertNil(module.thumbnail)
    }
    
    func testScreensaverModuleEquality() {
        let module1 = ScreensaverModule(
            name: "Test",
            identifier: "com.test",
            path: URL(fileURLWithPath: "/Test.saver"),
            type: .traditional,
            isSystem: true,
            thumbnail: nil
        )
        
        let module2 = ScreensaverModule(
            name: "Test",
            identifier: "com.test",
            path: URL(fileURLWithPath: "/Test.saver"),
            type: .traditional,
            isSystem: true,
            thumbnail: nil
        )
        
        let module3 = ScreensaverModule(
            name: "Different",
            identifier: "com.different",
            path: URL(fileURLWithPath: "/Different.saver"),
            type: .traditional,
            isSystem: false,
            thumbnail: nil
        )
        
        XCTAssertEqual(module1, module2)
        XCTAssertNotEqual(module1, module3)
    }
    
    // MARK: - Path Validation Tests
    
    func testSystemPathsExist() {
        // Test that expected system paths are correctly defined
        let wallpaperPath = SystemPaths.wallpaperIndexPath
        XCTAssertFalse(wallpaperPath.isEmpty)
        XCTAssertTrue(wallpaperPath.contains("com.apple.wallpaper"))
    }
    
    func testScreensaverDirectoryPaths() {
        let manager = ScreensaverManager()
        let screensavers = manager.listAvailableScreensavers()
        
        // Extract unique directory paths from screensavers
        let directories = Set(screensavers.map { $0.path.deletingLastPathComponent() })
        
        XCTAssertFalse(directories.isEmpty, "Should have screensaver directories")
        
        // Check for common directory patterns
        let hasSystemDir = directories.contains { $0.path.contains("/System/Library") }
        let hasUserDir = directories.contains { $0.path.contains("/Library/Screen Savers") }
        
        XCTAssertTrue(hasSystemDir || hasUserDir, "Should include system or user screensaver directory")
        
        // On newer systems, might include ExtensionKit
        if #available(macOS 14.0, *) {
            let hasExtensionKit = directories.contains { $0.path.contains("ExtensionKit") }
            print("ExtensionKit directory present: \(hasExtensionKit)")
        }
    }
    
    // MARK: - Error Type Tests
    
    func testPaperSaverErrorMessages() {
        let errors: [PaperSaverError] = [
            .screensaverNotFound("TestSaver"),
            .fileNotFound(URL(fileURLWithPath: "/test.plist")),
            .plistReadError("/test.plist"),
            .plistWriteError("/test.plist"),
            .invalidConfiguration("Test config error"),
            .spaceNotFound,
            .displayNotFound(1),
            .spaceNotFoundOnDisplay(displayNumber: 1, spaceNumber: 2)
        ]
        
        for error in errors {
            let description = error.localizedDescription
            XCTAssertFalse(description.isEmpty, "Error should have description")
            print("Error: \(error) - \(description)")
        }
    }
}