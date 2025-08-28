import Foundation
import AppKit

public protocol WallpaperManaging {
    func setWallpaper(url: URL, screen: NSScreen?, options: WallpaperOptions) async throws
    func getCurrentWallpaper(for screen: NSScreen) -> URL?
    func setWallpaperForAllScreens(url: URL) async throws
}

public class WallpaperManager: WallpaperManaging {
    private let plistManager = PlistManager.shared
    private let workspace = NSWorkspace.shared
    
    public init() {}
    
    public func setWallpaper(url: URL, screen: NSScreen?, options: WallpaperOptions = .default) async throws {
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw PaperSaverError.fileNotFound(url)
        }
        
        if #available(macOS 14.0, *) {
            try await setSonomaWallpaper(url: url, screen: screen, options: options)
        } else {
            try setLegacyWallpaper(url: url, screen: screen, options: options)
        }
    }
    
    public func getCurrentWallpaper(for screen: NSScreen) -> URL? {
        if #available(macOS 14.0, *) {
            return getSonomaWallpaper(for: screen)
        } else {
            return workspace.desktopImageURL(for: screen)
        }
    }
    
    public func setWallpaperForAllScreens(url: URL) async throws {
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw PaperSaverError.fileNotFound(url)
        }
        
        for screen in NSScreen.screens {
            try await setWallpaper(url: url, screen: screen, options: .default)
        }
    }
    
    @available(macOS 14.0, *)
    private func setSonomaWallpaper(url: URL, screen: NSScreen?, options: WallpaperOptions) async throws {
        let indexPath = SystemPaths.wallpaperIndexPath
        
        var plist: [String: Any]
        if let existingPlist = try? plistManager.read(at: indexPath) {
            plist = existingPlist
        } else {
            plist = createDefaultWallpaperPlist()
        }
        
        var modifiedPlist = plist
        
        let wallpaperData: [String: Any] = [
            "Path": url.path,
            "Scaling": options.scaling.rawValue,
            "Clipping": options.allowClipping,
            "Alignment": options.imageAlignment.rawValue
        ]
        
        if let screen = screen,
           let screenID = ScreenIdentifier(from: screen) {
            if var displays = modifiedPlist["Displays"] as? [String: Any] {
                if var displayConfig = displays["\(screenID.displayID)"] as? [String: Any],
                   var spaces = displayConfig["Spaces"] as? [[String: Any]] {
                    
                    for i in 0..<spaces.count {
                        spaces[i]["Wallpaper"] = wallpaperData
                    }
                    
                    displayConfig["Spaces"] = spaces
                    displays["\(screenID.displayID)"] = displayConfig
                } else {
                    displays["\(screenID.displayID)"] = [
                        "Spaces": [[
                            "Wallpaper": wallpaperData
                        ]]
                    ]
                }
                modifiedPlist["Displays"] = displays
            } else {
                modifiedPlist["Displays"] = [
                    "\(screenID.displayID)": [
                        "Spaces": [[
                            "Wallpaper": wallpaperData
                        ]]
                    ]
                ]
            }
        } else {
            modifiedPlist["GlobalWallpaper"] = wallpaperData
        }
        
        try plistManager.write(modifiedPlist, to: indexPath)
        
        restartWallpaperAgent()
    }
    
    private func setLegacyWallpaper(url: URL, screen: NSScreen?, options: WallpaperOptions) throws {
        let targetScreen = screen ?? NSScreen.main ?? NSScreen.screens.first
        
        guard let targetScreen = targetScreen else {
            throw PaperSaverError.invalidScreenIdentifier
        }
        
        var wallpaperOptions: [NSWorkspace.DesktopImageOptionKey: Any] = [
            .imageScaling: options.scaling.nsImageScaling,
            .allowClipping: options.allowClipping
        ]
        
        if let backgroundColor = options.backgroundColor {
            wallpaperOptions[.fillColor] = backgroundColor
        }
        
        do {
            try workspace.setDesktopImageURL(url, for: targetScreen, options: wallpaperOptions)
        } catch {
            throw PaperSaverError.unknownError(error)
        }
    }
    
    @available(macOS 14.0, *)
    private func getSonomaWallpaper(for screen: NSScreen) -> URL? {
        let indexPath = SystemPaths.wallpaperIndexPath
        
        guard let plist = try? plistManager.read(at: indexPath),
              let screenID = ScreenIdentifier(from: screen) else {
            return nil
        }
        
        if let displays = plist["Displays"] as? [String: Any],
           let displayConfig = displays["\(screenID.displayID)"] as? [String: Any],
           let spaces = displayConfig["Spaces"] as? [[String: Any]],
           let firstSpace = spaces.first,
           let wallpaper = firstSpace["Wallpaper"] as? [String: Any],
           let path = wallpaper["Path"] as? String {
            return URL(fileURLWithPath: path)
        }
        
        if let globalWallpaper = plist["GlobalWallpaper"] as? [String: Any],
           let path = globalWallpaper["Path"] as? String {
            return URL(fileURLWithPath: path)
        }
        
        return nil
    }
    
    private func createDefaultWallpaperPlist() -> [String: Any] {
        return [
            "Version": 1,
            "Displays": [:] as [String: Any],
            "SystemWallpaper": true
        ]
    }
    
    private func restartWallpaperAgent() {
        let task = Process()
        task.launchPath = "/usr/bin/killall"
        task.arguments = ["WallpaperAgent"]
        task.launch()
    }
}