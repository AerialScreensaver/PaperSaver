import Foundation
import AppKit
import ColorSync

// Private CoreGraphics API declarations for native space detection
@_silgen_name("CGSMainConnectionID")
func CGSMainConnectionID() -> UInt32

@_silgen_name("CGSCopyManagedDisplaySpaces") 
func CGSCopyManagedDisplaySpaces(_ cid: UInt32) -> CFArray

public protocol ScreensaverManaging {
    func setScreensaver(module: String, screen: NSScreen?) async throws
    func getActiveScreensaver(for screen: NSScreen?) -> ScreensaverInfo?
    func getActiveScreensavers() -> [String]
    func setIdleTime(seconds: Int) throws
    func getIdleTime() -> Int
    func listAvailableScreensavers() -> [ScreensaverModule]
    
    @available(macOS 14.0, *)
    func setScreensaverForSpaceID(module: String, spaceID: Int, screen: NSScreen?) async throws
    
    @available(macOS 14.0, *)
    func setScreensaverForSpace(module: String, spaceUUID: String, screen: NSScreen?) async throws
    
    func setScreensaverEverywhere(module: String) async throws
    
    @available(macOS 14.0, *)
    func setScreensaverForDisplay(module: String, displayNumber: Int) async throws
    
    @available(macOS 14.0, *)
    func setScreensaverForDisplaySpace(module: String, displayNumber: Int, spaceNumber: Int) async throws
}

@available(macOS 14.0, *)
public protocol SpaceManaging {
    func listSpaces() -> [SpaceInfo]
    func getAllSpaces(includeHistorical: Bool) -> [SpaceInfo]
    func getActiveSpace() -> SpaceInfo?
    func getActiveSpaces() -> [SpaceInfo]
    func getSpaceByID(_ spaceID: Int) -> SpaceInfo?
    func getSpacesForDisplay(_ displayIdentifier: String, includeHistorical: Bool) -> [SpaceInfo]
    func listDisplays() -> [DisplayInfo]
    func getDisplayUUID(for screen: NSScreen) -> String?
    func getNativeSpaceTree() -> [String: Any]
    func getSpaceUUID(displayNumber: Int, spaceNumber: Int) -> String?
    func getAllSpaceUUIDs(for displayNumber: Int) -> [String]
}

public class ScreensaverManager: ScreensaverManaging {
    private let plistManager = PlistManager.shared
    
    public init() {}
    
