#!/usr/bin/env swift

import Foundation

// Analyze the exact wallpaper configuration structure differences
class WallpaperStructureAnalyzer {
    static let wallpaperIndexPath = "/Users/\(NSUserName())/Library/Application Support/com.apple.wallpaper/Store/Index.plist"
    
    static func main() {
        if CommandLine.arguments.count > 1 {
            let command = CommandLine.arguments[1]
            switch command {
            case "extract-working":
                extractWorkingConfigurations()
            case "create-test":
                createTestConfiguration()
            case "compare":
                compareConfigurations()
            default:
                printUsage()
            }
        } else {
            printUsage()
        }
    }
    
    static func printUsage() {
        print("Usage: analyze_wallpaper_structure.swift <command>")
        print("Commands:")
        print("  extract-working  - Extract working wallpaper configurations")
        print("  create-test      - Create our test configuration")
        print("  compare          - Compare working vs test configurations")
    }
    
    static func extractWorkingConfigurations() {
        do {
            let data = try Data(contentsOf: URL(fileURLWithPath: wallpaperIndexPath))
            let plist = try PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any]
            
            guard let plist = plist else {
                print("❌ Failed to parse plist")
                return
            }
            
            print("🔍 Extracting working wallpaper configurations...")
            
            // Look for image-based wallpapers (not dynamic ones)
            if let spaces = plist["Spaces"] as? [String: Any] {
                for (spaceUUID, spaceConfig) in spaces {
                    if let config = spaceConfig as? [String: Any],
                       let displays = config["Displays"] as? [String: Any] {
                        
                        for (displayUUID, displayConfig) in displays {
                            if let displayDict = displayConfig as? [String: Any],
                               let desktop = displayDict["Desktop"] as? [String: Any],
                               let content = desktop["Content"] as? [String: Any],
                               let choices = content["Choices"] as? [[String: Any]],
                               let firstChoice = choices.first,
                               let provider = firstChoice["Provider"] as? String,
                               provider == "com.apple.wallpaper.choice.image" {
                                
                                print("📄 Found image wallpaper in Space \(spaceUUID), Display \(displayUUID):")
                                
                                if let configData = firstChoice["Configuration"] as? Data {
                                    do {
                                        let config = try PropertyListSerialization.propertyList(from: configData, options: [], format: nil)
                                        print("  Configuration: \(config)")
                                        
                                        // Save this working configuration
                                        let filename = "working-config-\(spaceUUID)-\(displayUUID).plist"
                                        let workingData = try PropertyListSerialization.data(fromPropertyList: config, format: .xml, options: 0)
                                        try workingData.write(to: URL(fileURLWithPath: filename))
                                        print("  ✅ Saved to \(filename)")
                                        
                                    } catch {
                                        print("  ❌ Failed to decode: \(error)")
                                    }
                                }
                                
                                if let optionsData = content["EncodedOptionValues"] as? Data {
                                    do {
                                        let options = try PropertyListSerialization.propertyList(from: optionsData, options: [], format: nil)
                                        print("  Options: \(options)")
                                        
                                        // Save working options
                                        let filename = "working-options-\(spaceUUID)-\(displayUUID).plist"
                                        let workingData = try PropertyListSerialization.data(fromPropertyList: options, format: .xml, options: 0)
                                        try workingData.write(to: URL(fileURLWithPath: filename))
                                        print("  ✅ Saved options to \(filename)")
                                        
                                    } catch {
                                        print("  ❌ Failed to decode options: \(error)")
                                    }
                                }
                                
                                print("  Files: \(firstChoice["Files"] ?? "none")")
                                print("  Provider: \(provider)")
                                print("")
                            }
                        }
                    }
                }
            }
            
        } catch {
            print("❌ Error: \(error)")
        }
    }
    
    static func createTestConfiguration() {
        print("🧪 Creating test configuration...")
        
        let testImageURL = URL(fileURLWithPath: "/Users/Shared/test.jpg")
        
        // Create our configuration exactly as PaperSaver does
        let wallpaperConfig: [String: Any] = [
            "type": "imageFile",
            "url": [
                "relative": testImageURL.absoluteString
            ]
        ]
        
        let optionsConfig: [String: Any] = [
            "values": [
                "style": [
                    "picker": [
                        "_0": [
                            "id": "fill"
                        ]
                    ]
                ]
            ]
        ]
        
        do {
            // Save test configuration
            let configData = try PropertyListSerialization.data(fromPropertyList: wallpaperConfig, format: .xml, options: 0)
            try configData.write(to: URL(fileURLWithPath: "test-config.plist"))
            print("✅ Test configuration saved to test-config.plist")
            print("  \(wallpaperConfig)")
            
            // Save test options
            let optionsData = try PropertyListSerialization.data(fromPropertyList: optionsConfig, format: .xml, options: 0)
            try optionsData.write(to: URL(fileURLWithPath: "test-options.plist"))
            print("✅ Test options saved to test-options.plist")
            print("  \(optionsConfig)")
            
        } catch {
            print("❌ Error creating test config: \(error)")
        }
    }
    
    static func compareConfigurations() {
        print("🔍 Comparing configurations...")
        
        // This would compare working vs test configurations
        // Implementation depends on having both files available
        let workingFiles = try? FileManager.default.contentsOfDirectory(atPath: ".").filter { $0.hasPrefix("working-config-") }
        let testFiles = ["test-config.plist"]
        
        if let workingFiles = workingFiles, !workingFiles.isEmpty {
            print("Working configs found: \(workingFiles)")
            print("Test configs: \(testFiles)")
            
            // Compare first working config with test config
            if let firstWorking = workingFiles.first {
                compareFiles(working: firstWorking, test: "test-config.plist")
            }
        } else {
            print("❌ No working configurations found. Run 'extract-working' first.")
        }
    }
    
    static func compareFiles(working: String, test: String) {
        do {
            let workingData = try Data(contentsOf: URL(fileURLWithPath: working))
            let testData = try Data(contentsOf: URL(fileURLWithPath: test))
            
            let workingPlist = try PropertyListSerialization.propertyList(from: workingData, options: [], format: nil) as? [String: Any]
            let testPlist = try PropertyListSerialization.propertyList(from: testData, options: [], format: nil) as? [String: Any]
            
            print("📊 Comparison:")
            print("Working: \(workingPlist ?? [:])")
            print("Test: \(testPlist ?? [:])")
            
        } catch {
            print("❌ Error comparing: \(error)")
        }
    }
}

WallpaperStructureAnalyzer.main()