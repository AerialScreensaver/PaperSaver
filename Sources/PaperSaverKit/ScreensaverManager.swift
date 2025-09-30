import Foundation
import AppKit
import ColorSync

// Private CoreGraphics API declarations for native space detection
@_silgen_name("CGSMainConnectionID")
func CGSMainConnectionID() -> UInt32

@_silgen_name("CGSCopyManagedDisplaySpaces")
func CGSCopyManagedDisplaySpaces(_ cid: UInt32) -> CFArray

/// Represents different targeting options for screensaver configuration.
public enum ScreensaverTarget {
    /// Apply to all screens and spaces system-wide
    case everywhere
    /// Apply to a specific display by number
    case display(Int)
    /// Apply to a specific space by UUID
    case space(String)
    /// Apply to a specific space on a specific display
    case displaySpace(display: Int, space: Int)
}

public protocol ScreensaverManaging {
    func setScreensaver(module: String, screen: NSScreen?, skipRestart: Bool, enableDebug: Bool) async throws
    func getActiveScreensaver(for screen: NSScreen?) -> ScreensaverInfo?
    func getActiveScreensavers() -> [String]
    func setIdleTime(seconds: Int) throws
    func getIdleTime() -> Int
    func listAvailableScreensavers() -> [ScreensaverModule]
    
    @available(macOS 14.0, *)
    func setScreensaverForSpaceID(module: String, spaceID: Int, screen: NSScreen?, skipRestart: Bool, enableDebug: Bool) async throws
    
    @available(macOS 14.0, *)
    func setScreensaverForSpace(module: String, spaceUUID: String, screen: NSScreen?, skipRestart: Bool, enableDebug: Bool) async throws

    func setScreensaverEverywhere(module: String, skipRestart: Bool, enableDebug: Bool) async throws

    @available(macOS 14.0, *)
    func setScreensaverForDisplay(module: String, displayNumber: Int, skipRestart: Bool, enableDebug: Bool) async throws

    @available(macOS 14.0, *)
    func setScreensaverForDisplaySpace(module: String, displayNumber: Int, spaceNumber: Int, skipRestart: Bool, enableDebug: Bool) async throws
}

@available(macOS 14.0, *)
internal protocol SpaceManaging {
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
    