    public func setScreensaver(module: String, screen: NSScreen?) async throws {
        if #available(macOS 14.0, *) {
            // Sonoma+: Set screensaver appropriately based on configuration
            if screen == nil {
                // No specific screen - set everywhere
                try await setScreensaverEverywhere(module: module)
            } else {
                // Specific screen requested - set for default/current space on that screen
                try await setScreensaverForDefaultSpace(module: module, screen: screen)
            }
        } else {
            try setLegacyScreensaver(module: module)
        }
    }
    
    public func getActiveScreensaver(for screen: NSScreen?) -> ScreensaverInfo? {
        if #available(macOS 14.0, *) {
            // Sonoma+: Use the same Spaces structure approach as CLI and getActiveScreensavers
            let spaceTree = getNativeSpaceTree()

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

                        // Get screensaver for the current space
                        if let screensaverName = getScreensaverForSpaceUUID(spaceUUID) {
                            return ScreensaverInfo(
                                name: screensaverName,
                                identifier: screensaverName,
                                screen: screenID
                            )
                        }
                    }
                }
            } else {
                // No specific screen - get screensaver from any current space
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

                        // Get screensaver for this current space
                        if let screensaverName = getScreensaverForSpaceUUID(spaceUUID) {
                            return ScreensaverInfo(
                                name: screensaverName,
                                identifier: screensaverName
                            )
                        }
                    }
                }
            }

            return nil
        } else {
            return getLegacyScreensaver()
        }
    }

    public func getActiveScreensavers() -> [String] {
        if #available(macOS 14.0, *) {
            // Sonoma+: Use getNativeSpaceTree approach (same as CLI list-spaces command)
            var screensaverNames = Set<String>()

            // Get the native space tree (this is what the CLI uses successfully)
            let spaceTree = getNativeSpaceTree()

            guard let monitors = spaceTree["monitors"] as? [[String: Any]] else {
                return []
            }

            // Iterate through each monitor and its spaces
            for monitor in monitors {
                guard let spaces = monitor["spaces"] as? [[String: Any]] else {
                    continue
                }

                // Process each space in this monitor
                for space in spaces {
                    guard let spaceUUID = space["uuid"] as? String else {
                        continue
                    }

                    // Get screensaver for this space using the same logic as CLI
                    if let screensaverName = getScreensaverForSpaceUUID(spaceUUID) {
                        screensaverNames.insert(screensaverName)
                    }
                }
            }

            return Array(screensaverNames).sorted()
        } else {
            // Legacy: Return single screensaver name if available
            if let screensaver = getLegacyScreensaver() {
                return [screensaver.name]
            }
            return []
        }
    }

    @available(macOS 14.0, *)
    private func getScreensaverForSpaceUUID(_ spaceUUID: String) -> String? {
        let indexPath = SystemPaths.wallpaperIndexPath

        // Handle empty UUID case - fallback to default space configuration
        let lookupUUID = spaceUUID.isEmpty ? "" : spaceUUID

        guard let plist = try? plistManager.read(at: indexPath) else {
            return nil
        }

        // Check if we have a Spaces structure (multi-space configuration)
        var spaceConfig: [String: Any]?

        if let spaces = plist["Spaces"] as? [String: Any], !spaces.isEmpty {
            // Try the specific space UUID first
            if let config = spaces[lookupUUID] as? [String: Any] {
                spaceConfig = config
            } else if !lookupUUID.isEmpty {
                // If specific UUID not found and it's not empty, try empty string (default)
                spaceConfig = spaces[""] as? [String: Any]
            }
        } else if let allSpacesAndDisplays = plist["AllSpacesAndDisplays"] as? [String: Any] {
            // Handle single screen/space configuration with AllSpacesAndDisplays (takes precedence)
            spaceConfig = allSpacesAndDisplays
        } else if let systemDefault = plist["SystemDefault"] as? [String: Any] {
            // Handle single screen/space configuration with SystemDefault (fallback)
            spaceConfig = systemDefault
        }

        guard let config = spaceConfig else {
            return nil
        }

        // Check if Idle is directly in config (SystemDefault case)
        if let idle = config["Idle"] as? [String: Any],
           let content = idle["Content"] as? [String: Any],
           let choices = content["Choices"] as? [[String: Any]],
           let firstChoice = choices.first,
           let configurationData = firstChoice["Configuration"] as? Data {

            // Use the new type-aware decoding method
            if let (name, _) = try? plistManager.decodeScreensaverConfigurationWithType(from: configurationData) {
                if let screensaverName = name {
                    return screensaverName
                }
            }

            // Fallback to old method for compatibility
            if let moduleName = try? plistManager.decodeScreensaverConfiguration(from: configurationData) {
                return moduleName
            }
        }

        // For ALL spaces, prioritize Default -> Idle over Displays
        // This ensures consistent behavior with CLI list-spaces command
        if let defaultConfig = config["Default"] as? [String: Any],
           let idle = defaultConfig["Idle"] as? [String: Any],
           let content = idle["Content"] as? [String: Any],
           let choices = content["Choices"] as? [[String: Any]],
           let firstChoice = choices.first,
           let configurationData = firstChoice["Configuration"] as? Data {

            // Use the new type-aware decoding method
            if let (name, _) = try? plistManager.decodeScreensaverConfigurationWithType(from: configurationData) {
                if let screensaverName = name {
                    return screensaverName
                }
            }

            // Fallback to old method for compatibility
            if let moduleName = try? plistManager.decodeScreensaverConfiguration(from: configurationData) {
                return moduleName
            }
        }

        // Fall back to Displays section (only if Default doesn't exist or fails)
        guard let displays = config["Displays"] as? [String: Any] else {
            return nil
        }

        // Get connected displays to prioritize active displays
        let connectedDisplays = listDisplays().filter { $0.isConnected }
        let connectedUUIDs = Set(connectedDisplays.map { $0.uuid })

        // Find the connected display first, fall back to any display
        var displayKeysToCheck: [String] = []

        // First, add any connected displays (but only valid ones)
        for displayKey in displays.keys {
            // Skip invalid display keys (like "Main", numeric IDs, etc.)
            guard isValidDisplayKey(displayKey) else {
                continue
            }
            if connectedUUIDs.contains(displayKey) {
                displayKeysToCheck.append(displayKey)
            }
        }

        // Then add remaining valid displays in sorted order (for fallback)
        let validDisplayKeys = displays.keys.filter(isValidDisplayKey).sorted()
        for displayKey in validDisplayKeys {
            if !displayKeysToCheck.contains(displayKey) {
                displayKeysToCheck.append(displayKey)
            }
        }

        // Check each display for screensaver configuration
        for displayKey in displayKeysToCheck {
            if let displayConfig = displays[displayKey] as? [String: Any],
               let idle = displayConfig["Idle"] as? [String: Any],
               let content = idle["Content"] as? [String: Any],
               let choices = content["Choices"] as? [[String: Any]],
               let firstChoice = choices.first,
               let configurationData = firstChoice["Configuration"] as? Data {

                if let moduleName = try? plistManager.decodeScreensaverConfiguration(from: configurationData) {
                    return moduleName
                }
            }
        }

        return nil
    }
    
    public func setIdleTime(seconds: Int) throws {
        // Validate input - negative values are invalid
        guard seconds >= 0 else {
            throw PaperSaverError.invalidConfiguration("Idle time cannot be negative")
        }
        
        // Set in currentHost preferences (these take precedence)
        CFPreferencesSetValue(
            "idleTime" as CFString,
            seconds as CFNumber,
            "com.apple.screensaver" as CFString,
            kCFPreferencesCurrentUser,
            kCFPreferencesCurrentHost
        )
        
        let synced = CFPreferencesSynchronize(
            "com.apple.screensaver" as CFString,
            kCFPreferencesCurrentUser,
            kCFPreferencesCurrentHost
        )
        
        if !synced {
            throw PaperSaverError.invalidConfiguration("Failed to save idle time preference")
        }
    }
    
    public func getIdleTime() -> Int {
        // Read from currentHost preferences (only these are valid for idle time)
        if let value = CFPreferencesCopyValue(
            "idleTime" as CFString,
            "com.apple.screensaver" as CFString,
            kCFPreferencesCurrentUser,
            kCFPreferencesCurrentHost
        ) as? Int {
            return value
        }
        
        // Return 0 (never) if not set in currentHost
        return 0
    }
    
    public func listAvailableScreensavers() -> [ScreensaverModule] {
        var modules: [ScreensaverModule] = []
        
        for directory in SystemPaths.screensaverModulesDirectories() {
            if let enumerator = FileManager.default.enumerator(
                at: directory,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles, .skipsPackageDescendants] // Don't enumerate inside bundles
            ) {
                for case let fileURL as URL in enumerator {
                    // Skip Default Collections and its contents
                    if fileURL.path.contains("Default Collections") {
                        continue
                    }
                    
                    let `extension` = fileURL.pathExtension.lowercased()
                    
                    if let screensaverType = ScreensaverType.allCases.first(where: { $0.fileExtension == `extension` }) {
                        let name = fileURL.deletingPathExtension().lastPathComponent
                        let identifier = fileURL.lastPathComponent
                        let isSystem = fileURL.path.hasPrefix("/System/")
                        
                        // For .appex files in ExtensionKit, filter to known screensavers
                        if `extension` == "appex" && fileURL.path.contains("/ExtensionKit/Extensions/") {
                            // Static list of known screensaver extensions (updated via Scripts/update-screensaver-list.swift)
                            let knownScreensavers = [
                                "Album Artwork",
                                "Arabesque", 
                                "Computer Name",
                                "Drift",
                                "Flurry",
                                "Hello",
                                "iLifeSlideshows",
                                "Monterey",
                                "Shell",
                                "Ventura",
                                "Word of the Day"
                            ]
                            guard knownScreensavers.contains(name) else {
                                continue
                            }
                        }
                        
                        modules.append(ScreensaverModule(
                            name: name,
                            identifier: identifier,
                            path: fileURL,
                            type: screensaverType,
                            isSystem: isSystem
                        ))
                    }
                }
            }
        }
        
        return modules
    }
    
    
    private func createIdleConfiguration(with configurationData: Data) -> [String: Any] {
        // Don't add EncodedOptionValues and Shuffle keys when they would be null
        // This avoids NSNull serialization issues with binary plist format
        // The system will handle default values appropriately
        return [
            "Content": [
                "Choices": [
                    [
                        "Configuration": configurationData,
                        "Files": [],
                        "Provider": "com.apple.wallpaper.choice.screen-saver"
                    ]
                ]
            ],
            "LastSet": Date(),
            "LastUse": Date()
        ]
    }

    private func isValidDisplayKey(_ key: String) -> Bool {
        // Valid display keys are UUIDs in format XXXXXXXX-XXXX-XXXX-XXXX-XXXXXXXXXXXX
        // Invalid keys include "Main", numeric strings, or other non-UUID formats
        let uuidPattern = "^[0-9A-F]{8}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{12}$"
        let regex = try? NSRegularExpression(pattern: uuidPattern, options: [.caseInsensitive])
        let range = NSRange(location: 0, length: key.count)
        return regex?.firstMatch(in: key, options: [], range: range) != nil
    }
    
    private func setLegacyScreensaver(module: String) throws {
        let moduleDict: [String: Any] = [
            "moduleName": module,
            "path": findScreensaverPath(for: module) ?? "",
            "type": 0
        ]
        
        // Set in currentHost preferences (these take precedence)
        CFPreferencesSetValue(
            "moduleDict" as CFString,
            moduleDict as CFDictionary,
            "com.apple.screensaver" as CFString,
            kCFPreferencesCurrentUser,
            kCFPreferencesCurrentHost
        )
        
        let synced = CFPreferencesSynchronize(
            "com.apple.screensaver" as CFString,
            kCFPreferencesCurrentUser,
            kCFPreferencesCurrentHost
        )
        
        if !synced {
            throw PaperSaverError.invalidConfiguration("Failed to save screensaver preference")
        }
    }
    
    
    private func getLegacyScreensaver() -> ScreensaverInfo? {
        // Read from currentHost preferences first (these take precedence)
        if let moduleDict = CFPreferencesCopyValue(
            "moduleDict" as CFString,
            "com.apple.screensaver" as CFString,
            kCFPreferencesCurrentUser,
            kCFPreferencesCurrentHost
        ) as? [String: Any],
           let moduleName = moduleDict["moduleName"] as? String {
            return ScreensaverInfo(
                name: moduleName,
                identifier: moduleName,
                modulePath: moduleDict["path"] as? String
            )
        }
        
        // Fallback to global preferences
        let defaults = UserDefaults(suiteName: "com.apple.screensaver")
        
        if let moduleDict = defaults?.dictionary(forKey: "moduleDict"),
           let moduleName = moduleDict["moduleName"] as? String {
            return ScreensaverInfo(
                name: moduleName,
                identifier: moduleName,
                modulePath: moduleDict["path"] as? String
            )
        }
        
        return nil
    }
    
    private func findScreensaverPath(for module: String) -> String? {
        return SystemPaths.screensaverModuleURL(for: module)?.path
    }
    
    private func restartWallpaperAgent() {
        let task = Process()
        task.launchPath = "/usr/bin/killall"
        task.arguments = ["WallpaperAgent"]
        task.launch()
    }
    
    // Debug helper to export dictionary structure as readable text
    private func exportDictionaryDebug(_ dictionary: [String: Any], to filePath: String, title: String) {
        var output = "\(title)\n"
        output += String(repeating: "=", count: title.count) + "\n\n"
        
        func describeDictionary(_ dict: [String: Any], prefix: String = "", level: Int = 0) -> String {
            var result = ""
            let indent = String(repeating: "  ", count: level)
            
            for (key, value) in dict.sorted(by: { $0.key < $1.key }) {
                let fullPath = prefix.isEmpty ? key : "\(prefix).\(key)"
                
                if let subDict = value as? [String: Any] {
                    result += "\(indent)\(key): [Dictionary with \(subDict.count) keys]\n"
                    result += describeDictionary(subDict, prefix: fullPath, level: level + 1)
                } else if let array = value as? [Any] {
                    result += "\(indent)\(key): [Array with \(array.count) items]\n"
                    for (index, item) in array.enumerated() {
                        if let itemDict = item as? [String: Any] {
                            result += "\(indent)  [\(index)]: [Dictionary with \(itemDict.count) keys]\n"
                            result += describeDictionary(itemDict, prefix: "\(fullPath)[\(index)]", level: level + 2)
                        } else if let data = item as? Data {
                            result += "\(indent)  [\(index)]: Data(\(data.count) bytes)\n"
                        } else {
                            result += "\(indent)  [\(index)]: \(type(of: item)) = \(item)\n"
                        }
                    }
                } else if let data = value as? Data {
                    result += "\(indent)\(key): Data(\(data.count) bytes)\n"
                } else if let date = value as? Date {
                    result += "\(indent)\(key): Date = \(date)\n"
                } else if value is NSNull {
                    result += "\(indent)\(key): NSNull\n"
                } else {
                    result += "\(indent)\(key): \(type(of: value)) = \(value)\n"
                }
            }
            return result
        }
        
        output += describeDictionary(dictionary)
        
        // Add summary statistics
        output += "\n\nSUMMARY:\n"
        output += "========\n"
        output += "Top-level keys: \(dictionary.keys.count)\n"
        
        if let displays = dictionary["Displays"] as? [String: Any] {
            output += "Displays section: \(displays.keys.count) display UUIDs\n"
        }
        
        if let spaces = dictionary["Spaces"] as? [String: Any] {
            output += "Spaces section: \(spaces.keys.count) space entries\n"
            var totalSpaceDisplays = 0
            for (spaceKey, spaceValue) in spaces {
                if let spaceDict = spaceValue as? [String: Any],
                   let spaceDisplays = spaceDict["Displays"] as? [String: Any] {
                    totalSpaceDisplays += spaceDisplays.keys.count
                    output += "  Space '\(spaceKey)': \(spaceDisplays.keys.count) displays\n"
                }
            }
            output += "Total display configs in all spaces: \(totalSpaceDisplays)\n"
        }
        
        do {
            try output.write(toFile: filePath, atomically: true, encoding: .utf8)
            print("DEBUG: Exported dictionary structure to \(filePath)")
        } catch {
            print("DEBUG: Failed to export dictionary: \(error)")
        }
    }
    
    @available(macOS 14.0, *)
    public func setScreensaverForSpaceID(module: String, spaceID: Int, screen: NSScreen? = nil) async throws {
        guard let spaceInfo = getSpaceByID(spaceID) else {
            throw PaperSaverError.spaceNotFound
        }
        
        if spaceInfo.uuid.isEmpty {
            try await setScreensaver(module: module, screen: screen)
        } else {
            try await setScreensaverForSpace(module: module, spaceUUID: spaceInfo.uuid, screen: screen)
        }
    }
    
    @available(macOS 14.0, *)
    private func setScreensaverForDefaultSpace(module: String, screen: NSScreen? = nil) async throws {
        let indexPath = SystemPaths.wallpaperIndexPath

        guard var plist = try? plistManager.read(at: indexPath) else {
            throw PaperSaverError.plistReadError(indexPath)
        }

        guard let moduleURL = SystemPaths.screensaverModuleURL(for: module) else {
            throw PaperSaverError.screensaverNotFound(module)
        }

        let configurationData = try plistManager.createScreensaverConfiguration(moduleURL: moduleURL)

        // Check if we should use SystemDefault or Spaces with empty UUID
        if let spaces = plist["Spaces"] as? [String: Any], !spaces.isEmpty {
            // Use Spaces with empty UUID
            var spacesDict = spaces
            var spaceConfig = spacesDict[""] as? [String: Any] ?? [:]

            // Write to Default section
            var defaultConfig = spaceConfig["Default"] as? [String: Any] ?? ["Type": "individual"]
            defaultConfig["Idle"] = createIdleConfiguration(with: configurationData)
            spaceConfig["Default"] = defaultConfig

            // Also write to Displays section for backward compatibility
            var spaceDisplays = spaceConfig["Displays"] as? [String: Any] ?? [:]
            for screen in NSScreen.screens {
                if let screenID = ScreenIdentifier(from: screen) {
                    let displayKey = screenID.displayID.description
                    var displayConfig: [String: Any] = ["Type": "individual"]
                    displayConfig["Idle"] = createIdleConfiguration(with: configurationData)
                    spaceDisplays[displayKey] = displayConfig
                }
            }
            spaceConfig["Displays"] = spaceDisplays

            spacesDict[""] = spaceConfig
            plist["Spaces"] = spacesDict
        } else {
            // Use SystemDefault for single screen/space configuration
            var systemDefault = plist["SystemDefault"] as? [String: Any] ?? ["Type": "individual"]
            systemDefault["Idle"] = createIdleConfiguration(with: configurationData)
            plist["SystemDefault"] = systemDefault

            // Also update AllSpacesAndDisplays if it exists (it may take precedence)
            if var allSpacesAndDisplays = plist["AllSpacesAndDisplays"] as? [String: Any] {
                allSpacesAndDisplays["Idle"] = createIdleConfiguration(with: configurationData)
                plist["AllSpacesAndDisplays"] = allSpacesAndDisplays
            }
        }

        try plistManager.write(plist, to: indexPath)
        restartWallpaperAgent()
    }

    @available(macOS 14.0, *)
    public func setScreensaverForSpace(module: String, spaceUUID: String, screen: NSScreen? = nil) async throws {
        // Handle empty UUID case - this means we're setting for the default/current space
        if spaceUUID.isEmpty {
            // For empty UUID, we need to determine if we should use SystemDefault or Spaces
            try await setScreensaverForDefaultSpace(module: module, screen: screen)
            return
        }

        let indexPath = SystemPaths.wallpaperIndexPath

        guard var plist = try? plistManager.read(at: indexPath) else {
            throw PaperSaverError.plistReadError(indexPath)
        }

        guard let moduleURL = SystemPaths.screensaverModuleURL(for: module) else {
            throw PaperSaverError.screensaverNotFound(module)
        }

        let configurationData = try plistManager.createScreensaverConfiguration(moduleURL: moduleURL)

        // Get or create Spaces section
        var spaces = plist["Spaces"] as? [String: Any] ?? [:]

        // Get or create the specific space
        var spaceConfig = spaces[spaceUUID] as? [String: Any] ?? [:]

        // Write to BOTH Default and Displays sections for consistency
        // Default section takes priority in reading, so write there first
        var defaultConfig = spaceConfig["Default"] as? [String: Any] ?? ["Type": "individual"]
        defaultConfig["Idle"] = createIdleConfiguration(with: configurationData)
        spaceConfig["Default"] = defaultConfig

        // Get or create Displays section for this space (for backward compatibility)
        var spaceDisplays = spaceConfig["Displays"] as? [String: Any] ?? [:]
        
        if let screen = screen,
           let screenID = ScreenIdentifier(from: screen) {
            // Set screensaver for specific screen
            let displayKey = screenID.displayID.description
            var displayConfig = spaceDisplays[displayKey] as? [String: Any] ?? ["Type": "individual"]
            displayConfig["Idle"] = createIdleConfiguration(with: configurationData)
            spaceDisplays[displayKey] = displayConfig
        } else {
            // Set screensaver for all displays already configured in this specific space
            // Don't add displays from other spaces - only update existing ones
            if spaceDisplays.isEmpty {
                // If this space has no display configurations yet, add only currently connected displays
                for screen in NSScreen.screens {
                    if let screenID = ScreenIdentifier(from: screen) {
                        let displayKey = screenID.displayID.description
                        var displayConfig: [String: Any] = ["Type": "individual"]
                        displayConfig["Idle"] = createIdleConfiguration(with: configurationData)
                        spaceDisplays[displayKey] = displayConfig
                    }
                }
            } else {
                // Update existing displays in this space only, but filter out invalid display keys
                for displayKey in spaceDisplays.keys {
                    // Skip invalid display keys (like "Main", numeric IDs, etc.)
                    guard isValidDisplayKey(displayKey) else {
                        continue
                    }
                    var displayConfig = spaceDisplays[displayKey] as? [String: Any] ?? ["Type": "individual"]
                    displayConfig["Idle"] = createIdleConfiguration(with: configurationData)
                    spaceDisplays[displayKey] = displayConfig
                }
            }
        }
        
        // Update the space configuration
        spaceConfig["Displays"] = spaceDisplays
        spaces[spaceUUID] = spaceConfig
        plist["Spaces"] = spaces
        
        try plistManager.write(plist, to: indexPath)
        restartWallpaperAgent()
    }
    
    
    public func setScreensaverEverywhere(module: String) async throws {
        if #available(macOS 14.0, *) {
            // Check if we're in a single screen/space configuration
            let indexPath = SystemPaths.wallpaperIndexPath
            guard let plist = try? plistManager.read(at: indexPath) else {
                throw PaperSaverError.plistReadError(indexPath)
            }

            // Check if we should use SystemDefault
            if let spaces = plist["Spaces"] as? [String: Any], !spaces.isEmpty {
                // Multi-space configuration - use the existing logic
                let spaceTree = getNativeSpaceTree()

                guard let monitors = spaceTree["monitors"] as? [[String: Any]] else {
                    // Fallback to setting default space
                    try await setScreensaverForDefaultSpace(module: module, screen: nil)
                    return
                }

                // Extract all display numbers
                let displayNumbers = monitors.compactMap { monitor in
                    monitor["display_number"] as? Int
                }

                guard !displayNumbers.isEmpty else {
                    throw PaperSaverError.screensaverNotFound(module)
                }

                // Set screensaver on each display
                for displayNumber in displayNumbers {
                    try await setScreensaverForDisplay(module: module, displayNumber: displayNumber)
                }
            } else {
                // Single screen/space configuration - use SystemDefault
                try await setScreensaverForDefaultSpace(module: module, screen: nil)
            }
        } else {
            // Pre-Sonoma: Use legacy method to set on all screens
            try await setScreensaver(module: module, screen: nil)
        }
    }
    
    @available(macOS 14.0, *)
    public func setScreensaverForDisplay(module: String, displayNumber: Int) async throws {
        let indexPath = SystemPaths.wallpaperIndexPath
        
        guard var plist = try? plistManager.read(at: indexPath) else {
            throw PaperSaverError.plistReadError(indexPath)
        }
        
        guard let moduleURL = SystemPaths.screensaverModuleURL(for: module) else {
            throw PaperSaverError.screensaverNotFound(module)
        }
        
        let configurationData = try plistManager.createScreensaverConfiguration(moduleURL: moduleURL)
        let spaceTree = getNativeSpaceTree()
        
        guard let monitors = spaceTree["monitors"] as? [[String: Any]] else {
            throw PaperSaverError.displayNotFound(displayNumber)
        }
        
        // Find the display by displayNumber
        guard let monitor = monitors.first(where: { 
            ($0["display_number"] as? Int) == displayNumber 
        }),
              let spaces = monitor["spaces"] as? [[String: Any]] else {
            throw PaperSaverError.displayNotFound(displayNumber)
        }
        
        // Find the display UUID for the Displays section
        guard let displayUUID = monitor["uuid"] as? String else {
            throw PaperSaverError.displayNotFound(displayNumber)
        }
        
        // Handle all spaces (including empty UUID) using the Spaces section for consistency
        var spacesConfig = plist["Spaces"] as? [String: Any] ?? [:]
        var spacesProcessed = 0
        
        for space in spaces {
            guard let uuid = space["uuid"] as? String else { continue }

            // Set screensaver for this specific space (including empty UUID space)
            var spaceConfig = spacesConfig[uuid] as? [String: Any] ?? [:]

            // Write to BOTH Default and Displays sections for consistency
            // Default section takes priority in reading, so write there first
            var defaultConfig = spaceConfig["Default"] as? [String: Any] ?? ["Type": "individual"]
            defaultConfig["Idle"] = createIdleConfiguration(with: configurationData)
            spaceConfig["Default"] = defaultConfig

            // Also write to Displays section for backward compatibility
            var spaceDisplays = spaceConfig["Displays"] as? [String: Any] ?? [:]
            var spaceDisplayConfig = spaceDisplays[displayUUID] as? [String: Any] ?? ["Type": "individual"]
            spaceDisplayConfig["Idle"] = createIdleConfiguration(with: configurationData)
            spaceDisplays[displayUUID] = spaceDisplayConfig
            spaceConfig["Displays"] = spaceDisplays

            spacesConfig[uuid] = spaceConfig
            spacesProcessed += 1
        }
        
        guard spacesProcessed > 0 else {
            throw PaperSaverError.displayNotFound(displayNumber)
        }
        
        plist["Spaces"] = spacesConfig
        
        try plistManager.write(plist, to: indexPath)
        restartWallpaperAgent()
    }
    
    @available(macOS 14.0, *)
    public func setScreensaverForDisplaySpace(module: String, displayNumber: Int, spaceNumber: Int) async throws {
        guard let uuid = getSpaceUUID(displayNumber: displayNumber, spaceNumber: spaceNumber) else {
            throw PaperSaverError.spaceNotFoundOnDisplay(displayNumber: displayNumber, spaceNumber: spaceNumber)
        }
        
        try await setScreensaverForSpace(module: module, spaceUUID: uuid, screen: nil)
    }
}

