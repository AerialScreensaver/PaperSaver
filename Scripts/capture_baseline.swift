#!/usr/bin/env swift

import Foundation

// Simple baseline capture script to save working wallpaper configurations
class BaselineCapture {
    static let wallpaperIndexPath = "/Users/\(NSUserName())/Library/Application Support/com.apple.wallpaper/Store/Index.plist"
    
    static func main() {
        let args = CommandLine.arguments
        let scriptName = URL(fileURLWithPath: args[0]).lastPathComponent
        
        if args.count < 2 {
            print("Usage: \(scriptName) <label>")
            print("Example: \(scriptName) system-ui-baseline")
            exit(1)
        }
        
        let label = args[1]
        captureBaseline(label: label)
    }
    
    static func captureBaseline(label: String) {
        let timestamp = DateFormatter().then {
            $0.dateFormat = "yyyy-MM-dd-HH-mm-ss"
        }.string(from: Date())
        
        let outputPath = "baseline-\(label)-\(timestamp).plist"
        
        guard FileManager.default.fileExists(atPath: wallpaperIndexPath) else {
            print("❌ Wallpaper Index.plist not found at: \(wallpaperIndexPath)")
            exit(1)
        }
        
        do {
            // Copy the plist file
            try FileManager.default.copyItem(atPath: wallpaperIndexPath, toPath: outputPath)
            print("✅ Captured baseline to: \(outputPath)")
            
            // Also create a readable version
            let readableOutputPath = "baseline-\(label)-\(timestamp)-readable.plist"
            if let data = FileManager.default.contents(atPath: wallpaperIndexPath) {
                let plist = try PropertyListSerialization.propertyList(from: data, options: [], format: nil)
                let readableData = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
                try readableData.write(to: URL(fileURLWithPath: readableOutputPath))
                print("✅ Created readable version: \(readableOutputPath)")
            }
            
            // Extract and display current configuration summary
            analyzeCurrent()
            
        } catch {
            print("❌ Error capturing baseline: \(error)")
            exit(1)
        }
    }
    
    static func analyzeCurrent() {
        print("\n📊 Current Configuration Analysis:")
        
        do {
            let data = try Data(contentsOf: URL(fileURLWithPath: wallpaperIndexPath))
            let plist = try PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any]
            
            // Show top-level structure
            print("Top-level keys: \(plist?.keys.sorted() ?? [])")
            
            // Show Displays info
            if let displays = plist?["Displays"] as? [String: Any] {
                print("Displays count: \(displays.count)")
                for (uuid, _) in displays {
                    print("  Display UUID: \(uuid)")
                }
            }
            
            // Show Spaces info
            if let spaces = plist?["Spaces"] as? [String: Any] {
                print("Spaces count: \(spaces.count)")
                for (uuid, config) in spaces {
                    print("  Space UUID: \(uuid)")
                    if let spaceConfig = config as? [String: Any],
                       let displays = spaceConfig["Displays"] as? [String: Any] {
                        print("    Has display configs: \(displays.count)")
                    }
                }
            }
            
        } catch {
            print("❌ Error analyzing current config: \(error)")
        }
    }
}

extension DateFormatter {
    func then(_ closure: (DateFormatter) -> Void) -> DateFormatter {
        closure(self)
        return self
    }
}

BaselineCapture.main()