import Foundation
import AppKit

/// Identifies which wallpaper "slot" an extension should occupy.
///
/// macOS Sonoma+ stores the desktop wallpaper and the screensaver ("idle"
/// wallpaper) as two independent slots in the same wallpaper store. A single
/// extension (an `.appex` declaring `EXExtensionPointIdentifier com.apple.wallpaper`)
/// can occupy either or both.
public enum WallpaperExtensionSlot: Sendable {
    /// The desktop wallpaper slot only.
    case desktop
    /// The screensaver (idle) slot only.
    case screensaver
    /// Both the desktop and screensaver slots.
    case both

    var includesDesktop: Bool {
        switch self {
        case .desktop, .both: return true
        case .screensaver: return false
        }
    }

    var includesScreensaver: Bool {
        switch self {
        case .screensaver, .both: return true
        case .desktop: return false
        }
    }
}

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

    // MARK: Wallpaper / Screensaver Extensions (macOS 14.0+)

    @available(macOS 14.0, *)
    func setWallpaperExtension(bundleID: String, configuration: Data, slot: WallpaperExtensionSlot, optionValues: [String: Any]?, skipRestart: Bool) async throws

    @available(macOS 14.0, *)
    func getCurrentWallpaperExtension(for screen: NSScreen?) -> String?

    @available(macOS 14.0, *)
    func getCurrentScreensaverExtension(for screen: NSScreen?) -> String?
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
    
    // MARK: - Wallpaper / Screensaver Extensions (macOS 14.0+)

    /// Activates a wallpaper/screensaver extension by its bundle identifier.
    ///
    /// Writes the extension choice into the wallpaper store's Desktop slot (wallpaper)
    /// and/or Idle slot (screensaver) across `AllSpacesAndDisplays`, `SystemDefault`, and
    /// any per-space entries, then restarts WallpaperAgent. Mirrors the screensaver path
    /// (`ScreensaverManager`), which uses the same plist mechanism.
    @available(macOS 14.0, *)
    public func setWallpaperExtension(
        bundleID: String,
        configuration: Data,
        slot: WallpaperExtensionSlot = .both,
        optionValues: [String: Any]? = nil,
        skipRestart: Bool = false
    ) async throws {
        guard !bundleID.isEmpty else {
            throw PaperSaverError.invalidConfiguration("Extension bundle identifier cannot be empty")
        }

        let indexPath = SystemPaths.wallpaperIndexPath
        guard var plist = try? plistManager.read(at: indexPath) else {
            throw PaperSaverError.plistReadError(indexPath)
        }

        // WallpaperAgent rejects under-specified desktop choices (it resets to "no
        // wallpaper" on restart), so the desktop slot must carry COMPLETE option values
        // matching what System Settings records: both a "placement" AND a background
        // "color". Omitting "color" is enough to make the agent reject the whole choice.
        // The idle (screensaver) slot, by contrast, uses empty option values as the system does.
        let desktopOptions = optionValues ?? defaultDesktopOptionValues()
        let desktopSlot = slot.includesDesktop
            ? try makeExtensionSlotConfiguration(provider: bundleID, configuration: configuration, optionValues: desktopOptions)
            : nil
        let idleSlot = slot.includesScreensaver
            ? try makeExtensionSlotConfiguration(provider: bundleID, configuration: configuration, optionValues: [:])
            : nil

        plist = applyExtensionSlots(to: plist, desktop: desktopSlot, idle: idleSlot)

        try await writeExtensionWithRollback(
            plist,
            to: indexPath,
            restartAgent: !skipRestart,
            slot: slot,
            expectedProvider: bundleID
        )
    }

    /// The bundle identifier of the extension currently set as the desktop wallpaper,
    /// or `nil` if the desktop wallpaper is not an extension (e.g. a plain image).
    @available(macOS 14.0, *)
    public func getCurrentWallpaperExtension(for screen: NSScreen? = nil) -> String? {
        return currentExtensionProvider(slotKey: "Desktop")
    }

    /// The bundle identifier of the extension currently set as the screensaver,
    /// or `nil` if the screensaver is not a wallpaper-style extension.
    @available(macOS 14.0, *)
    public func getCurrentScreensaverExtension(for screen: NSScreen? = nil) -> String? {
        return currentExtensionProvider(slotKey: "Idle")
    }

    // MARK: Extension helpers

    /// Complete default option values for a desktop wallpaper-extension choice: a "Crop"
    /// placement plus an opaque-black background color. WallpaperAgent requires the desktop
    /// slot to carry a background color or it rejects the choice; the value is otherwise
    /// cosmetic (only visible behind a non-filling wallpaper). Callers may override via
    /// `setWallpaperExtension(optionValues:)`.
    func defaultDesktopOptionValues() -> [String: Any] {
        return [
            "placement": ["picker": ["_0": ["id": "Crop"]]],
            "color": defaultBackgroundColor()
        ]
    }

    /// The background-color structure WallpaperAgent records for a desktop choice
    /// (opaque black in the generic RGB color space).
    private func defaultBackgroundColor() -> [String: Any] {
        // `colorSpace` is an archived plist of the color-space name string, exactly as the
        // system stores it (`bplist00` + "kCGColorSpaceGenericRGB").
        let colorSpaceData = (try? PropertyListSerialization.data(
            fromPropertyList: "kCGColorSpaceGenericRGB", format: .binary, options: 0)) ?? Data()
        return [
            "color": [
                "color": [
                    "_0": [
                        "color": [
                            "components": [0.0, 0.0, 0.0, 1.0],
                            "colorSpace": colorSpaceData
                        ]
                    ]
                ]
            ]
        ]
    }

    /// Builds a single slot ("Desktop" or "Idle") value for a wallpaper-extension choice.
    /// Internal (not private) so tests can validate the structure without touching the system.
    func makeExtensionSlotConfiguration(
        provider: String,
        configuration: Data,
        optionValues: [String: Any]?
    ) throws -> [String: Any] {
        var content: [String: Any] = [
            "Choices": [
                [
                    "Provider": provider,
                    "Configuration": configuration,
                    "Files": []
                ]
            ]
        ]
        // EncodedOptionValues is a binary plist of {"values": <dict>}. The system tolerates
        // an empty values dictionary; the extension supplies its own defaults.
        content["EncodedOptionValues"] = try plistManager.createBinaryPlist(from: ["values": optionValues ?? [:]])
        // The system records a "$null" Shuffle sentinel; include it so the written choice is
        // structurally complete. WallpaperAgent rejects under-specified extension choices.
        content["Shuffle"] = "$null"

        return [
            "Content": content,
            "LastSet": Date(),
            "LastUse": Date()
        ]
    }

    /// Writes the given slot configurations into every relevant section of the wallpaper
    /// store, preserving the slot we are not setting. Handles both "all spaces" mode
    /// (`AllSpacesAndDisplays` + `SystemDefault`) and per-space mode (each `Spaces` entry's
    /// `Default`).
    /// Internal (not private) so tests can validate the structure without touching the system.
    func applyExtensionSlots(
        to plist: [String: Any],
        desktop: [String: Any]?,
        idle: [String: Any]?
    ) -> [String: Any] {
        var modified = plist

        func apply(into config: [String: Any]?) -> [String: Any] {
            var c = config ?? [:]
            if let desktop { c["Desktop"] = desktop }
            if let idle { c["Idle"] = idle }
            // Force "individual" mode and drop any "Linked" (automatic-mode) block. When no
            // wallpaper is set the agent puts the section in linked/automatic mode
            // (Type=linked + a Linked block with Provider "default"); leaving that in place
            // makes the agent ignore the Desktop/Idle choices we just wrote.
            c["Type"] = "individual"
            c.removeValue(forKey: "Linked")
            return c
        }

        // Top-level sections the system reads in "all spaces" mode.
        modified["AllSpacesAndDisplays"] = apply(into: modified["AllSpacesAndDisplays"] as? [String: Any])
        modified["SystemDefault"] = apply(into: modified["SystemDefault"] as? [String: Any])

        // Per-space mode: also update each existing space's Default section.
        if let spaces = modified["Spaces"] as? [String: Any], !spaces.isEmpty {
            var updatedSpaces = spaces
            for (uuid, value) in spaces {
                guard var spaceConfig = value as? [String: Any] else { continue }
                spaceConfig["Default"] = apply(into: spaceConfig["Default"] as? [String: Any])
                updatedSpaces[uuid] = spaceConfig
            }
            modified["Spaces"] = updatedSpaces
        }

        return modified
    }

    /// Reads the provider (extension bundle ID) currently occupying the given slot,
    /// honoring `AllSpacesAndDisplays` → `Spaces` → `SystemDefault` precedence.
    private func currentExtensionProvider(slotKey: String) -> String? {
        guard let plist = try? plistManager.read(at: SystemPaths.wallpaperIndexPath) else {
            return nil
        }

        if let provider = providerInSection(plist["AllSpacesAndDisplays"] as? [String: Any], slotKey: slotKey) {
            return provider
        }

        if let spaces = plist["Spaces"] as? [String: Any] {
            for (_, value) in spaces {
                if let provider = providerInSection((value as? [String: Any])?["Default"] as? [String: Any], slotKey: slotKey) {
                    return provider
                }
            }
        }

        return providerInSection(plist["SystemDefault"] as? [String: Any], slotKey: slotKey)
    }

    private func providerInSection(_ section: [String: Any]?, slotKey: String) -> String? {
        guard let slot = section?[slotKey] as? [String: Any],
              let content = slot["Content"] as? [String: Any],
              let choices = content["Choices"] as? [[String: Any]],
              let provider = choices.first?["Provider"] as? String else {
            return nil
        }
        return provider
    }

    /// Writes the plist, restarts WallpaperAgent, and verifies the extension took effect.
    /// On a verification mismatch it throws (leaving the written, structurally-valid plist
    /// in place rather than risking undoing a change that actually applied).
    private func writeExtensionWithRollback(
        _ plist: [String: Any],
        to path: String,
        restartAgent: Bool,
        waitSeconds: Double = 3.0,
        slot: WallpaperExtensionSlot,
        expectedProvider: String
    ) async throws {
        try plistManager.write(plist, to: path)   // creates a .backup automatically

        guard restartAgent else { return }

        restartWallpaperAgent()
        try await Task.sleep(nanoseconds: UInt64(waitSeconds * 1_000_000_000))

        var applied = true
        if slot.includesDesktop {
            applied = applied && (currentExtensionProvider(slotKey: "Desktop") == expectedProvider)
        }
        if slot.includesScreensaver {
            applied = applied && (currentExtensionProvider(slotKey: "Idle") == expectedProvider)
        }

        if !applied {
            throw PaperSaverError.invalidConfiguration(
                "Wallpaper extension '\(expectedProvider)' did not apply after WallpaperAgent restart"
            )
        }
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