@available(macOS 14.0, *)
extension ScreensaverManager: SpaceManaging {
    
    public func listSpaces() -> [SpaceInfo] {
        return getAllSpaces(includeHistorical: true)
    }
    
    public func getAllSpaces(includeHistorical: Bool = false) -> [SpaceInfo] {
        let indexPath = SystemPaths.wallpaperIndexPath
        
        guard let wallpaperPlist = try? plistManager.read(at: indexPath),
              let wallpaperSpaces = wallpaperPlist["Spaces"] as? [String: Any] else {
            return []
        }
        
        let spacesManager = SpacesManager.shared
        let missionControlSpaces = spacesManager.getMissionControlSpaces()
        
        var spaceInfos: [SpaceInfo] = []
        
        // First, process all wallpaper spaces and correlate with Mission Control data
        for (spaceUUID, spaceValue) in wallpaperSpaces {
            guard let spaceConfig = spaceValue as? [String: Any] else { continue }
            
            var displayUUIDs: [String] = []
            if let displays = spaceConfig["Displays"] as? [String: Any] {
                displayUUIDs = Array(displays.keys)
            }
            
            // Find corresponding Mission Control space
            let mcSpace = missionControlSpaces.first { $0.uuid == spaceUUID }
            
            // Determine if this is a historical space (exists in wallpaper but not in active Mission Control)
            let isHistorical = mcSpace?.isHistorical ?? (mcSpace == nil && !spaceUUID.isEmpty && spaceUUID != "SystemDefault")
            
            // Skip historical spaces if not requested
            if isHistorical && !includeHistorical {
                continue
            }
            
            let spaceInfo = SpaceInfo(
                uuid: spaceUUID,
                displayUUIDs: displayUUIDs,
                isActive: true, // Has wallpaper config
                name: nil,
                spaceID: mcSpace?.spaceID,
                displayIdentifier: mcSpace?.displayIdentifier,
                isCurrent: mcSpace?.isCurrent ?? false,
                isHistorical: isHistorical
            )
            
            spaceInfos.append(spaceInfo)
        }
        
        // Add any Mission Control spaces that don't have wallpaper configs yet
        for mcSpace in missionControlSpaces {
            // Skip if we already processed this space or if it's historical and not requested
            if spaceInfos.contains(where: { $0.uuid == mcSpace.uuid }) {
                continue
            }
            
            if mcSpace.isHistorical && !includeHistorical {
                continue
            }
            
            let spaceInfo = SpaceInfo(
                uuid: mcSpace.uuid,
                displayUUIDs: [],
                isActive: false, // No wallpaper config yet
                name: nil,
                spaceID: mcSpace.spaceID,
                displayIdentifier: mcSpace.displayIdentifier,
                isCurrent: mcSpace.isCurrent,
                isHistorical: mcSpace.isHistorical
            )
            
            spaceInfos.append(spaceInfo)
        }
        
        // Sort by display identifier (Main first) then by space ID
        return spaceInfos.sorted { first, second in
            // Main display first
            if first.displayIdentifier == "Main" && second.displayIdentifier != "Main" {
                return true
            }
            if second.displayIdentifier == "Main" && first.displayIdentifier != "Main" {
                return false
            }
            
            // Then by space ID if available
            if let firstID = first.spaceID, let secondID = second.spaceID {
                return firstID < secondID
            }
            
            // Finally by UUID
            return first.uuid < second.uuid
        }
    }
    
