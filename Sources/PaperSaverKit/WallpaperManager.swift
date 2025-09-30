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
            // Use the same Spaces structure approach as other functions
            let spaceTree = screensaverManager.getNativeSpaceTree()
            guard let monitors = spaceTree["monitors"] as? [[String: Any]] else {
                return nil
            }

            // If screen is specified, find the specific display
            if let screen = screen,
               let screenID = ScreenIdentifier(from: screen) {
                let displayIDToFind = screenID.displayID.description

                // Find the monitor with matching display UUID
                for monitor in monitors {
                    guard let displayUUID = monitor["uuid"] as? String,
                          displayUUID == displayIDToFind,
                          let spaces = monitor["spaces"] as? [[String: Any]] else {
                        continue
                    }

                    // Get the current space for this display
                    for space in spaces {
                        guard let isCurrent = space["is_current"] as? Bool,
                              isCurrent,
                              let spaceUUID = space["uuid"] as? String else {
                            continue
                        }

                        // Get wallpaper for the current space using Default section prioritization
                        if let wallpaperInfo = getWallpaperForSpaceUUID(spaceUUID, screenID: screenID) {
                            return wallpaperInfo
                        }
                    }
                }
            } else {
                // No specific screen - get wallpaper from any current space
                for monitor in monitors {
                    guard let spaces = monitor["spaces"] as? [[String: Any]] else {
                        continue
                    }

                    for space in spaces {
                        guard let isCurrent = space["is_current"] as? Bool,
                              isCurrent,
                              let spaceUUID = space["uuid"] as? String else {
                            continue
                        }

                        // Get wallpaper for this current space
                        if let wallpaperInfo = getWallpaperForSpaceUUID(spaceUUID, screenID: nil) {
                            return wallpaperInfo
                        }
                    }
                }
            }

            return nil
        } else {
            return getLegacyWallpaper(for: screen)
        }
    }

    @available(macOS 14.0, *)
    private func getWallpaperForSpaceUUID(_ spaceUUID: String, screenID: ScreenIdentifier?) -> WallpaperInfo? {
        let indexPath = SystemPaths.wallpaperIndexPath

        // Handle empty UUID case - fallback to default space configuration
        let lookupUUID = spaceUUID.isEmpty ? "" : spaceUUID

        guard let plist = try? plistManager.read(at: indexPath),
              let spaces = plist["Spaces"] as? [String: Any] else {
            return nil
        }

        // Try the specific space UUID first
        var spaceConfig: [String: Any]?
        if let config = spaces[lookupUUID] as? [String: Any] {
            spaceConfig = config
        } else if !lookupUUID.isEmpty {
            // If specific UUID not found and it's not empty, try empty string (default)
            spaceConfig = spaces[""] as? [String: Any]
        }

        guard let config = spaceConfig else {
            return nil
        }

        // For ALL spaces, prioritize Default -> Desktop over Displays
        // This ensures consistent behavior with the rest of the API
        if let defaultConfig = config["Default"] as? [String: Any],
           let desktop = defaultConfig["Desktop"] as? [String: Any],
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

        // Fall back to Displays section (only if Default doesn't exist or fails)
        if let displays = config["Displays"] as? [String: Any],
           let screenID = screenID {
            let displayKey = screenID.displayID.description

            if let displayConfig = displays[displayKey] as? [String: Any],
               let desktop = displayConfig["Desktop"] as? [String: Any],
               let content = desktop["Content"] as? [String: Any],
               let choices = content["Choices"] as? [[String: Any]],
               let firstChoice = choices.first,
               let configurationData = firstChoice["Configuration"] as? Data,
               let urlString = try? plistManager.decodeWallpaperConfiguration(from: configurationData),
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

        return nil
    }

    @available(macOS 14.0, *)
    public func setWallpaperForSpaceID(imageURL: URL, spaceID: Int, screen: NSScreen? = nil, options: WallpaperOptions = .default) async throws {
        guard FileManager.default.fileExists(atPath: imageURL.path) else {
            throw PaperSaverError.fileNotFound(imageURL)
        }
        
        guard let spaceInfo = screensaverManager.getSpaceByID(spaceID) else {
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
        
        if let screen = screen,
           let screenID = ScreenIdentifier(from: screen) {
            let displayKey = screenID.displayID.description
            var spaceDisplays = spaceConfig["Displays"] as? [String: Any] ?? [:]
            // Filter out invalid display keys (like "Main") to prevent plist corruption
            spaceDisplays = filterValidDisplayKeys(spaceDisplays)
            var displayConfig = spaceDisplays[displayKey] as? [String: Any] ?? ["Type": "individual"]
            displayConfig["Desktop"] = createDesktopConfiguration(with: configurationData, options: optionsData)
            spaceDisplays[displayKey] = displayConfig
            spaceConfig["Displays"] = spaceDisplays
        } else {
            var defaultConfig = spaceConfig["Default"] as? [String: Any] ?? ["Type": "individual"]
            defaultConfig["Desktop"] = createDesktopConfiguration(with: configurationData, options: optionsData)
            spaceConfig["Default"] = defaultConfig
        }
        
        spaces[spaceUUID] = spaceConfig
        plist["Spaces"] = spaces
        
        try plistManager.write(plist, to: indexPath)
        restartWallpaperAgent()
    }
    
    public func setWallpaperEverywhere(imageURL: URL, options: WallpaperOptions = .default) async throws {
        guard FileManager.default.fileExists(atPath: imageURL.path) else {
            throw PaperSaverError.fileNotFound(imageURL)
        }
        
        if #available(macOS 14.0, *) {
            let spaceTree = screensaverManager.getNativeSpaceTree()
            
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
        
        let spaceTree = screensaverManager.getNativeSpaceTree()
        
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

                    // Write to BOTH Default and Displays sections for consistency
                    // Default section takes priority in reading, so write there first
                    var defaultConfig = spaceConfig["Default"] as? [String: Any] ?? ["Type": "individual"]
                    defaultConfig["Desktop"] = createDesktopConfiguration(with: configurationData, options: optionsData)
                    spaceConfig["Default"] = defaultConfig

                    // Also write to Displays section for backward compatibility
                    var spaceDisplays = spaceConfig["Displays"] as? [String: Any] ?? [:]
                    // Filter out invalid display keys (like "Main") to prevent plist corruption
                    spaceDisplays = filterValidDisplayKeys(spaceDisplays)
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
        restartWallpaperAgent()
    }
    
    @available(macOS 14.0, *)
    public func setWallpaperForDisplaySpace(imageURL: URL, displayNumber: Int, spaceNumber: Int, options: WallpaperOptions = .default) async throws {
        guard FileManager.default.fileExists(atPath: imageURL.path) else {
            throw PaperSaverError.fileNotFound(imageURL)
        }
        
        guard let spaceUUID = screensaverManager.getSpaceUUID(displayNumber: displayNumber, spaceNumber: spaceNumber) else {
            throw PaperSaverError.spaceNotFound
        }
        
        // Pass nil for screen, just like setScreensaverForDisplaySpace does
        // This ensures we use the Default config which applies to the space
        try await setWallpaperForSpace(imageURL: imageURL, spaceUUID: spaceUUID, screen: nil, options: options)
    }
    
    private func createDesktopConfiguration(with configurationData: Data, options: Data) -> [String: Any] {
        let content: [String: Any] = [
            "Choices": [
                [
                    "Configuration": configurationData,
                    "Files": [],
                    "Provider": "com.apple.wallpaper.choice.image"
                ]
            ],
            "EncodedOptionValues": options
        ]

        // Don't add Shuffle key at all to avoid NSNull issues
        // The system will handle the default value

        return [
            "Content": content,
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

    private func restartWallpaperAgent() {
        let task = Process()
        task.launchPath = "/usr/bin/killall"
        task.arguments = ["WallpaperAgent"]
        task.launch()
    }

    private func isValidDisplayKey(_ key: String) -> Bool {
        // Valid display keys are UUIDs in format XXXXXXXX-XXXX-XXXX-XXXX-XXXXXXXXXXXX
        // Invalid keys include "Main", numeric strings, or other non-UUID formats
        let uuidPattern = "^[0-9A-F]{8}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{12}$"
        let regex = try? NSRegularExpression(pattern: uuidPattern, options: [.caseInsensitive])
        let range = NSRange(location: 0, length: key.count)
        return regex?.firstMatch(in: key, options: [], range: range) != nil
    }

    /// Filters a Displays dictionary to keep only valid UUID-format display keys
    /// Removes invalid keys like "Main", numeric strings, or other non-UUID formats
    private func filterValidDisplayKeys(_ displays: [String: Any]) -> [String: Any] {
        return displays.filter { key, _ in
            isValidDisplayKey(key)
        }
    }
}