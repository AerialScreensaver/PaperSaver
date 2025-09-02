#!/usr/bin/env swift

// Script to detect screensaver .appex files in /System/Library/ExtensionKit/Extensions
// Run this script when updating PaperSaver for new macOS versions to refresh the static list
// Usage: swift Scripts/update-screensaver-list.swift

import Foundation

print("🔍 Scanning for screensaver .appex files...")
print(String(repeating: "=", count: 50))

let extensionKitPath = "/System/Library/ExtensionKit/Extensions"
let fileManager = FileManager.default

guard let contents = try? fileManager.contentsOfDirectory(atPath: extensionKitPath) else {
    print("❌ Could not read ExtensionKit directory")
    exit(1)
}

var screensavers: [String] = []

for item in contents {
    guard item.hasSuffix(".appex") else { continue }
    
    let appexPath = "\(extensionKitPath)/\(item)"
    let infoPlistPath = "\(appexPath)/Contents/Info.plist"
    
    // Check if Info.plist exists
    guard fileManager.fileExists(atPath: infoPlistPath) else {
        continue
    }
    
    // Read the plist
    guard let plistData = try? Data(contentsOf: URL(fileURLWithPath: infoPlistPath)),
          let plist = try? PropertyListSerialization.propertyList(from: plistData, options: [], format: nil) as? [String: Any] else {
        print("⚠️  Could not read Info.plist for \(item)")
        continue
    }
    
    // Check if this is a screensaver extension
    if let nsExtension = plist["NSExtension"] as? [String: Any],
       let pointIdentifier = nsExtension["NSExtensionPointIdentifier"] as? String,
       pointIdentifier == "com.apple.screensaver" {
        
        let name = String(item.dropLast(6)) // Remove .appex extension
        screensavers.append(name)
        
        if let bundleName = plist["CFBundleName"] as? String {
            print("✅ \(name) - \(bundleName)")
        } else {
            print("✅ \(name)")
        }
    }
}

print("\n📝 Summary")
print(String(repeating: "=", count: 30))
print("Found \(screensavers.count) screensaver extensions:")

// Sort alphabetically for consistent output
screensavers.sort()

print("\nSwift array format:")
print("let knownScreensavers = [")
for screensaver in screensavers {
    print("    \"\(screensaver)\",")
}
print("]")

print("\nString array for easy copying:")
print(screensavers.map { "\"\($0)\"" }.joined(separator: ", "))

print("\n✨ Update complete!")