    public func getActiveSpace() -> SpaceInfo? {
        let spaces = listSpaces()
        
        // First, try to find a space that is actually current (isCurrent: true)
        if let actualCurrentSpace = spaces.first(where: { $0.isCurrent }) {
            return actualCurrentSpace
        }
        
        // If no actual current space found, fall back to empty UUID spaces
        return spaces.first { $0.uuid.isEmpty }
    }
    
    public func getActiveSpaces() -> [SpaceInfo] {
        return getAllSpaces(includeHistorical: false)
    }
    
    public func getSpaceByID(_ spaceID: Int) -> SpaceInfo? {
        return listSpaces().first { $0.spaceID == spaceID }
    }
    
    public func getSpacesForDisplay(_ displayIdentifier: String, includeHistorical: Bool = false) -> [SpaceInfo] {
        return getAllSpaces(includeHistorical: includeHistorical)
            .filter { $0.displayIdentifier == displayIdentifier }
    }
    
    public func listDisplays() -> [DisplayInfo] {
        let windowServerManager = WindowServerDisplayManager.shared
        let windowServerConfigs = windowServerManager.getWindowServerDisplays()
        let allKnownUUIDs = windowServerManager.getAllKnownDisplayUUIDs()
        
        // Note: Could add wallpaper display UUID correlation in the future if needed
        
        var displayInfos: [DisplayInfo] = []
        let activeScreens = NSScreen.screens
        
        // Process all known display UUIDs from WindowServer
        for uuid in allKnownUUIDs {
            let windowServerConfig = windowServerConfigs.first { $0.uuid == uuid }
            let (displayID, frame, isMain, displayName) = findMatchingScreen(uuid: uuid, activeScreens: activeScreens)
            
            let displayInfo = DisplayInfo(
                uuid: uuid,
                displayID: displayID,
                frame: frame,
                isMain: isMain,
                isConnected: displayID != nil && displayID != 0,
                resolution: windowServerConfig?.resolution,
                refreshRate: windowServerConfig?.refreshRate,
                scale: windowServerConfig?.scale,
                configVersion: windowServerConfig?.configVersion,
                displayName: displayName  // Real display name from NSScreen!
            )
            
            displayInfos.append(displayInfo)
        }
        
        // Sort by connection status first (connected first), then by UUID
        return displayInfos.sorted { first, second in
            if first.isConnected && !second.isConnected {
                return true
            }
            if second.isConnected && !first.isConnected {
                return false
            }
            return first.uuid < second.uuid
        }
    }
    
