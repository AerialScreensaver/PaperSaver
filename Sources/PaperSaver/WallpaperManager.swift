import Foundation
import AppKit

public protocol WallpaperManaging {
    func setWallpaper(imageURL: URL, screen: NSScreen?, options: WallpaperOptions) async throws
    func getCurrentWallpaper(for screen: NSScreen?) -> WallpaperInfo?
    
    @available(macOS 14.0, *)
    func setWallpaperForSpace(imageURL: URL, spaceUUID: String, screen: NSScreen?, options: WallpaperOptions) async throws
    
    @available(macOS 14.0, *)
    func setWallpaperForSpaceID(imageURL: URL, spaceID: Int, screen: NSScreen?, options: WallpaperOptions) async throws
    
    func setWallpaperEverywhere(imageURL: URL, options: WallpaperOptions) async throws
    
    @available(macOS 14.0, *)
    func setWallpaperForDisplay(imageURL: URL, displayNumber: Int, options: WallpaperOptions) async throws
    
    @available(macOS 14.0, *)
    func setWallpaperForDisplaySpace(imageURL: URL, displayNumber: Int, spaceNumber: Int, options: WallpaperOptions) async throws
}

public class WallpaperManager: WallpaperManaging {
    private let plistManager = PlistManager.shared
    private let configManager = ConfigurationManager()
    private let screensaverManager = ScreensaverManager()
    
    public init() {}
    
