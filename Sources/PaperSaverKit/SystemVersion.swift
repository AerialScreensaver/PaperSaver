import Foundation

public struct SystemPaths {
    
    public static var wallpaperIndexPath: String {
        if #available(macOS 14.0, *) {
            return NSString(string: "~/Library/Application Support/com.apple.wallpaper/Store/Index.plist").expandingTildeInPath
        } else {
            return NSString(string: "~/Library/Preferences/com.apple.desktop.plist").expandingTildeInPath
        }
    }
    
    public static func screensaverModulesDirectories() -> [URL] {
        var directories: [URL] = []
        
        directories.append(URL(fileURLWithPath: "/System/Library/Screen Savers"))
        directories.append(URL(fileURLWithPath: "/Library/Screen Savers"))
        
        // Add ExtensionKit directory for .appex screensavers (macOS Sequoia+)
        directories.append(URL(fileURLWithPath: "/System/Library/ExtensionKit/Extensions"))
        
        if let userPath = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask).first {
            directories.append(userPath.appendingPathComponent("Screen Savers"))
        }
        
        return directories.filter { FileManager.default.fileExists(atPath: $0.path) }
    }
    
    public static func screensaverModuleURL(for moduleName: String) -> URL? {
        // First try hardcoded directories (fast path for common cases)
        for directory in screensaverModulesDirectories() {
            let saverURL = directory.appendingPathComponent("\(moduleName).saver")
            let appexURL = directory.appendingPathComponent("\(moduleName).appex")

            if FileManager.default.fileExists(atPath: saverURL.path) {
                return saverURL
            }
            if FileManager.default.fileExists(atPath: appexURL.path) {
                return appexURL
            }
        }

        // Fallback to pluginkit for third-party appex in non-standard locations
        if let ext = try? PluginkitManager.shared.findExtension(byName: moduleName) {
            return ext.path
        }

        return nil
    }
}

