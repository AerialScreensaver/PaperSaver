import Foundation

public struct SystemPaths {
    public static var wallpaperStorePath: String {
        if #available(macOS 14.0, *) {
            return NSString(string: "~/Library/Application Support/com.apple.wallpaper/Store").expandingTildeInPath
        } else {
            return NSString(string: "~/Library/Preferences/com.apple.desktop.plist").expandingTildeInPath
        }
    }
    
    public static var screensaverPreferencePath: String {
        NSString(string: "~/Library/Preferences/com.apple.screensaver.plist").expandingTildeInPath
    }
    
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
        
        if let userPath = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask).first {
            directories.append(userPath.appendingPathComponent("Screen Savers"))
        }
        
        return directories.filter { FileManager.default.fileExists(atPath: $0.path) }
    }
    
    public static func screensaverModuleURL(for moduleName: String) -> URL? {
        for directory in screensaverModulesDirectories() {
            let saverURL = directory.appendingPathComponent("\(moduleName).saver")
            let qtzURL = directory.appendingPathComponent("\(moduleName).qtz")
            
            if FileManager.default.fileExists(atPath: saverURL.path) {
                return saverURL
            }
            if FileManager.default.fileExists(atPath: qtzURL.path) {
                return qtzURL
            }
        }
        return nil
    }
}

public struct SystemCapabilities {
    public static var supportsPerScreenConfiguration: Bool {
        if #available(macOS 14.0, *) {
            return true
        } else {
            return false
        }
    }
    
    public static var supportsPerSpaceConfiguration: Bool {
        if #available(macOS 14.0, *) {
            return true
        } else {
            return false
        }
    }
    
    public static var requiresFullDiskAccess: Bool {
        if #available(macOS 14.0, *) {
            return true
        } else {
            return false
        }
    }
    
    public static var supportsDynamicWallpapers: Bool {
        return true
    }
}

public struct SystemVersionInfo {
    public let versionString: String
    public let buildNumber: String?
    
    public init() {
        let processInfo = ProcessInfo.processInfo
        let osVersion = processInfo.operatingSystemVersion
        self.versionString = "\(osVersion.majorVersion).\(osVersion.minorVersion).\(osVersion.patchVersion)"
        
        if let buildVersion = processInfo.operatingSystemVersionString.components(separatedBy: "Build ").last {
            self.buildNumber = buildVersion.replacingOccurrences(of: ")", with: "").trimmingCharacters(in: .whitespaces)
        } else {
            self.buildNumber = nil
        }
    }
}