    public func setWallpaper(imageURL: URL, screen: NSScreen? = nil, options: WallpaperOptions = .default) async throws {
        guard FileManager.default.fileExists(atPath: imageURL.path) else {
            throw PaperSaverError.fileNotFound(imageURL)
        }
        
        if #available(macOS 14.0, *) {
            try await setWallpaperEverywhere(imageURL: imageURL, options: options)
        } else {
            try setLegacyWallpaper(imageURL: imageURL, screen: screen)
        }
    }
    
    public func getCurrentWallpaper(for screen: NSScreen?) -> WallpaperInfo? {
        if #available(macOS 14.0, *) {
            let indexPath = SystemPaths.wallpaperIndexPath
            
            guard let plist = try? plistManager.read(at: indexPath) else {
                return nil
            }
            
            if let screen = screen,
               let screenID = ScreenIdentifier(from: screen) {
                let displayKey = screenID.displayID.description
                
                if let displays = plist["Displays"] as? [String: Any],
                   let displayConfig = displays[displayKey] as? [String: Any],
                   let desktop = displayConfig["Desktop"] as? [String: Any],
                   let content = desktop["Content"] as? [String: Any],
                   let choices = content["Choices"] as? [[String: Any]],
                   let firstChoice = choices.first,
                   let configurationData = firstChoice["Configuration"] as? Data {
                    
                    if let urlString = try? plistManager.decodeWallpaperConfiguration(from: configurationData),
                       let url = URL(string: urlString) {
                        
                        var style: WallpaperStyle = .fill
                        if let optionsData = content["EncodedOptionValues"] as? Data,
                           let optionsPlist = try? plistManager.readBinaryPlist(from: optionsData),
                           let values = optionsPlist["values"] as? [String: Any],
                           let styleInfo = values["style"] as? [String: Any],
                           let picker = styleInfo["picker"] as? [String: Any],
                           let _0 = picker["_0"] as? [String: Any],
                           let id = _0["id"] as? String,
                           let parsedStyle = WallpaperStyle(rawValue: id) {
                            style = parsedStyle
                        }
                        
                        return WallpaperInfo(imageURL: url, style: style, screen: screenID)
                    }
                }
            }
        } else {
            return getLegacyWallpaper(for: screen)
        }
        
        return nil
    }
    
    @available(macOS 14.0, *)
    public func setWallpaperForSpaceID(imageURL: URL, spaceID: Int, screen: NSScreen? = nil, options: WallpaperOptions = .default) async throws {
        guard FileManager.default.fileExists(atPath: imageURL.path) else {
            throw PaperSaverError.fileNotFound(imageURL)
        }
        
        guard let spaceInfo = (screensaverManager as? SpaceManaging)?.getSpaceByID(spaceID) else {
            throw PaperSaverError.spaceNotFound
        }
        
        if spaceInfo.uuid.isEmpty {
            try await setWallpaper(imageURL: imageURL, screen: screen, options: options)
        } else {
            try await setWallpaperForSpace(imageURL: imageURL, spaceUUID: spaceInfo.uuid, screen: screen, options: options)
        }
    }
    
    @available(macOS 14.0, *)
    public func setWallpaperForSpace(imageURL: URL, spaceUUID: String, screen: NSScreen? = nil, options: WallpaperOptions = .default) async throws {
        guard FileManager.default.fileExists(atPath: imageURL.path) else {
            throw PaperSaverError.fileNotFound(imageURL)
        }
        
        guard !spaceUUID.isEmpty else {
            throw PaperSaverError.invalidConfiguration("Space UUID cannot be empty")
        }
        
        let indexPath = SystemPaths.wallpaperIndexPath
        
        guard var plist = try? plistManager.read(at: indexPath) else {
            throw PaperSaverError.plistReadError(indexPath)
        }
        
        let configurationData = try plistManager.createWallpaperConfiguration(imageURL: imageURL)
        let optionsData = try plistManager.createWallpaperOptions(style: options.style)
        
        var spaces = plist["Spaces"] as? [String: Any] ?? [:]
        var spaceConfig = spaces[spaceUUID] as? [String: Any] ?? [:]
        var spaceDisplays = spaceConfig["Displays"] as? [String: Any] ?? [:]
        
        if let screen = screen,
           let screenID = ScreenIdentifier(from: screen) {
            let displayKey = screenID.displayID.description
            var displayConfig = spaceDisplays[displayKey] as? [String: Any] ?? ["Type": "individual"]
            displayConfig["Desktop"] = createDesktopConfiguration(with: configurationData, options: optionsData)
            spaceDisplays[displayKey] = displayConfig
        } else {
            var defaultConfig = spaceConfig["Default"] as? [String: Any] ?? ["Type": "individual"]
            defaultConfig["Desktop"] = createDesktopConfiguration(with: configurationData, options: optionsData)
            spaceConfig["Default"] = defaultConfig
        }
        
        spaceConfig["Displays"] = spaceDisplays
        spaces[spaceUUID] = spaceConfig
        plist["Spaces"] = spaces
        
        try plistManager.write(plist, to: indexPath)
        configManager.restartWallpaperAgent()
    }
    
    public func setWallpaperEverywhere(imageURL: URL, options: WallpaperOptions = .default) async throws {
        guard FileManager.default.fileExists(atPath: imageURL.path) else {
            throw PaperSaverError.fileNotFound(imageURL)
        }
        
        if #available(macOS 14.0, *) {
            let spaceTree = (screensaverManager as? SpaceManaging)?.getNativeSpaceTree() ?? [:]
            
            guard let monitors = spaceTree["monitors"] as? [[String: Any]] else {
                try await setWallpaper(imageURL: imageURL, screen: nil, options: options)
                return
            }
            
            let displayNumbers = monitors.compactMap { monitor in
                monitor["display_number"] as? Int
            }
            
            guard !displayNumbers.isEmpty else {
                throw PaperSaverError.invalidConfiguration("No displays found")
            }
            
            for displayNumber in displayNumbers {
                try await setWallpaperForDisplay(imageURL: imageURL, displayNumber: displayNumber, options: options)
            }
        } else {
            try await setWallpaper(imageURL: imageURL, screen: nil, options: options)
        }
    }
    
    @available(macOS 14.0, *)
    public func setWallpaperForDisplay(imageURL: URL, displayNumber: Int, options: WallpaperOptions = .default) async throws {
        guard FileManager.default.fileExists(atPath: imageURL.path) else {
            throw PaperSaverError.fileNotFound(imageURL)
        }
        
        let indexPath = SystemPaths.wallpaperIndexPath
        
        guard var plist = try? plistManager.read(at: indexPath) else {
            throw PaperSaverError.plistReadError(indexPath)
        }
        
        let configurationData = try plistManager.createWallpaperConfiguration(imageURL: imageURL)
        let optionsData = try plistManager.createWallpaperOptions(style: options.style)
        
        let spaceTree = (screensaverManager as? SpaceManaging)?.getNativeSpaceTree() ?? [:]
        
        guard let monitors = spaceTree["monitors"] as? [[String: Any]] else {
            throw PaperSaverError.displayNotFound(displayNumber)
        }
        
        guard let monitor = monitors.first(where: {
            $0["display_number"] as? Int == displayNumber
        }) else {
            throw PaperSaverError.displayNotFound(displayNumber)
        }
        
        guard let displayUUID = monitor["display_uuid"] as? String else {
            throw PaperSaverError.displayNotFound(displayNumber)
        }
        
        var displays = plist["Displays"] as? [String: Any] ?? [:]
        var displayConfig = displays[displayUUID] as? [String: Any] ?? ["Type": "individual"]
        displayConfig["Desktop"] = createDesktopConfiguration(with: configurationData, options: optionsData)
        displays[displayUUID] = displayConfig
        plist["Displays"] = displays
        
        if let spaces = monitor["spaces"] as? [[String: Any]] {
            var spacesDict = plist["Spaces"] as? [String: Any] ?? [:]
            
            for space in spaces {
                if let spaceUUID = space["space_uuid"] as? String {
                    var spaceConfig = spacesDict[spaceUUID] as? [String: Any] ?? [:]
                    var spaceDisplays = spaceConfig["Displays"] as? [String: Any] ?? [:]
                    var spaceDisplayConfig = spaceDisplays[displayUUID] as? [String: Any] ?? ["Type": "individual"]
                    spaceDisplayConfig["Desktop"] = createDesktopConfiguration(with: configurationData, options: optionsData)
                    spaceDisplays[displayUUID] = spaceDisplayConfig
                    spaceConfig["Displays"] = spaceDisplays
                    spacesDict[spaceUUID] = spaceConfig
                }
            }
            
            plist["Spaces"] = spacesDict
        }
        
        try plistManager.write(plist, to: indexPath)
        configManager.restartWallpaperAgent()
    }
    
    @available(macOS 14.0, *)
    public func setWallpaperForDisplaySpace(imageURL: URL, displayNumber: Int, spaceNumber: Int, options: WallpaperOptions = .default) async throws {
        guard FileManager.default.fileExists(atPath: imageURL.path) else {
            throw PaperSaverError.fileNotFound(imageURL)
        }
        
        guard let spaceUUID = (screensaverManager as? SpaceManaging)?.getSpaceUUID(displayNumber: displayNumber, spaceNumber: spaceNumber) else {
            throw PaperSaverError.spaceNotFound
        }
        
        let screens = NSScreen.screens
        let screen = screens.first { screen in
            if let screenNumber = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID {
                let screenDisplayNumber = CGDisplayUnitNumber(screenNumber)
                return screenDisplayNumber == displayNumber
            }
            return false
        }
        
        try await setWallpaperForSpace(imageURL: imageURL, spaceUUID: spaceUUID, screen: screen, options: options)
    }
    
    private func createDesktopConfiguration(with configurationData: Data, options: Data) -> [String: Any] {
        return [
            "Content": [
                "Choices": [
                    [
                        "Configuration": configurationData,
                        "Files": [],
                        "Provider": "com.apple.wallpaper.choice.image"
                    ]
                ],
                "EncodedOptionValues": options,
                "Shuffle": NSNull()
            ],
            "LastSet": Date(),
            "LastUse": Date()
        ]
    }
    
    private func setLegacyWallpaper(imageURL: URL, screen: NSScreen?) throws {
        let workspace = NSWorkspace.shared
        
        if let screen = screen {
            try workspace.setDesktopImageURL(imageURL, for: screen, options: [:])
        } else {
            for screen in NSScreen.screens {
                try workspace.setDesktopImageURL(imageURL, for: screen, options: [:])
            }
        }
    }
    
    private func getLegacyWallpaper(for screen: NSScreen?) -> WallpaperInfo? {
        let workspace = NSWorkspace.shared
        
        if let screen = screen,
           let url = workspace.desktopImageURL(for: screen) {
            return WallpaperInfo(imageURL: url, style: .fill)
        }
        
        return nil
    }
}