    public func getDisplayUUID(for screen: NSScreen) -> String? {
        let displays = listDisplays()
        
        guard let screenDisplayID = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID else {
            return nil
        }
        
        return displays.first { $0.displayID == screenDisplayID }?.uuid
    }
    
    public func getSpacesForDisplay(_ displayUUID: String) -> [SpaceInfo] {
        return listSpaces().filter { $0.contains(displayUUID: displayUUID) }
    }
    
    
    private func findMatchingScreen(uuid: String, activeScreens: [NSScreen]) -> (CGDirectDisplayID?, CGRect?, Bool, String?) {
        // Use ColorSync API for perfect UUID to Display ID correlation
        guard let cfUuid = CFUUIDCreateFromString(nil, uuid as CFString) else {
            return (nil, nil, false, nil)
        }
        
        let displayID = CGDisplayGetDisplayIDFromUUID(cfUuid)
        
        // Display ID 0 means the display is not connected
        if displayID == 0 {
            return (nil, nil, false, nil)
        }
        
        // Find the matching NSScreen using the display ID
        for screen in activeScreens {
            if let screenDisplayID = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID,
               screenDisplayID == displayID {
                
                // Get the real display name
                let displayName = screen.localizedName
                
                return (displayID, screen.frame, screen == NSScreen.main, displayName)
            }
        }
        
        // Display ID found but no matching NSScreen (shouldn't happen for connected displays)
        return (displayID, nil, false, nil)
    }
    
