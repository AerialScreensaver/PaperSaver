import Foundation

let indexPath = NSString(string: "~/Library/Application Support/com.apple.wallpaper/Store/Index.plist").expandingTildeInPath

guard let plistData = try? Data(contentsOf: URL(fileURLWithPath: indexPath)) else {
    print("Failed to read Index.plist")
    exit(1)
}

guard let plist = try? PropertyListSerialization.propertyList(from: plistData, options: [], format: nil) as? [String: Any] else {
    print("Failed to parse plist")
    exit(1)
}

print("Successfully read Index.plist")

if let displays = plist["Displays"] as? [String: Any] {
    print("\nDisplays found: \(displays.keys.joined(separator: ", "))")
    
    for (displayKey, displayValue) in displays {
        print("\nDisplay: \(displayKey)")
        
        if let displayConfig = displayValue as? [String: Any],
           let idle = displayConfig["Idle"] as? [String: Any],
           let content = idle["Content"] as? [String: Any],
           let choices = content["Choices"] as? [[String: Any]],
           let firstChoice = choices.first {
            
            print("  Has Idle configuration: YES")
            
            if let configData = firstChoice["Configuration"] as? Data {
                print("  Configuration data size: \(configData.count) bytes")
                
                if let configPlist = try? PropertyListSerialization.propertyList(from: configData, options: [], format: nil) as? [String: Any] {
                    print("  Decoded configuration: \(configPlist)")
                    
                    if let module = configPlist["module"] as? [String: Any],
                       let relative = module["relative"] as? String,
                       let url = URL(string: relative) {
                        let moduleName = url.deletingPathExtension().lastPathComponent
                        print("  Screensaver module: \(moduleName)")
                    }
                }
            } else {
                print("  No Configuration data found")
            }
        } else {
            print("  Has Idle configuration: NO")
        }
    }
} else {
    print("No Displays found in plist")
}