#!/usr/bin/env swift

import Foundation

// Extract and decode configuration data from wallpaper plist files
class ConfigExtractor {
    static func main() {
        let args = CommandLine.arguments
        let scriptName = URL(fileURLWithPath: args[0]).lastPathComponent
        
        if args.count < 2 {
            print("Usage: \(scriptName) <plist_file>")
            exit(1)
        }
        
        let plistPath = args[1]
        extractConfigurations(from: plistPath)
    }
    
    static func extractConfigurations(from plistPath: String) {
        do {
            let data = try Data(contentsOf: URL(fileURLWithPath: plistPath))
            let plist = try PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any]
            
            guard let plist = plist else {
                print("❌ Failed to parse plist")
                exit(1)
            }
            
            print("🔍 Extracting configuration data from \(plistPath)")
            print("")
            
            // Extract from Displays section
            if let displays = plist["Displays"] as? [String: Any] {
                for (displayUUID, displayConfig) in displays {
                    print("🖥️ Display \(displayUUID):")
                    if let config = displayConfig as? [String: Any] {
                        extractFromDisplayConfig(config: config)
                    }
                    print("")
                }
            }
            
            // Extract from Spaces section
            if let spaces = plist["Spaces"] as? [String: Any] {
                for (spaceUUID, spaceConfig) in spaces {
                    print("🚀 Space \(spaceUUID):")
                    if let config = spaceConfig as? [String: Any] {
                        extractFromSpaceConfig(config: config)
                    }
                    print("")
                }
            }
            
        } catch {
            print("❌ Error processing plist: \(error)")
            exit(1)
        }
    }
    
    static func extractFromDisplayConfig(config: [String: Any]) {
        if let desktop = config["Desktop"] as? [String: Any] {
            print("  📄 Desktop configuration:")
            extractChoices(from: desktop)
        }
        
        if let idle = config["Idle"] as? [String: Any] {
            print("  💤 Idle configuration:")
            extractChoices(from: idle)
        }
    }
    
    static func extractFromSpaceConfig(config: [String: Any]) {
        if let displays = config["Displays"] as? [String: Any] {
            for (displayUUID, displayConfig) in displays {
                print("  🖥️ Display \(displayUUID) in this space:")
                if let config = displayConfig as? [String: Any] {
                    if let desktop = config["Desktop"] as? [String: Any] {
                        print("    📄 Desktop:")
                        extractChoices(from: desktop)
                    }
                }
            }
        }
        
        if let defaultConfig = config["Default"] as? [String: Any] {
            print("  📄 Default configuration:")
            extractChoices(from: defaultConfig)
        }
    }
    
    static func extractChoices(from config: [String: Any]) {
        guard let content = config["Content"] as? [String: Any],
              let choices = content["Choices"] as? [[String: Any]] else {
            print("    ❌ No choices found")
            return
        }
        
        for (index, choice) in choices.enumerated() {
            print("    Choice \(index + 1):")
            
            if let provider = choice["Provider"] as? String {
                print("      Provider: \(provider)")
            }
            
            if let configData = choice["Configuration"] as? Data {
                print("      Configuration size: \(configData.count) bytes")
                decodeConfigurationData(configData)
            }
        }
        
        // Check EncodedOptionValues
        if let optionsData = content["EncodedOptionValues"] as? Data {
            print("    EncodedOptionValues size: \(optionsData.count) bytes")
            decodeOptionsData(optionsData)
        } else if let optionsString = content["EncodedOptionValues"] as? String {
            print("    EncodedOptionValues: \(optionsString)")
        }
        
        // Check Shuffle
        if let shuffle = content["Shuffle"] {
            print("    Shuffle: \(shuffle) (type: \(type(of: shuffle)))")
        }
    }
    
    static func decodeConfigurationData(_ data: Data) {
        do {
            let config = try PropertyListSerialization.propertyList(from: data, options: [], format: nil)
            print("      📄 Decoded config: \(config)")
        } catch {
            print("      ❌ Failed to decode config: \(error)")
        }
    }
    
    static func decodeOptionsData(_ data: Data) {
        do {
            let options = try PropertyListSerialization.propertyList(from: data, options: [], format: nil)
            print("    📄 Decoded options: \(options)")
        } catch {
            print("    ❌ Failed to decode options: \(error)")
        }
    }
}

ConfigExtractor.main()