    @available(macOS 14.0, *)
    private func getManagedDisplaySpaces() -> [[String: Any]] {
        let connectionID = CGSMainConnectionID()
        let displaySpacesRef = CGSCopyManagedDisplaySpaces(connectionID)
        
        // Convert CFArray to Swift array
        let displaySpaces = displaySpacesRef as! [[String: Any]]
        return displaySpaces
    }
    
    @available(macOS 14.0, *)
    private func getDisplayName(for displayUUID: String) -> String {
        // Use ColorSync correlation to get real display name
        guard let cfUuid = CFUUIDCreateFromString(nil, displayUUID as CFString) else {
            return displayUUID
        }
        
        let displayID = CGDisplayGetDisplayIDFromUUID(cfUuid)
        
        if displayID == 0 {
            return "Display \(String(displayUUID.prefix(8)))..."
        }
        
        // Find matching NSScreen for the display name
        for screen in NSScreen.screens {
            if let screenDisplayID = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID,
               screenDisplayID == displayID {
                
                let isMain = screen == NSScreen.main
                return isMain ? "\(screen.localizedName) (Main)" : screen.localizedName
            }
        }
        
        return "Display \(String(displayUUID.prefix(8)))..."
    }
    
    @available(macOS 14.0, *)
    private func getDisplayArrangement(for displayID: CGDirectDisplayID) -> Int {
        let screens = NSScreen.screens
        
        for (index, screen) in screens.enumerated() {
            if let screenDisplayID = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID,
               screenDisplayID == displayID {
                return index
            }
        }
        
        return -1
    }
    