    public func setScreensaver(module: String, screen: NSScreen?, skipRestart: Bool = false, enableDebug: Bool = false) async throws {
        if #available(macOS 14.0, *) {
            // Sonoma+: Set screensaver appropriately based on configuration
            if screen == nil {
                // No specific screen - set everywhere
                try await setScreensaverEverywhere(module: module, skipRestart: skipRestart, enableDebug: enableDebug)
            } else {
                // Specific screen requested - set for default/current space on that screen
                try await setScreensaverForDefaultSpace(module: module, screen: screen, skipRestart: skipRestart, enableDebug: enableDebug)
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

        // Check in priority order matching macOS behavior:
        // 1. AllSpacesAndDisplays (highest priority - what system actually uses)
        // 2. Spaces[UUID] (medium priority - per-space configuration)
        // 3. SystemDefault (fallback)
        // Note: When "all spaces" mode is enabled for wallpapers, AllSpacesAndDisplays exists,
        // but screensavers can still be per-space. We check if AllSpacesAndDisplays has valid
        // screensaver data first, and fall back to Spaces[UUID] if it doesn't.
        var spaceConfig: [String: Any]?

        // Check if AllSpacesAndDisplays exists and has valid screensaver data
        if let allSpacesAndDisplays = plist["AllSpacesAndDisplays"] as? [String: Any] {
            var hasValidScreensaverData = false

            // Check if AllSpacesAndDisplays.Idle has non-empty configuration
            if let idle = allSpacesAndDisplays["Idle"] as? [String: Any],
               let content = idle["Content"] as? [String: Any],
               let choices = content["Choices"] as? [[String: Any]],
               let firstChoice = choices.first,
               let configurationData = firstChoice["Configuration"] as? Data,
               !configurationData.isEmpty {
                // AllSpacesAndDisplays.Idle has valid screensaver data
                hasValidScreensaverData = true
            }

            // Also check if AllSpacesAndDisplays.Linked has non-empty configuration (Automatic mode)
            if !hasValidScreensaverData,
               let linked = allSpacesAndDisplays["Linked"] as? [String: Any],
               let content = linked["Content"] as? [String: Any],
               let choices = content["Choices"] as? [[String: Any]],
               let firstChoice = choices.first,
               let configurationData = firstChoice["Configuration"] as? Data,
               !configurationData.isEmpty {
                // AllSpacesAndDisplays.Linked has valid screensaver data (Automatic mode)
                hasValidScreensaverData = true
            }

            if hasValidScreensaverData {
                spaceConfig = allSpacesAndDisplays
            }
        }

        // If AllSpacesAndDisplays doesn't have valid screensaver data, check Spaces for per-space config
        if spaceConfig == nil {
            if let spaces = plist["Spaces"] as? [String: Any], !spaces.isEmpty {
                // Then check Spaces structure (multi-space configuration)
                if let config = spaces[lookupUUID] as? [String: Any] {
                    spaceConfig = config
                } else if !lookupUUID.isEmpty {
                    // If specific UUID not found and it's not empty, try empty string (default)
                    spaceConfig = spaces[""] as? [String: Any]
                }
            }
        }

        // Final fallback to SystemDefault
        if spaceConfig == nil {
            if let systemDefault = plist["SystemDefault"] as? [String: Any] {
                spaceConfig = systemDefault
            }
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

        // Check if Linked is directly in config (SystemDefault or AllSpacesAndDisplays in Automatic mode)
        if let linked = config["Linked"] as? [String: Any],
           let content = linked["Content"] as? [String: Any],
           let choices = content["Choices"] as? [[String: Any]],
           let firstChoice = choices.first {

            // Check the Provider to determine if this is Automatic mode (wallpaper as screensaver)
            if let provider = firstChoice["Provider"] as? String {
                // In Automatic mode, the provider is a wallpaper provider, not a screensaver
                if provider == "com.apple.wallpaper.choice.image" ||
                   provider == "com.apple.wallpaper.choice.dynamic" ||
                   provider.starts(with: "com.apple.wallpaper.") {
                    return "Automatic"
                }
            }

            // If it's not Automatic mode, try to decode as screensaver
            if let configurationData = firstChoice["Configuration"] as? Data {
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

        // Also check for Linked configurations (dynamic desktop in Automatic mode)
        if let defaultConfig = config["Default"] as? [String: Any],
           let linked = defaultConfig["Linked"] as? [String: Any],
           let content = linked["Content"] as? [String: Any],
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

        // Check for Linked configurations without nested structure
        if let defaultConfig = config["Default"] as? [String: Any],
           let linked = defaultConfig["Linked"] as? [String: Any],
           let provider = linked["Provider"] as? String {

            // Handle com.apple.NeptuneOneExtension directly
            if provider == "com.apple.NeptuneOneExtension" {
                return "Dynamic Desktop"
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
            // First try Idle configuration
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

            // Also try Linked configuration (dynamic desktop in Automatic mode)
            if let displayConfig = displays[displayKey] as? [String: Any],
               let linked = displayConfig["Linked"] as? [String: Any],
               let content = linked["Content"] as? [String: Any],
               let choices = content["Choices"] as? [[String: Any]],
               let firstChoice = choices.first,
               let configurationData = firstChoice["Configuration"] as? Data {

                if let moduleName = try? plistManager.decodeScreensaverConfiguration(from: configurationData) {
                    return moduleName
                }
            }

            // Check for Linked configurations without nested structure
            if let displayConfig = displays[displayKey] as? [String: Any],
               let linked = displayConfig["Linked"] as? [String: Any],
               let provider = linked["Provider"] as? String {

                // Handle com.apple.NeptuneOneExtension directly
                if provider == "com.apple.NeptuneOneExtension" {
                    return "Dynamic Desktop"
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

    // MARK: - Pure Plist Modification Functions

    /// Modifies a plist to set screensaver configuration for a specific target
    @available(macOS 14.0, *)
    private func modifyPlistForTarget(
        _ plist: [String: Any],
        target: ScreensaverTarget,
        configurationData: Data
    ) throws -> [String: Any] {
        var modifiedPlist = plist

        switch target {
        case .everywhere:
            modifiedPlist = try modifyPlistForEverywhere(modifiedPlist, configurationData: configurationData)
        case .display(let displayNumber):
            modifiedPlist = try modifyPlistForDisplay(modifiedPlist, displayNumber: displayNumber, configurationData: configurationData)
        case .space(let spaceUUID):
            modifiedPlist = try modifyPlistForSpace(modifiedPlist, spaceUUID: spaceUUID, configurationData: configurationData)
        case .displaySpace(let displayNumber, let spaceNumber):
            guard let spaceUUID = getSpaceUUID(displayNumber: displayNumber, spaceNumber: spaceNumber) else {
                throw PaperSaverError.spaceNotFoundOnDisplay(displayNumber: displayNumber, spaceNumber: spaceNumber)
            }
            modifiedPlist = try modifyPlistForSpace(modifiedPlist, spaceUUID: spaceUUID, configurationData: configurationData)
        }

        return modifiedPlist
    }

    /// Modifies a plist to set screensaver everywhere
    @available(macOS 14.0, *)
    private func modifyPlistForEverywhere(
        _ plist: [String: Any],
        configurationData: Data
    ) throws -> [String: Any] {
        var modifiedPlist = plist

        // Always update AllSpacesAndDisplays first (highest priority)
        // This ensures the screensaver applies everywhere regardless of other configurations
        // Create fresh AllSpacesAndDisplays to avoid preserving Automatic mode (Linked section)
        // Setting an explicit screensaver switches from Automatic mode to explicit screensaver mode
        var allSpacesAndDisplays: [String: Any] = ["Type": "idle"]
        allSpacesAndDisplays["Idle"] = createIdleConfiguration(with: configurationData)
        modifiedPlist["AllSpacesAndDisplays"] = allSpacesAndDisplays

        // Check if we're in a single screen/space configuration
        if let spaces = plist["Spaces"] as? [String: Any], !spaces.isEmpty {
            // Multi-space configuration - set on all displays
            let spaceTree = getNativeSpaceTree()
            guard let monitors = spaceTree["monitors"] as? [[String: Any]] else {
                // Fallback to setting default space (which will update all sections)
                return try modifyPlistForDefaultSpace(modifiedPlist, configurationData: configurationData)
            }

            // Extract all display numbers and modify for each
            let displayNumbers = monitors.compactMap { monitor in
                monitor["display_number"] as? Int
            }

            for displayNumber in displayNumbers {
                modifiedPlist = try modifyPlistForDisplay(modifiedPlist, displayNumber: displayNumber, configurationData: configurationData)
            }
        }

        // Always update SystemDefault for compatibility
        var systemDefault = modifiedPlist["SystemDefault"] as? [String: Any] ?? ["Type": "individual"]
        systemDefault["Idle"] = createIdleConfiguration(with: configurationData)
        modifiedPlist["SystemDefault"] = systemDefault

        return modifiedPlist
    }

    /// Modifies a plist to set screensaver for default space
    @available(macOS 14.0, *)
    private func modifyPlistForDefaultSpace(
        _ plist: [String: Any],
        configurationData: Data
    ) throws -> [String: Any] {
        var modifiedPlist = plist

        // Update ALL relevant sections for consistency with macOS precedence
        // This ensures the screensaver is applied correctly regardless of which section macOS reads

        // 1. Always update AllSpacesAndDisplays (highest priority in macOS)
        // Create fresh AllSpacesAndDisplays to avoid preserving Automatic mode (Linked section)
        // Setting an explicit screensaver switches from Automatic mode to explicit screensaver mode
        var allSpacesAndDisplays: [String: Any] = ["Type": "idle"]
        allSpacesAndDisplays["Idle"] = createIdleConfiguration(with: configurationData)
        modifiedPlist["AllSpacesAndDisplays"] = allSpacesAndDisplays

        // 2. Update Spaces[""] if Spaces exists (medium priority)
        if let spaces = plist["Spaces"] as? [String: Any] {
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
            modifiedPlist["Spaces"] = spacesDict
        }

        // 3. Always update SystemDefault for compatibility (lowest priority)
        var systemDefault = modifiedPlist["SystemDefault"] as? [String: Any] ?? ["Type": "individual"]
        systemDefault["Idle"] = createIdleConfiguration(with: configurationData)
        modifiedPlist["SystemDefault"] = systemDefault

        return modifiedPlist
    }

    /// Modifies a plist to set screensaver for a specific display
    @available(macOS 14.0, *)
    private func modifyPlistForDisplay(
        _ plist: [String: Any],
        displayNumber: Int,
        configurationData: Data
    ) throws -> [String: Any] {
        var modifiedPlist = plist
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
        var spacesConfig = modifiedPlist["Spaces"] as? [String: Any] ?? [:]

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
        }

        modifiedPlist["Spaces"] = spacesConfig
        return modifiedPlist
    }

    /// Modifies a plist to set screensaver for a specific space
    @available(macOS 14.0, *)
    private func modifyPlistForSpace(
        _ plist: [String: Any],
        spaceUUID: String,
        configurationData: Data,
        displayUUID: String? = nil
    ) throws -> [String: Any] {
        var modifiedPlist = plist

        // Handle empty UUID case - this means we're setting for the default/current space
        if spaceUUID.isEmpty {
            return try modifyPlistForDefaultSpace(modifiedPlist, configurationData: configurationData)
        }

        // Get or create Spaces section
        var spaces = modifiedPlist["Spaces"] as? [String: Any] ?? [:]

        // Get or create the specific space
        var spaceConfig = spaces[spaceUUID] as? [String: Any] ?? [:]

        // Write to BOTH Default and Displays sections for consistency
        // Default section takes priority in reading, so write there first
        var defaultConfig = spaceConfig["Default"] as? [String: Any] ?? ["Type": "individual"]
        defaultConfig["Idle"] = createIdleConfiguration(with: configurationData)
        spaceConfig["Default"] = defaultConfig

        // Get or create Displays section for this space (for backward compatibility)
        var spaceDisplays = spaceConfig["Displays"] as? [String: Any] ?? [:]

        if let displayUUID = displayUUID {
            // Set screensaver for specific display
            var displayConfig = spaceDisplays[displayUUID] as? [String: Any] ?? ["Type": "individual"]
            displayConfig["Idle"] = createIdleConfiguration(with: configurationData)
            spaceDisplays[displayUUID] = displayConfig
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
        modifiedPlist["Spaces"] = spaces

        return modifiedPlist
    }

    // MARK: - Semantic Verification

    /// Verifies that a screensaver configuration was successfully applied for a given target
    /// This uses semantic verification (actual functionality) rather than file checksums
    @available(macOS 14.0, *)
    private func verifyScreensaverConfiguration(
        expectedModule: String,
        target: ScreensaverTarget
    ) async throws -> Bool {
        switch target {
        case .everywhere:
            return verifyScreensaverEverywhere(expectedModule: expectedModule)
        case .display(let displayNumber):
            return verifyScreensaverForDisplay(expectedModule: expectedModule, displayNumber: displayNumber)
        case .space(let spaceUUID):
            return verifyScreensaverForSpace(expectedModule: expectedModule, spaceUUID: spaceUUID)
        case .displaySpace(let displayNumber, let spaceNumber):
            guard let spaceUUID = getSpaceUUID(displayNumber: displayNumber, spaceNumber: spaceNumber) else {
                return false
            }
            return verifyScreensaverForSpace(expectedModule: expectedModule, spaceUUID: spaceUUID)
        }
    }

    /// Verifies screensaver is set everywhere by checking if it appears in active screensavers
    @available(macOS 14.0, *)
    private func verifyScreensaverEverywhere(expectedModule: String) -> Bool {
        let activeScreensavers = getActiveScreensavers()
        return activeScreensavers.contains(expectedModule)
    }

    /// Verifies screensaver is set for a specific display
    @available(macOS 14.0, *)
    private func verifyScreensaverForDisplay(expectedModule: String, displayNumber: Int) -> Bool {
        let spaceTree = getNativeSpaceTree()
        guard let monitors = spaceTree["monitors"] as? [[String: Any]] else {
            return false
        }

        // Find the display by displayNumber
        guard let monitor = monitors.first(where: {
            ($0["display_number"] as? Int) == displayNumber
        }),
              let spaces = monitor["spaces"] as? [[String: Any]] else {
            return false
        }

        // Check if any space on this display has the expected screensaver
        for space in spaces {
            guard let spaceUUID = space["uuid"] as? String else { continue }
            if let screensaverName = getScreensaverForSpaceUUID(spaceUUID),
               screensaverName == expectedModule {
                return true
            }
        }

        return false
    }

    /// Verifies screensaver is set for a specific space
    @available(macOS 14.0, *)
    private func verifyScreensaverForSpace(expectedModule: String, spaceUUID: String) -> Bool {
        guard let screensaverName = getScreensaverForSpaceUUID(spaceUUID) else {
            return false
        }
        return screensaverName == expectedModule
    }

    // MARK: - Unified Configuration Application

    /// Unified function to apply screensaver configuration for any target
    /// This performs: read once -> modify -> write once -> auto-rollback check
    @available(macOS 14.0, *)
    private func applyScreensaverConfiguration(
        module: String,
        target: ScreensaverTarget,
        skipRestart: Bool = false,
        enableDebug: Bool = false
    ) async throws {
        let indexPath = SystemPaths.wallpaperIndexPath

        // 1. Read plist once
        guard var plist = try? plistManager.read(at: indexPath) else {
            throw PaperSaverError.plistReadError(indexPath)
        }

        // 2. Get screensaver module URL and create configuration data
        guard let moduleURL = SystemPaths.screensaverModuleURL(for: module) else {
            throw PaperSaverError.screensaverNotFound(module)
        }

        let configurationData = try plistManager.createScreensaverConfiguration(moduleURL: moduleURL)

        // 3. Apply all modifications using pure functions
        plist = try modifyPlistForTarget(plist, target: target, configurationData: configurationData)

        // 4. Write once with semantic auto-rollback verification
        try await writeWithAutoRollback(
            plist,
            to: indexPath,
            restartAgent: !skipRestart,
            enableDebug: enableDebug,
            expectedModule: module,
            target: target
        )
    }

    @available(macOS 14.0, *)
    private func writeWithAutoRollback(
        _ plist: [String: Any],
        to path: String,
        restartAgent: Bool = true,
        waitSeconds: Double = 3.0,
        enableDebug: Bool = false,
        expectedModule: String? = nil,
        target: ScreensaverTarget? = nil
    ) async throws {
        if enableDebug {
            print("🔧 DEBUG: Starting writeWithAutoRollback")
            print("🔧 DEBUG: Target path: \(path)")
            print("🔧 DEBUG: Restart agent: \(restartAgent)")
        }

        // 1. Calculate PRE-write checksum for comparison
        let preWriteChecksum = try? plistManager.calculateChecksum(at: path)
        if enableDebug {
            print("🔧 DEBUG: Pre-write checksum: \(preWriteChecksum ?? "N/A")")
        }

        // 2. Write plist (backup automatically created)
        try plistManager.write(plist, to: path)

        // 3. Calculate post-write checksum
        let expectedChecksum = try plistManager.calculateChecksum(at: path)
        if enableDebug {
            print("🔧 DEBUG: Post-write checksum: \(expectedChecksum)")
            let fileSize = try? FileManager.default.attributesOfItem(atPath: path)[.size]
            print("🔧 DEBUG: File size after write: \(fileSize ?? "unknown")")
        }

        // 4. Restart agent if requested
        if restartAgent {
            if enableDebug {
                print("🔧 DEBUG: Restarting WallpaperAgent...")
            }
            restartWallpaperAgent()

            // 5. Wait for system to settle
            if enableDebug {
                print("🔧 DEBUG: Waiting \(waitSeconds) seconds for system to settle...")
            }
            try await Task.sleep(nanoseconds: UInt64(waitSeconds * 1_000_000_000))

            // 6. Verify configuration semantically (if verification parameters provided)
            if let expectedModule = expectedModule, let target = target {
                do {
                    let verificationResult = try await verifyScreensaverConfiguration(
                        expectedModule: expectedModule,
                        target: target
                    )

                    if enableDebug {
                        print("🔧 DEBUG: Semantic verification result: \(verificationResult ? "SUCCESS" : "FAILED")")
                        print("🔧 DEBUG: Expected module: \(expectedModule)")
                        print("🔧 DEBUG: Target: \(target)")
                    }

                    // 7. Auto-rollback if semantic verification failed
                    if !verificationResult {
                        print("⚠️ Semantic verification failed - screensaver configuration did not apply correctly")
                        if enableDebug {
                            print("🔧 DEBUG: Expected module '\(expectedModule)' not found for target \(target)")
                        }
                        print("🔧 Auto-rolling back...")
                        try plistManager.restore(backupAt: path + ".backup", to: path)
                        print("✅ Auto-rollback completed successfully")
                    } else if enableDebug {
                        print("🔧 DEBUG: Semantic verification passed - screensaver correctly applied")
                    }
                } catch {
                    print("⚠️ Unable to verify screensaver configuration after WallpaperAgent restart")
                    if enableDebug {
                        print("🔧 DEBUG: Verification error: \(error)")
                    }
                    print("🔧 Auto-rolling back...")
                    try plistManager.restore(backupAt: path + ".backup", to: path)
                    print("✅ Auto-rollback completed successfully")
                }
            } else if enableDebug {
                print("🔧 DEBUG: No verification parameters provided - skipping semantic verification")

                // Still show file changes for debugging purposes
                do {
                    let actualChecksum = try plistManager.calculateChecksum(at: path)
                    let fileSize = try? FileManager.default.attributesOfItem(atPath: path)[.size]
                    print("🔧 DEBUG: Post-restart checksum: \(actualChecksum)")
                    print("🔧 DEBUG: File size after restart: \(fileSize ?? "unknown")")
                    print("🔧 DEBUG: Checksums match: \(expectedChecksum == actualChecksum)")
                } catch {
                    print("🔧 DEBUG: Could not read post-restart file info: \(error)")
                }
            }
        }

        if enableDebug {
            print("🔧 DEBUG: writeWithAutoRollback completed")
        }
    }


    @available(macOS 14.0, *)
    public func setScreensaverForSpaceID(module: String, spaceID: Int, screen: NSScreen? = nil, skipRestart: Bool = false, enableDebug: Bool = false) async throws {
        guard let spaceInfo = getSpaceByID(spaceID) else {
            throw PaperSaverError.spaceNotFound
        }

        if spaceInfo.uuid.isEmpty {
            try await setScreensaver(module: module, screen: screen, skipRestart: skipRestart, enableDebug: enableDebug)
        } else {
            try await setScreensaverForSpace(module: module, spaceUUID: spaceInfo.uuid, screen: screen, skipRestart: skipRestart, enableDebug: enableDebug)
        }
    }
    
    @available(macOS 14.0, *)
    private func setScreensaverForDefaultSpace(module: String, screen: NSScreen? = nil, skipRestart: Bool = false, enableDebug: Bool = false) async throws {
        // For default space, we use empty space UUID
        let displayUUID = screen != nil ? getDisplayUUID(for: screen!) : nil

        // Use the pure function approach by modifying the existing one to handle displayUUID
        let indexPath = SystemPaths.wallpaperIndexPath
        guard var plist = try? plistManager.read(at: indexPath) else {
            throw PaperSaverError.plistReadError(indexPath)
        }

        guard let moduleURL = SystemPaths.screensaverModuleURL(for: module) else {
            throw PaperSaverError.screensaverNotFound(module)
        }

        let configurationData = try plistManager.createScreensaverConfiguration(moduleURL: moduleURL)
        plist = try modifyPlistForSpace(plist, spaceUUID: "", configurationData: configurationData, displayUUID: displayUUID)

        try await writeWithAutoRollback(
            plist,
            to: indexPath,
            restartAgent: !skipRestart,
            enableDebug: enableDebug,
            expectedModule: module,
            target: .space("")
        )
    }

    @available(macOS 14.0, *)
    public func setScreensaverForSpace(module: String, spaceUUID: String, screen: NSScreen? = nil, skipRestart: Bool = false, enableDebug: Bool = false) async throws {
        // Handle empty UUID case - this means we're setting for the default/current space
        if spaceUUID.isEmpty {
            try await setScreensaverForDefaultSpace(module: module, screen: screen, skipRestart: skipRestart, enableDebug: enableDebug)
            return
        }

        // Get displayUUID if screen is specified
        let displayUUID = screen != nil ? getDisplayUUID(for: screen!) : nil

        // Use the unified approach
        let indexPath = SystemPaths.wallpaperIndexPath
        guard var plist = try? plistManager.read(at: indexPath) else {
            throw PaperSaverError.plistReadError(indexPath)
        }

        guard let moduleURL = SystemPaths.screensaverModuleURL(for: module) else {
            throw PaperSaverError.screensaverNotFound(module)
        }

        let configurationData = try plistManager.createScreensaverConfiguration(moduleURL: moduleURL)
        plist = try modifyPlistForSpace(plist, spaceUUID: spaceUUID, configurationData: configurationData, displayUUID: displayUUID)

        try await writeWithAutoRollback(
            plist,
            to: indexPath,
            restartAgent: !skipRestart,
            enableDebug: enableDebug,
            expectedModule: module,
            target: .space(spaceUUID)
        )
    }


    public func setScreensaverEverywhere(module: String, skipRestart: Bool = false, enableDebug: Bool = false) async throws {
        if #available(macOS 14.0, *) {
            try await applyScreensaverConfiguration(
                module: module,
                target: .everywhere,
                skipRestart: skipRestart,
                enableDebug: enableDebug
            )
        } else {
            // Pre-Sonoma: Use legacy method to set on all screens
            try await setScreensaver(module: module, screen: nil, skipRestart: skipRestart, enableDebug: enableDebug)
        }
    }
    
    @available(macOS 14.0, *)
    public func setScreensaverForDisplay(module: String, displayNumber: Int, skipRestart: Bool = false, enableDebug: Bool = false) async throws {
        try await applyScreensaverConfiguration(
            module: module,
            target: .display(displayNumber),
            skipRestart: skipRestart,
            enableDebug: enableDebug
        )
    }

    @available(macOS 14.0, *)
    public func setScreensaverForDisplaySpace(module: String, displayNumber: Int, spaceNumber: Int, skipRestart: Bool = false, enableDebug: Bool = false) async throws {
        try await applyScreensaverConfiguration(
            module: module,
            target: .displaySpace(display: displayNumber, space: spaceNumber),
            skipRestart: skipRestart,
            enableDebug: enableDebug
        )
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