    @available(macOS 14.0, *)
    public func getNativeSpaceTree() -> [String: Any] {
        let displaySpaces = getManagedDisplaySpaces()
        
        var result: [String: Any] = [:]
        var monitorsArray: [[String: Any]] = []
        
        // Track global space index exactly like spacespy
        var globalSpaceIndex = 1
        
        // Sort displays by their first space ID to match spacespy ordering
        let orderedDisplays = displaySpaces.sorted { display1, display2 in
            guard let spaces1 = display1["Spaces"] as? [[String: Any]],
                  let spaces2 = display2["Spaces"] as? [[String: Any]],
                  let firstSpace1 = spaces1.first?["id64"] as? NSNumber,
                  let firstSpace2 = spaces2.first?["id64"] as? NSNumber else {
                return false
            }
            return firstSpace1.compare(firstSpace2) == .orderedAscending
        }
        
        for display in orderedDisplays {
            guard let displayID = display["Display Identifier"] as? String,
                  let spaces = display["Spaces"] as? [[String: Any]],
                  let currentSpaceDict = display["Current Space"] as? [String: Any],
                  let currentSpace = currentSpaceDict["id64"] as? NSNumber else {
                continue
            }
            
            let monitorName = getDisplayName(for: displayID)
            
            // Get the display ID from UUID for arrangement
            var displayIDNum: CGDirectDisplayID = 0
            if let cfUuid = CFUUIDCreateFromString(nil, displayID as CFString) {
                displayIDNum = CGDisplayGetDisplayIDFromUUID(cfUuid)
            }
            
            var monitorInfo: [String: Any] = [:]
            monitorInfo["name"] = monitorName
            monitorInfo["uuid"] = displayID
            monitorInfo["display_number"] = getDisplayArrangement(for: displayIDNum) + 1
            
            var spacesArray: [[String: Any]] = []
            
            for space in spaces {
                guard let spaceID = space["id64"] as? NSNumber,
                      let managedSpaceID = space["ManagedSpaceID"] as? NSNumber,
                      let spaceUUID = space["uuid"] as? String else {
                    continue
                }
                
                // Use exact same current space detection method as spacespy
                let isCurrent = spaceID.isEqual(to: currentSpace)
                
                spacesArray.append([
                    "space_number": globalSpaceIndex,
                    "id": spaceID,
                    "managed_id": managedSpaceID,
                    "uuid": spaceUUID,
                    "is_current": isCurrent
                ])
                
                globalSpaceIndex += 1
            }
            
            monitorInfo["spaces"] = spacesArray
            monitorsArray.append(monitorInfo)
        }
        
        result["monitors"] = monitorsArray
        return result
    }
    
    public func getSpaceUUID(displayNumber: Int, spaceNumber: Int) -> String? {
        let spaceTree = getNativeSpaceTree()
        
        guard let monitors = spaceTree["monitors"] as? [[String: Any]] else {
            return nil
        }
        
        // Find the display by displayNumber
        guard let monitor = monitors.first(where: { 
            ($0["display_number"] as? Int) == displayNumber 
        }),
              let spaces = monitor["spaces"] as? [[String: Any]] else {
            return nil
        }
        
        // Find the space by spaceNumber within this display
        for space in spaces {
            if let currentSpaceNumber = space["space_number"] as? Int,
               let uuid = space["uuid"] as? String,
               currentSpaceNumber == spaceNumber {
                // Skip empty UUIDs - they represent system defaults that can't be set individually
                return uuid.isEmpty ? nil : uuid
            }
        }
        
        return nil
    }
    
    public func getAllSpaceUUIDs(for displayNumber: Int) -> [String] {
        let spaceTree = getNativeSpaceTree()
        
        guard let monitors = spaceTree["monitors"] as? [[String: Any]] else {
            return []
        }
        
        // Find the display by displayNumber
        guard let monitor = monitors.first(where: { 
            ($0["display_number"] as? Int) == displayNumber 
        }),
              let spaces = monitor["spaces"] as? [[String: Any]] else {
            return []
        }
        
        // Extract all UUIDs for this display, filtering out empty ones
        return spaces.compactMap { space in
            if let uuid = space["uuid"] as? String, !uuid.isEmpty {
                return uuid
            }
            return nil
        }
    }
}
