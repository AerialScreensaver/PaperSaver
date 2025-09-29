import Foundation
import PaperSaverKit
import AppKit

@main
struct PaperSaverCLI {
    static let version = "0.1.0"
    
    enum Command: String, CaseIterable {
        case list
        case get
        case idleTime = "idle-time"
        case listSpaces = "list-spaces"
        case listDisplays = "list-displays"
        case getSpace = "get-space"
        case setSaver = "set-saver"
        case setPaper = "set-paper"
        case restoreBackup = "restore-backup"
        case version
        case help
        
    }
    
    enum OutputFormat: String {
        case text
        case json
    }
    
    static func main() async {
        let args = Array(CommandLine.arguments.dropFirst())
        
        guard !args.isEmpty else {
            printUsage()
            exit(0)
        }
        
        let commandString = args[0]
        
        if commandString == "--version" {
            print("papersaver version \(version)")
            exit(0)
        }
        
        if commandString == "--help" || commandString == "-h" {
            printUsage()
            exit(0)
        }
        
        guard let command = Command(rawValue: commandString) else {
            printError("Unknown command: '\(commandString)'")
            printUsage()
            exit(1)
        }
        
        do {
            try await executeCommand(command, args: Array(args.dropFirst()))
        } catch {
            printError("Error: \(error.localizedDescription)")
            exit(1)
        }
    }
    
    static func executeCommand(_ command: Command, args: [String]) async throws {
        let paperSaver = PaperSaver()
        
        switch command {
        case .list:
            try listScreensavers(paperSaver, args: args)
            
        case .get:
            try getScreensaver(paperSaver, args: args)
            
        case .idleTime:
            try handleIdleTime(paperSaver, args: args)
            
        case .listSpaces:
            if #available(macOS 14.0, *) {
                handleListSpaces(paperSaver, args: args)
            } else {
                printError("Error: Space commands require macOS 14.0 (Sonoma) or later")
                exit(1)
            }
            
        case .listDisplays:
            if #available(macOS 14.0, *) {
                handleListDisplays(paperSaver, args: args)
            } else {
                printError("Error: Space commands require macOS 14.0 (Sonoma) or later")
                exit(1)
            }
            
        case .getSpace:
            if #available(macOS 14.0, *) {
                handleGetSpace(paperSaver, args: args)
            } else {
                printError("Error: Space commands require macOS 14.0 (Sonoma) or later")
                exit(1)
            }
            
        case .setSaver:
            guard !args.isEmpty else {
                printError("Error: Screensaver name required")
                print("Usage: papersaver set-saver <screensaver-name> [targeting-options]")
                exit(1)
            }
            try await handleUnifiedSetSaver(paperSaver, screensaverName: args[0], args: Array(args.dropFirst()))
            
        case .setPaper:
            guard !args.isEmpty else {
                printError("Error: Wallpaper path required")
                print("Usage: papersaver set-paper <image-path> [targeting-options]")
                exit(1)
            }
            try await handleUnifiedSetPaper(paperSaver, imagePath: args[0], args: Array(args.dropFirst()))
            
        case .restoreBackup:
            if #available(macOS 14.0, *) {
                try await handleRestore(paperSaver, args: args)
            } else {
                printError("Error: Restore requires macOS 14.0 (Sonoma) or later")
                exit(1)
            }
            
        case .version:
            print("papersaver version \(version)")
            
        case .help:
            printUsage()
        }
    }
    
    static func listScreensavers(_ paperSaver: PaperSaver, args: [String]) throws {
        let format = getOutputFormat(from: args)
        let verbose = args.contains("--verbose") || args.contains("-v")
        let screensavers = paperSaver.listAvailableScreensavers()
        
        switch format {
        case .json:
            let jsonData = try JSONEncoder().encode(screensavers)
            print(String(data: jsonData, encoding: .utf8)!)
            
        case .text:
            if screensavers.isEmpty {
                print("No screensavers found")
                return
            }
            
            print("Available Screensavers:")
            print("=" * 50)
            
            let systemScreensavers = screensavers.filter { $0.isSystem }
            let userScreensavers = screensavers.filter { !$0.isSystem }
            
            if !systemScreensavers.isEmpty {
                print("\nSystem Screensavers:")
                for saver in systemScreensavers {
                    print("  • \(saver.name) (\(saver.type.displayName))")
                    if verbose {
                        print("    Path: \(saver.path.path)")
                    }
                }
            }
            
            if !userScreensavers.isEmpty {
                print("\nUser Screensavers:")
                for saver in userScreensavers {
                    print("  • \(saver.name) (\(saver.type.displayName))")
                    if verbose {
                        print("    Path: \(saver.path.path)")
                    }
                }
            }
            
            print("\nTotal: \(screensavers.count) screensaver(s)")
        }
    }
    
    static func getScreensaver(_ paperSaver: PaperSaver, args: [String]) throws {
        let format = getOutputFormat(from: args)
        let screen = getScreen(from: args)
        
        guard let info = paperSaver.getActiveScreensaver(for: screen) else {
            if format == .json {
                print("{}")
            } else {
                print("No screensaver currently set")
            }
            return
        }
        
        switch format {
        case .json:
            let jsonData = try JSONEncoder().encode(info)
            print(String(data: jsonData, encoding: .utf8)!)
            
        case .text:
            print("Current Screensaver: \(info.name)")
            if let screenInfo = info.screen {
                print("Display ID: \(screenInfo.displayID)")
            }
        }
    }
    
    static func setScreensaver(_ paperSaver: PaperSaver, name: String, args: [String]) async throws {
        let screen = getScreen(from: args)
        let verbose = args.contains("--verbose") || args.contains("-v")
        
        if verbose {
            print("Setting screensaver to '\(name)'...")
            if screen != nil {
                print("Target: Specific screen")
            } else {
                print("Target: All screens")
            }
        }
        
        do {
            try await paperSaver.setScreensaver(module: name, for: screen)

            print("✅ Successfully set screensaver to: \(name)")

            if verbose {
                print("\nNote: You may need to restart the wallpaper agent for changes to take effect:")
                print("  killall WallpaperAgent")
            }
        } catch {
            throw error
        }
    }
    
    static func handleIdleTime(_ paperSaver: PaperSaver, args: [String]) throws {
        guard !args.isEmpty else {
            let idleTime = paperSaver.getIdleTime()
            print("Current idle time: \(formatIdleTime(idleTime))")
            return
        }
        
        let subcommand = args[0]
        
        switch subcommand {
        case "get":
            let idleTime = paperSaver.getIdleTime()
            let format = getOutputFormat(from: args)
            
            if format == .json {
                print("{\"idleTime\": \(idleTime)}")
            } else {
                print("Current idle time: \(formatIdleTime(idleTime))")
            }
            
        case "set":
            guard args.count >= 2, let seconds = Int(args[1]) else {
                printError("Error: Invalid idle time value")
                print("Usage: papersaver idle-time set <seconds>")
                exit(1)
            }
            
            try paperSaver.setIdleTime(seconds: seconds)
            print("✅ Idle time set to: \(formatIdleTime(seconds))")
            
        default:
            if let seconds = Int(subcommand) {
                try paperSaver.setIdleTime(seconds: seconds)
                print("✅ Idle time set to: \(formatIdleTime(seconds))")
            } else {
                printError("Error: Invalid subcommand '\(subcommand)'")
                print("Usage: papersaver idle-time [get|set <seconds>]")
                exit(1)
            }
        }
    }
    
    
    static func formatIdleTime(_ seconds: Int) -> String {
        if seconds == 0 {
            return "Never"
        } else if seconds < 60 {
            return "\(seconds) seconds"
        } else if seconds < 3600 {
            let minutes = seconds / 60
            return "\(minutes) minute\(minutes == 1 ? "" : "s")"
        } else {
            let hours = seconds / 3600
            let remainingMinutes = (seconds % 3600) / 60
            if remainingMinutes == 0 {
                return "\(hours) hour\(hours == 1 ? "" : "s")"
            } else {
                return "\(hours) hour\(hours == 1 ? "" : "s") \(remainingMinutes) minute\(remainingMinutes == 1 ? "" : "s")"
            }
        }
    }
    
    static func getScreen(from args: [String]) -> NSScreen? {
        guard let index = args.firstIndex(of: "--screen") ?? args.firstIndex(of: "-s"),
              index + 1 < args.count else {
            return nil
        }
        
        return NSScreen.main
    }
    
    static func getOutputFormat(from args: [String]) -> OutputFormat {
        if args.contains("--json") || args.contains("-j") {
            return .json
        }
        return .text
    }
    
    @available(macOS 14.0, *)
    static func handleListSpaces(_ paperSaver: PaperSaver, args: [String]) {
        let format = getOutputFormat(from: args)
        
        // Tree view using native space detection
        let spaceTree = paperSaver.getNativeSpaceTree()
        
        switch format {
        case .json:
            if let jsonData = try? JSONSerialization.data(withJSONObject: spaceTree, options: .prettyPrinted),
               let jsonString = String(data: jsonData, encoding: .utf8) {
                print(jsonString)
            } else {
                print("{}")
            }
            
        case .text:
            let debug = args.contains("--debug")
            if debug {
                print("=== DEBUG INFO ===")
                print("Timestamp: \(Date())")
                print("Raw space tree keys: \(spaceTree.keys.sorted())")
                if let monitors = spaceTree["monitors"] as? [[String: Any]] {
                    print("Monitor count: \(monitors.count)")
                    for (i, monitor) in monitors.enumerated() {
                        print("Monitor \(i) keys: \(monitor.keys.sorted())")
                    }
                }
                print("==================\n")
            }
            printSpaceTree(paperSaver, spaceTree, debug: debug)
        }
    }
    
    @available(macOS 14.0, *)
    static func getScreensaverForSpace(_ paperSaver: PaperSaver, spaceUUID: String, debug: Bool = false) -> String? {
        let plistManager = PlistManager.shared
        let indexPath = SystemPaths.wallpaperIndexPath
        
        // Handle empty UUID case - fallback to default space configuration
        let lookupUUID = spaceUUID.isEmpty ? "" : spaceUUID
        
        if debug {
            print("DEBUG: Looking up screensaver for space UUID: '\(spaceUUID)'")
            print("DEBUG: Using lookup UUID: '\(lookupUUID)'")
        }
        
        guard let plist = try? plistManager.read(at: indexPath) else {
            if debug { print("DEBUG: Failed to read plist") }
            return nil
        }

        // Check in priority order matching macOS behavior:
        // 1. AllSpacesAndDisplays (highest priority - what system actually uses)
        // 2. Spaces[UUID] (medium priority)
        // 3. SystemDefault (fallback)
        var spaceConfig: [String: Any]?

        if let allSpacesAndDisplays = plist["AllSpacesAndDisplays"] as? [String: Any] {
            // Handle single screen/space configuration with AllSpacesAndDisplays (takes precedence)
            if debug { print("DEBUG: Using AllSpacesAndDisplays configuration (highest priority)") }
            spaceConfig = allSpacesAndDisplays
        } else if let spaces = plist["Spaces"] as? [String: Any], !spaces.isEmpty {
            if debug {
                print("DEBUG: Found \(spaces.keys.count) space configurations in plist")
                print("DEBUG: Space keys available: \(spaces.keys.sorted())")
            }

            // Try the specific space UUID first
            if let config = spaces[lookupUUID] as? [String: Any] {
                spaceConfig = config
                if debug { print("DEBUG: Found exact match for UUID '\(lookupUUID)'") }
            } else if !lookupUUID.isEmpty {
                // If specific UUID not found and it's not empty, try empty string (default)
                spaceConfig = spaces[""] as? [String: Any]
                if debug {
                    if spaceConfig != nil {
                        print("DEBUG: UUID '\(lookupUUID)' not found, using default space configuration")
                    } else {
                        print("DEBUG: UUID '\(lookupUUID)' not found, and no default configuration available")
                    }
                }
            }
        } else if let systemDefault = plist["SystemDefault"] as? [String: Any] {
            // Handle single screen/space configuration with SystemDefault (fallback)
            if debug { print("DEBUG: Using SystemDefault configuration (lowest priority)") }
            spaceConfig = systemDefault
        }

        guard let config = spaceConfig else {
            if debug { print("DEBUG: No valid space config found") }
            return nil
        }

        if debug {
            print("DEBUG: Space UUID value: '\(spaceUUID)', isEmpty: \(spaceUUID.isEmpty)")
        }

        // Check if Idle is directly in config (SystemDefault case)
        if let idle = config["Idle"] as? [String: Any],
           let content = idle["Content"] as? [String: Any],
           let choices = content["Choices"] as? [[String: Any]],
           let firstChoice = choices.first,
           let configurationData = firstChoice["Configuration"] as? Data {

            if debug {
                print("DEBUG: Using direct Idle configuration (SystemDefault)")
            }

            // Use the new type-aware decoding method
            if let (name, type) = try? plistManager.decodeScreensaverConfigurationWithType(from: configurationData) {
                if let screensaverName = name {
                    if debug {
                        print("DEBUG: Successfully decoded screensaver name from SystemDefault: '\(screensaverName)' type: '\(type.displayName)'")
                    }
                    return "\(screensaverName) (\(type.displayName))"
                }
            }

            // Fallback to old method for compatibility
            if let moduleName = try? plistManager.decodeScreensaverConfiguration(from: configurationData) {
                if debug {
                    print("DEBUG: Old method decoded module name from SystemDefault: '\(moduleName)'")
                }
                return moduleName
            }
        }

        // For ALL spaces, prioritize Default -> Idle over Displays
        // This ensures consistent behavior regardless of UUID
        if debug {
            print("DEBUG: Checking for Default section for space UUID '\(spaceUUID)'")
            if let defaultConfig = config["Default"] as? [String: Any] {
                print("DEBUG: Found Default config")
                if defaultConfig["Idle"] is [String: Any] {
                    print("DEBUG: Found Idle in Default")
                }
            }
        }
        if let defaultConfig = config["Default"] as? [String: Any],
           let idle = defaultConfig["Idle"] as? [String: Any],
           let content = idle["Content"] as? [String: Any],
           let choices = content["Choices"] as? [[String: Any]],
           let firstChoice = choices.first,
           let configurationData = firstChoice["Configuration"] as? Data {

            if debug {
                print("DEBUG: Using Default -> Idle configuration for space UUID '\(spaceUUID)'")
            }

            // Use the new type-aware decoding method
            if let (name, type) = try? plistManager.decodeScreensaverConfigurationWithType(from: configurationData) {
                if let screensaverName = name {
                    if debug {
                        print("DEBUG: Successfully decoded screensaver name from Default: '\(screensaverName)' type: '\(type.displayName)'")
                    }
                    return "\(screensaverName) (\(type.displayName))"
                }
            }

            // Fallback to old method for compatibility
            if let moduleName = try? plistManager.decodeScreensaverConfiguration(from: configurationData) {
                if debug {
                    print("DEBUG: Old method decoded module name from Default: '\(moduleName)'")
                }
                return moduleName
            }
        }

        // Fall back to Displays section (only if Default doesn't exist or fails)
        guard let displays = config["Displays"] as? [String: Any] else {
            if debug { print("DEBUG: No Displays found in space config") }
            return nil
        }
        
        if debug {
            print("DEBUG: Found \(displays.keys.count) displays in space configuration")
        }
        
        // Get connected displays to prioritize active display
        let connectedDisplays = paperSaver.listDisplays().filter { $0.isConnected }
        let connectedUUIDs = Set(connectedDisplays.map { $0.uuid })
        
        if debug {
            print("DEBUG: Connected display UUIDs: \(connectedUUIDs)")
            print("DEBUG: Available display keys in space: \(displays.keys.sorted())")
        }
        
        // Helper function to validate display keys
        func isValidDisplayKey(_ key: String) -> Bool {
            // Valid display keys are UUIDs in format XXXXXXXX-XXXX-XXXX-XXXX-XXXXXXXXXXXX
            // Invalid keys include "Main", numeric strings, or other non-UUID formats
            let uuidPattern = "^[0-9A-F]{8}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{12}$"
            let regex = try? NSRegularExpression(pattern: uuidPattern, options: [.caseInsensitive])
            let range = NSRange(location: 0, length: key.count)
            return regex?.firstMatch(in: key, options: [], range: range) != nil
        }

        // Find the connected display first, fall back to sorted order
        var displayKeysToCheck: [String] = []

        // First, add any connected displays (but only valid ones)
        for displayKey in displays.keys {
            guard isValidDisplayKey(displayKey) else {
                if debug {
                    print("DEBUG: Skipping invalid display key: '\(displayKey)'")
                }
                continue
            }
            if connectedUUIDs.contains(displayKey) {
                displayKeysToCheck.append(displayKey)
                if debug {
                    print("DEBUG: Found connected display: \(displayKey)")
                }
            }
        }

        // Then add remaining valid displays in sorted order (for fallback)
        let validDisplayKeys = displays.keys.filter(isValidDisplayKey).sorted()
        for displayKey in validDisplayKeys {
            if !displayKeysToCheck.contains(displayKey) {
                displayKeysToCheck.append(displayKey)
            }
        }
        
        if debug {
            print("DEBUG: Processing displays in priority order: \(displayKeysToCheck)")
        }
        
        // Look for screensaver in each display configuration (prioritized order)
        for (index, displayKey) in displayKeysToCheck.enumerated() {
            if debug {
                print("DEBUG: Processing display [\(index)]: '\(displayKey)'")
            }
            
            guard let displayValue = displays[displayKey],
                  let displayConfig = displayValue as? [String: Any] else {
                if debug { print("DEBUG: Display '\(displayKey)' has no valid configuration") }
                continue
            }
            
            if debug {
                print("DEBUG: Display '\(displayKey)' config keys: \(displayConfig.keys.sorted())")
            }
            
            guard let idle = displayConfig["Idle"] as? [String: Any] else {
                if debug { print("DEBUG: Display '\(displayKey)' has no Idle configuration") }
                continue
            }
            
            if debug {
                print("DEBUG: Display '\(displayKey)' Idle keys: \(idle.keys.sorted())")
            }
            
            guard let content = idle["Content"] as? [String: Any] else {
                if debug { print("DEBUG: Display '\(displayKey)' Idle has no Content") }
                continue
            }
            
            if debug {
                print("DEBUG: Display '\(displayKey)' Content keys: \(content.keys.sorted())")
            }
            
            guard let choices = content["Choices"] as? [[String: Any]] else {
                if debug { print("DEBUG: Display '\(displayKey)' Content has no Choices array") }
                continue
            }
            
            if debug {
                print("DEBUG: Display '\(displayKey)' has \(choices.count) choice(s)")
            }
            
            guard let firstChoice = choices.first else {
                if debug { print("DEBUG: Display '\(displayKey)' has empty Choices array") }
                continue
            }
            
            if debug {
                print("DEBUG: Display '\(displayKey)' first choice keys: \(firstChoice.keys.sorted())")
            }
            
            guard let provider = firstChoice["Provider"] as? String else {
                if debug { print("DEBUG: Display '\(displayKey)' first choice has no Provider") }
                continue
            }
            
            if debug {
                print("DEBUG: Display '\(displayKey)' provider: '\(provider)'")
            }
            
            guard let configurationData = firstChoice["Configuration"] as? Data else {
                if debug { print("DEBUG: Display '\(displayKey)' first choice has no Configuration data") }
                continue
            }
            
            if debug {
                print("DEBUG: Display '\(displayKey)' configuration data size: \(configurationData.count) bytes")
            }
            
            // Use the new type-aware decoding method
            if let (name, type) = try? plistManager.decodeScreensaverConfigurationWithType(from: configurationData) {
                if let screensaverName = name {
                    if debug {
                        print("DEBUG: Successfully decoded screensaver name: '\(screensaverName)' type: '\(type.displayName)'")
                    }
                    return "\(screensaverName) (\(type.displayName))"
                } else {
                    if debug {
                        print("DEBUG: Decoded configuration but got nil name, type: '\(type.displayName)'")
                    }
                }
            } else {
                if debug {
                    print("DEBUG: Failed to decode with new type-aware method, trying old method")
                }
            }
            
            // Fallback to old method for compatibility
            if let moduleName = try? plistManager.decodeScreensaverConfiguration(from: configurationData) {
                if debug {
                    print("DEBUG: Old method decoded module name: '\(moduleName)'")
                }
                return moduleName
            } else {
                if debug {
                    print("DEBUG: Old method also failed to decode configuration")
                }
            }
            
            // If all else fails, show provider info with proper type mapping
            let fallbackResult: String
            let fallbackType: ScreensaverType
            
            switch provider {
            case "com.apple.wallpaper.choice.screen-saver":
                fallbackResult = "Traditional Screensaver"
                fallbackType = .traditional
            case "com.apple.NeptuneOneExtension":
                fallbackResult = "Neptune Extension"
                fallbackType = .appExtension
            case "com.apple.wallpaper.choice.sequoia":
                fallbackResult = "Sequoia Video"
                fallbackType = .sequoiaVideo
            case "com.apple.wallpaper.choice.macintosh":
                // Built-in Mac screensaver with empty config
                fallbackResult = "Classic Mac"
                fallbackType = .builtInMac
                if debug {
                    print("DEBUG: Built-in Mac screensaver detected")
                }
                return "\(fallbackResult) (\(fallbackType.displayName))"
            case "default":
                fallbackResult = "Default"
                fallbackType = .defaultScreen
                return "\(fallbackResult) (\(fallbackType.displayName))"
            default:
                fallbackResult = "Unknown (\(provider))"
                fallbackType = .traditional
            }
            
            if debug {
                print("DEBUG: Using fallback result: '\(fallbackResult)'")
                print("DEBUG: Continue checking other displays...")
            }
            
            // For Neptune Extensions with empty config data, continue looking for other displays
            if provider == "com.apple.NeptuneOneExtension" && configurationData.isEmpty {
                if debug {
                    print("DEBUG: Neptune extension with empty config, continuing...")
                }
                continue
            }
            
            return fallbackResult
        }
        
        if debug {
            print("DEBUG: No screensaver configuration found in any display")
        }
        return nil
    }
    
    @available(macOS 14.0, *)
    static func getWallpaperForSpace(spaceUUID: String, debug: Bool = false) -> String? {
        let plistManager = PlistManager.shared
        let indexPath = SystemPaths.wallpaperIndexPath
        
        // Handle empty UUID case - fallback to default space configuration
        let lookupUUID = spaceUUID.isEmpty ? "" : spaceUUID
        
        if debug {
            print("DEBUG: Looking up wallpaper for space UUID: '\(spaceUUID)'")
            print("DEBUG: Using lookup UUID: '\(lookupUUID)'")
        }
        
        guard let plist = try? plistManager.read(at: indexPath) else {
            if debug { print("DEBUG: Failed to read plist") }
            return nil
        }

        // Check if we have a Spaces structure (multi-space configuration)
        var spaceConfig: [String: Any]?

        if let spaces = plist["Spaces"] as? [String: Any], !spaces.isEmpty {
            if debug {
                print("DEBUG: Found \(spaces.keys.count) space configurations in plist")
            }

            // Try the specific space UUID first
            if let config = spaces[lookupUUID] as? [String: Any] {
                spaceConfig = config
                if debug { print("DEBUG: Found exact match for UUID '\(lookupUUID)'") }
            } else if !lookupUUID.isEmpty {
                // If specific UUID not found and it's not empty, try empty string (default)
                spaceConfig = spaces[""] as? [String: Any]
                if debug {
                    if spaceConfig != nil {
                        print("DEBUG: UUID '\(lookupUUID)' not found, using default space configuration")
                    } else {
                        print("DEBUG: UUID '\(lookupUUID)' not found, and no default configuration available")
                    }
                }
            }
        } else if let allSpacesAndDisplays = plist["AllSpacesAndDisplays"] as? [String: Any] {
            // Handle single screen/space configuration with AllSpacesAndDisplays (takes precedence)
            if debug { print("DEBUG: No Spaces configurations found, using AllSpacesAndDisplays configuration") }
            spaceConfig = allSpacesAndDisplays
        } else if let systemDefault = plist["SystemDefault"] as? [String: Any] {
            // Handle single screen/space configuration with SystemDefault (fallback)
            if debug { print("DEBUG: No Spaces or AllSpacesAndDisplays found, using SystemDefault configuration") }
            spaceConfig = systemDefault
        }

        guard let config = spaceConfig else {
            if debug { print("DEBUG: No valid space config found") }
            return nil
        }

        // For empty UUID (default space), prioritize Default → Desktop
        // For non-empty UUIDs, also use Default → Desktop (as they don't have Displays sections)
        // Look for wallpaper in Default → Desktop → Content → Choices

        // First check if Desktop is directly in config (SystemDefault case)
        var desktop: [String: Any]?
        var provider: String?
        var firstChoice: [String: Any]?

        if let systemDesktop = config["Desktop"] as? [String: Any] {
            // SystemDefault case - Desktop is directly in config
            desktop = systemDesktop
            if debug { print("DEBUG: Found Desktop directly in config (SystemDefault)") }
        } else if let defaultConfig = config["Default"] as? [String: Any],
                  let defaultDesktop = defaultConfig["Desktop"] as? [String: Any] {
            // Spaces case - Desktop is under Default
            desktop = defaultDesktop
            if debug { print("DEBUG: Found Desktop under Default section") }
        }

        guard let desktopConfig = desktop,
              let content = desktopConfig["Content"] as? [String: Any],
              let choices = content["Choices"] as? [[String: Any]],
              let choice = choices.first else {
            if debug { print("DEBUG: No valid wallpaper configuration found in space") }
            return nil
        }

        firstChoice = choice
        provider = choice["Provider"] as? String

        guard let providerName = provider else {
            if debug { print("DEBUG: No provider found in wallpaper configuration") }
            return nil
        }
        
        if debug {
            print("DEBUG: Wallpaper provider: '\(providerName)'")
        }

        // Only process image wallpapers
        guard providerName == "com.apple.wallpaper.choice.image" else {
            if debug { print("DEBUG: Provider is not an image type: \(providerName)") }
            // Return a descriptive name for non-image wallpapers
            switch providerName {
            case "com.apple.wallpaper.choice.dynamic":
                return "Dynamic Wallpaper"
            case "com.apple.wallpaper.choice.sequoia":
                return "Sequoia Video"
            case "com.apple.wallpaper.choice.macintosh":
                return "Classic Mac"
            default:
                return "System Wallpaper"
            }
        }
        
        guard let configurationData = firstChoice?["Configuration"] as? Data else {
            if debug { print("DEBUG: No configuration data found") }
            return nil
        }
        
        // Decode the wallpaper path from configuration
        if let urlString = try? plistManager.decodeWallpaperConfiguration(from: configurationData),
           let url = URL(string: urlString) {
            if debug {
                print("DEBUG: Decoded wallpaper URL: \(url)")
            }
            // Return the full path
            return url.path
        }
        
        if debug { print("DEBUG: Failed to decode wallpaper configuration") }
        return nil
    }
    
    @available(macOS 14.0, *)
    static func printSpaceTree(_ paperSaver: PaperSaver, _ spaceTree: [String: Any], debug: Bool = false) {
        // ANSI color codes
        let displayColor = "\u{001B}[1;36m"      // Bold cyan
        let spaceColor = "\u{001B}[1;33m"        // Bold yellow
        let activeColor = "\u{001B}[1;32m"       // Bold green
        let uuidColor = "\u{001B}[34m"           // Blue
        let wallpaperColor = "\u{001B}[35m"      // Magenta
        let screensaverColor = "\u{001B}[36m"    // Cyan
        let reset = "\u{001B}[0m"                // Reset
        
        guard let monitors = spaceTree["monitors"] as? [[String: Any]] else {
            print("No space data available")
            return
        }
        
        if monitors.isEmpty {
            print("No displays found (requires macOS 14.0+)")
            return
        }
        
        print("Spaces (Enhanced Tree View):")
        print("=" * 50)
        
        var totalSpaces = 0
        var currentSpaces: [String] = []
        
        for monitor in monitors {
            guard let name = monitor["name"] as? String,
                  let displayNumber = monitor["display_number"] as? Int,
                  let displayUUID = monitor["uuid"] as? String,
                  let spaces = monitor["spaces"] as? [[String: Any]] else {
                continue
            }
            
            // Display header with UUID prominently shown
            print("\n\(displayColor)Display \(displayNumber)\(reset): \(name) \(uuidColor)(UUID: \(displayUUID))\(reset)")
            
            for space in spaces {
                guard let spaceNumber = space["space_number"] as? Int,
                      let spaceID = space["id"] as? NSNumber,
                      let _ = space["managed_id"] as? NSNumber,
                      let spaceUUID = space["uuid"] as? String,
                      let isCurrent = space["is_current"] as? Bool else {
                    continue
                }
                
                let currentMarker = isCurrent ? " \(activeColor)[ACTIVE]\(reset)" : ""
                let uuidDisplay = spaceUUID.isEmpty ? "(default)" : "(\(String(spaceUUID.prefix(8)))...)"
                print("  \(spaceColor)Space \(spaceNumber)\(reset): Desktop \(spaceNumber) \(uuidDisplay)\(currentMarker)")
                
                // Get wallpaper for this space
                let wallpaperInfo = getWallpaperForSpace(spaceUUID: spaceUUID, debug: debug) ?? "None"
                print("    └─ \(wallpaperColor)Wallpaper\(reset): \(wallpaperInfo)")
                
                // Get screensaver for this space
                if debug {
                    print("    === SCREENSAVER DEBUG FOR SPACE \(spaceNumber) ===")
                }
                let screensaver = getScreensaverForSpace(paperSaver, spaceUUID: spaceUUID, debug: debug) ?? "None"
                print("    └─ \(screensaverColor)Screensaver\(reset): \(screensaver)")
                if debug {
                    print("    === END SCREENSAVER DEBUG ===")
                    print("    └─ \(uuidColor)UUID\(reset): \(spaceUUID)")
                    print("    └─ \(uuidColor)ID\(reset): \(spaceID)")
                }
                
                totalSpaces += 1
                if isCurrent {
                    currentSpaces.append("Display \(displayNumber) Space \(spaceNumber)")
                }
            }
        }
        
        print("\nTotal: \(totalSpaces) space(s)")
        if !currentSpaces.isEmpty {
            print("Current: \(currentSpaces.joined(separator: ", "))")
        }
    }
    
    
    @available(macOS 14.0, *)
    static func handleListDisplays(_ paperSaver: PaperSaver, args: [String]) {
        let format = getOutputFormat(from: args)
        let displays = paperSaver.listDisplays()
        
        switch format {
        case .json:
            if let jsonData = try? JSONEncoder().encode(displays) {
                print(String(data: jsonData, encoding: .utf8) ?? "{}")
            }
            
        case .text:
            if displays.isEmpty {
                print("No displays found (requires macOS 14.0+)")
                return
            }
            
            print("Displays:")
            print("=" * 50)
            
            let connectedDisplays = displays.filter { $0.isConnected }
            let disconnectedDisplays = displays.filter { !$0.isConnected }
            
            if !connectedDisplays.isEmpty {
                print("\nConnected Displays:")
                for display in connectedDisplays {
                    print("• \(display.friendlyName) (\(display.displayDescription))")
                    if let displayID = display.displayID {
                        print("  Display ID: \(displayID)")
                    }
                    print("  UUID: \(display.uuid)")
                    if let frame = display.frame {
                        print("  Position: (\(Int(frame.origin.x)), \(Int(frame.origin.y)))")
                    }
                    print()
                }
            }
            
            if !disconnectedDisplays.isEmpty {
                print("\nHistorical Displays:")
                for display in disconnectedDisplays {
                    if let displayName = display.displayName {
                        // Display has a meaningful name, show it with description and UUID separately
                        print("• \(displayName) (\(display.displayDescription))")
                        print("  UUID: \(display.uuid)")
                    } else {
                        // No meaningful name, just show the UUID to avoid duplication
                        print("• \(display.uuid)")
                        if !display.displayDescription.contains("Unknown") {
                            print("  \(display.displayDescription)")
                        }
                    }
                    if let configVersion = display.configVersion {
                        print("  Last seen: Configuration \(configVersion)")
                    }
                    print()
                }
            }
            
            print("\nTotal: \(displays.count) display UUID(s) (\(connectedDisplays.count) connected)")
        }
    }
    
    @available(macOS 14.0, *)
    static func handleGetSpace(_ paperSaver: PaperSaver, args: [String]) {
        let format = getOutputFormat(from: args)
        
        guard let activeSpace = paperSaver.getActiveSpace() else {
            if format == .json {
                print("{}")
            } else {
                print("No active space found (requires macOS 14.0+)")
            }
            return
        }
        
        switch format {
        case .json:
            if let jsonData = try? JSONEncoder().encode(activeSpace) {
                print(String(data: jsonData, encoding: .utf8) ?? "{}")
            }
            
        case .text:
            print("Active Space: \(activeSpace.name ?? "Current")")
            if !activeSpace.uuid.isEmpty {
                print("UUID: \(activeSpace.uuid)")
            }
            print("Displays: \(activeSpace.displayCount)")
            if !activeSpace.displayUUIDs.isEmpty {
                print("Display UUIDs: \(activeSpace.displayUUIDs.joined(separator: ", "))")
            }
        }
    }
    
    
    @available(macOS 14.0, *)
    static func handleSetSpaceScreensaver(_ paperSaver: PaperSaver, args: [String]) async throws {
        guard !args.isEmpty else {
            printError("Error: Screensaver name required")
            print("Usage: papersaver set-space-screensaver <screensaver-name> --space-id <id> [--screen <screen-id>]")
            print("   or: papersaver set-space-screensaver <screensaver-name> --space-uuid <uuid> [--screen <screen-id>]")
            exit(1)
        }
        
        let screensaverName = args[0]
        let remainingArgs = Array(args.dropFirst())
        let screen = getScreen(from: remainingArgs)
        
        // Check for space ID parameter
        if let spaceIDIndex = remainingArgs.firstIndex(of: "--space-id"),
           spaceIDIndex + 1 < remainingArgs.count,
           let spaceID = Int(remainingArgs[spaceIDIndex + 1]) {
            
            do {
                try await paperSaver.setScreensaverForSpaceID(module: screensaverName, spaceID: spaceID, screen: screen)
                print("Successfully set screensaver '\(screensaverName)' for space ID \(spaceID)")
            } catch PaperSaverError.spaceNotFound {
                printError("Error: Space ID \(spaceID) not found")
                exit(1)
            } catch PaperSaverError.screensaverNotFound(let name) {
                printError("Error: Screensaver '\(name)' not found")
                exit(1)
            }
            return
        }
        
        // Check for space UUID parameter
        if let spaceUUIDIndex = remainingArgs.firstIndex(of: "--space-uuid"),
           spaceUUIDIndex + 1 < remainingArgs.count {
            
            let spaceUUID = remainingArgs[spaceUUIDIndex + 1]
            
            do {
                try await paperSaver.setScreensaverForSpace(module: screensaverName, spaceUUID: spaceUUID, screen: screen)
                let shortUUID = String(spaceUUID.prefix(8)) + "..."
                print("Successfully set screensaver '\(screensaverName)' for space UUID \(shortUUID)")
            } catch PaperSaverError.screensaverNotFound(let name) {
                printError("Error: Screensaver '\(name)' not found")
                exit(1)
            }
            return
        }
        
        printError("Error: Either --space-id <id> or --space-uuid <uuid> is required")
        print("Usage: papersaver set-space-screensaver <screensaver-name> --space-id <id> [--screen <screen-id>]")
        print("   or: papersaver set-space-screensaver <screensaver-name> --space-uuid <uuid> [--screen <screen-id>]")
        exit(1)
    }
    
    
    @available(macOS 14.0, *)
    static func handleSetDisplay(_ paperSaver: PaperSaver, args: [String]) async throws {
        guard !args.isEmpty else {
            printError("Error: Screensaver name required")
            print("Usage: papersaver set-display <screensaver-name> --display <number>")
            exit(1)
        }
        
        let screensaverName = args[0]
        let remainingArgs = Array(args.dropFirst())
        let verbose = remainingArgs.contains("--verbose") || remainingArgs.contains("-v")
        
        // Check for display parameter
        guard let displayIndex = remainingArgs.firstIndex(of: "--display"),
              displayIndex + 1 < remainingArgs.count,
              let displayNumber = Int(remainingArgs[displayIndex + 1]) else {
            printError("Error: --display <number> parameter is required")
            print("Usage: papersaver set-display <screensaver-name> --display <number>")
            print("\nUse 'papersaver list-spaces' to see display numbers")
            exit(1)
        }
        
        if verbose {
            print("Setting screensaver '\(screensaverName)' on Display \(displayNumber)...")
        }
        
        do {
            try await paperSaver.setScreensaverForDisplay(module: screensaverName, displayNumber: displayNumber)
            print("✅ Successfully set screensaver '\(screensaverName)' on Display \(displayNumber)")
            
            if verbose {
                print("\nNote: This sets the screensaver on all spaces of Display \(displayNumber)")
                print("\nYou may need to restart the wallpaper agent for changes to take effect:")
                print("  killall WallpaperAgent")
            }
        } catch PaperSaverError.displayNotFound(let displayNum) {
            printError("Error: Display \(displayNum) not found")
            print("\nUse 'papersaver list-spaces' to see available displays")
            exit(1)
        } catch PaperSaverError.screensaverNotFound(let name) {
            printError("Error: Screensaver '\(name)' not found")
            exit(1)
        }
    }
    
    @available(macOS 14.0, *)
    static func handleSetSpace(_ paperSaver: PaperSaver, args: [String]) async throws {
        guard !args.isEmpty else {
            printError("Error: Screensaver name required")
            print("Usage: papersaver set-space <screensaver-name> --display <number> --space <number>")
            exit(1)
        }
        
        let screensaverName = args[0]
        let remainingArgs = Array(args.dropFirst())
        let verbose = remainingArgs.contains("--verbose") || remainingArgs.contains("-v")
        
        // Check for display parameter
        guard let displayIndex = remainingArgs.firstIndex(of: "--display"),
              displayIndex + 1 < remainingArgs.count,
              let displayNumber = Int(remainingArgs[displayIndex + 1]) else {
            printError("Error: --display <number> parameter is required")
            print("Usage: papersaver set-space <screensaver-name> --display <number> --space <number>")
            print("\nUse 'papersaver list-spaces' to see display and space numbers")
            exit(1)
        }
        
        // Check for space parameter
        guard let spaceIndex = remainingArgs.firstIndex(of: "--space"),
              spaceIndex + 1 < remainingArgs.count,
              let spaceNumber = Int(remainingArgs[spaceIndex + 1]) else {
            printError("Error: --space <number> parameter is required")
            print("Usage: papersaver set-space <screensaver-name> --display <number> --space <number>")
            print("\nUse 'papersaver list-spaces' to see display and space numbers")
            exit(1)
        }
        
        if verbose {
            print("Setting screensaver '\(screensaverName)' on Display \(displayNumber) Space \(spaceNumber)...")
        }
        
        do {
            try await paperSaver.setScreensaverForDisplaySpace(module: screensaverName, displayNumber: displayNumber, spaceNumber: spaceNumber)
            print("✅ Successfully set screensaver '\(screensaverName)' on Display \(displayNumber) Space \(spaceNumber)")
            
            if verbose {
                print("\nYou may need to restart the wallpaper agent for changes to take effect:")
                print("  killall WallpaperAgent")
            }
        } catch PaperSaverError.displayNotFound(let displayNum) {
            printError("Error: Display \(displayNum) not found")
            print("\nUse 'papersaver list-spaces' to see available displays")
            exit(1)
        } catch PaperSaverError.spaceNotFoundOnDisplay(let displayNum, let spaceNum) {
            printError("Error: Space \(spaceNum) not found on Display \(displayNum)")
            print("\nUse 'papersaver list-spaces' to see available spaces")
            exit(1)
        } catch PaperSaverError.screensaverNotFound(let name) {
            printError("Error: Screensaver '\(name)' not found")
            exit(1)
        }
    }
    
    @available(macOS 14.0, *)
    static func handleRestore(_ paperSaver: PaperSaver, args: [String]) async throws {
        let verbose = args.contains("--verbose") || args.contains("-v")
        let force = args.contains("--force") || args.contains("-f")
        
        if verbose {
            print("Checking for backup file...")
        }
        
        let backupInfo = paperSaver.getBackupInfo()
        
        guard backupInfo.exists else {
            printError("Error: No backup file found")
            print("\nBackups are automatically created before each screensaver modification.")
            print("Make some screensaver changes first, then you can restore if needed.")
            exit(1)
        }
        
        // Show backup information
        print("Found backup file:")
        
        if let date = backupInfo.date {
            let formatter = DateFormatter()
            formatter.dateStyle = .medium
            formatter.timeStyle = .medium
            print("  Created: \(formatter.string(from: date))")
        }
        
        if let size = backupInfo.size {
            let sizeKB = Double(size) / 1024.0
            print("  Size: \(String(format: "%.1f", sizeKB)) KB")
        }
        
        // Ask for confirmation unless --force is used
        if !force {
            print("\n⚠️  This will overwrite your current wallpaper/screensaver settings.")
            print("Are you sure you want to restore from backup? (y/N): ", terminator: "")
            
            if let response = readLine()?.lowercased(),
               response == "y" || response == "yes" {
                // Proceed with restore
            } else {
                print("Restore cancelled.")
                return
            }
        }
        
        if verbose {
            print("Restoring from backup...")
        }
        
        do {
            try paperSaver.restoreFromBackup()
            print("✅ Successfully restored wallpaper/screensaver settings from backup")
            
            if verbose {
                print("\nYou may need to restart the wallpaper agent for changes to take effect:")
                print("  killall WallpaperAgent")
            }
        } catch PaperSaverError.fileNotFound(_) {
            printError("Error: Backup file not found or is no longer accessible")
            exit(1)
        } catch {
            printError("Error: Failed to restore from backup: \(error.localizedDescription)")
            exit(1)
        }
    }
    
    static func printUsage() {
        print("""
        papersaver - Command-line interface for PaperSaver
        
        USAGE:
            papersaver <command> [options]
        
        COMMANDS:
            list                    List all available screensavers
            get                     Get current screensaver
            idle-time [get|set]     Get or set idle time before screensaver starts
            
          Unified Commands (Sonoma+):
            set-saver <name>        Set screensaver with unified targeting options
            set-paper <path>        Set wallpaper with unified targeting options
            restore-backup          Restore wallpaper/screensaver settings from backup
            
          Information Commands (Sonoma+):
            list-spaces             List all spaces with display information
            list-displays           List displays with UUID to screen mapping
            get-space               Get current active space
            
            help, --help, -h        Show this help message
            version, --version      Show version information
        
        TARGETING OPTIONS (for set-saver and set-paper):
            --display <number>      Target specific display by number (1, 2, 3...)
            --space <number>        Target specific space by number (1, 2, 3...)
            --space-uuid <uuid>     Target specific space by UUID
            --display-uuid <uuid>   Target specific display by UUID
            
            Note: Without targeting options, commands apply everywhere.
                  Combine --display and --space to target a specific display's space.
        
        OTHER OPTIONS:
            --screen, -s <id>       Target specific screen (legacy commands only)
            --json, -j              Output in JSON format
            --verbose, -v           Show verbose output
            --force, -f             Skip confirmation prompts (restore-backup only)
        
        EXAMPLES:
            papersaver list
            papersaver get --json
            papersaver idle-time get
            papersaver idle-time set 300
            
          Unified Command Examples:
            papersaver set-saver Aerial
            papersaver set-saver Aerial --display 1
            papersaver set-saver Aerial --display 1 --space 4
            papersaver set-saver Aerial --space-uuid 6CE21993-87A6-4708-80D3-F803E0C6B050
            
            papersaver set-paper ~/Pictures/background.jpg
            papersaver set-paper ~/Pictures/background.jpg --display 1
            papersaver set-paper ~/Pictures/background.jpg --space 2
            papersaver set-paper ~/Pictures/background.jpg --space-uuid 6CE21993-87A6-4708-80D3-F803E0C6B050
            
          Information Examples:
            papersaver list-spaces
            papersaver list-displays --json
            papersaver get-space
            papersaver restore-backup --force --verbose
        """)
    }
    
    static func printError(_ message: String) {
        fputs("❌ \(message)\n", stderr)
    }
}

extension String {
    static func * (left: String, right: Int) -> String {
        return String(repeating: left, count: right)
    }
}


// MARK: - Unified Command Support
extension PaperSaverCLI {
    struct TargetingOptions {
        let displayNumber: Int?
        let spaceNumber: Int?
        let spaceUUID: String?
        let displayUUID: String?
        
        var hasDisplayTarget: Bool {
            return displayNumber != nil || displayUUID != nil
        }
        
        var hasSpaceTarget: Bool {
            return spaceNumber != nil || spaceUUID != nil
        }
        
        var isEverywhere: Bool {
            return !hasDisplayTarget && !hasSpaceTarget
        }
    }
    
    static func parseTargetingOptions(from args: [String]) -> TargetingOptions {
        var displayNumber: Int?
        var spaceNumber: Int?
        var spaceUUID: String?
        var displayUUID: String?
        
        // Parse --display <number>
        if let displayIndex = args.firstIndex(of: "--display"),
           displayIndex + 1 < args.count,
           let displayNum = Int(args[displayIndex + 1]) {
            displayNumber = displayNum
        }
        
        // Parse --space <number>
        if let spaceIndex = args.firstIndex(of: "--space"),
           spaceIndex + 1 < args.count,
           let spaceNum = Int(args[spaceIndex + 1]) {
            spaceNumber = spaceNum
        }
        
        // Parse --space-uuid <uuid>
        if let spaceUUIDIndex = args.firstIndex(of: "--space-uuid"),
           spaceUUIDIndex + 1 < args.count {
            spaceUUID = args[spaceUUIDIndex + 1]
        }
        
        // Parse --display-uuid <uuid>
        if let displayUUIDIndex = args.firstIndex(of: "--display-uuid"),
           displayUUIDIndex + 1 < args.count {
            displayUUID = args[displayUUIDIndex + 1]
        }
        
        return TargetingOptions(
            displayNumber: displayNumber,
            spaceNumber: spaceNumber,
            spaceUUID: spaceUUID,
            displayUUID: displayUUID
        )
    }
    
    static func handleUnifiedSetSaver(_ paperSaver: PaperSaver, screensaverName: String, args: [String]) async throws {
        let options = parseTargetingOptions(from: args)
        
        if options.isEverywhere {
            let verbose = args.contains("--verbose") || args.contains("-v")
            let noRestart = args.contains("--no-restart")
            let debugRollback = args.contains("--debug-rollback")

            if verbose {
                print("Setting screensaver to '\(screensaverName)'...")
                print("Target: All screens and spaces")
                if noRestart {
                    print("Using --no-restart: skipping WallpaperAgent restart and auto-rollback")
                }
                if debugRollback {
                    print("Debug mode enabled: detailed rollback logging active")
                }
            }

            do {
                try await paperSaver.setScreensaverEverywhere(module: screensaverName, skipRestart: noRestart, enableDebug: debugRollback)

                print("✅ Successfully set screensaver to: \(screensaverName)")

                if verbose && !noRestart && !debugRollback {
                    print("\nAuto-rollback protection is active - will revert if WallpaperAgent corrupts settings")
                } else if verbose && noRestart {
                    print("\nNote: You may need to restart the wallpaper agent manually for changes to take effect:")
                    print("  killall WallpaperAgent")
                }
            } catch {
                throw error
            }
        } else if options.hasDisplayTarget && options.hasSpaceTarget {
            if #available(macOS 14.0, *) {
                if let displayNumber = options.displayNumber, let spaceNumber = options.spaceNumber {
                    let fakeArgs = ["--display", displayNumber.description, "--space", spaceNumber.description]
                    try await handleSetSpace(paperSaver, args: [screensaverName] + fakeArgs)
                } else {
                    throw PaperSaverError.invalidConfiguration("Invalid display/space combination")
                }
            } else {
                printError("Error: Space/Display commands require macOS 14.0 (Sonoma) or later")
                exit(1)
            }
        } else if options.hasDisplayTarget {
            if #available(macOS 14.0, *) {
                if let displayNumber = options.displayNumber {
                    let fakeArgs = ["--display", displayNumber.description]
                    try await handleSetDisplay(paperSaver, args: [screensaverName] + fakeArgs)
                } else {
                    throw PaperSaverError.invalidConfiguration("Invalid display number")
                }
            } else {
                printError("Error: Display commands require macOS 14.0 (Sonoma) or later")
                exit(1)
            }
        } else if options.hasSpaceTarget {
            if #available(macOS 14.0, *) {
                if let spaceUUID = options.spaceUUID {
                    let fakeArgs = ["--space-uuid", spaceUUID]
                    try await handleSetSpaceScreensaver(paperSaver, args: [screensaverName] + fakeArgs)
                } else if let spaceNumber = options.spaceNumber {
                    let fakeArgs = ["--space", spaceNumber.description]
                    try await handleSetSpaceScreensaver(paperSaver, args: [screensaverName] + fakeArgs)
                } else {
                    throw PaperSaverError.invalidConfiguration("Invalid space identifier")
                }
            } else {
                printError("Error: Space commands require macOS 14.0 (Sonoma) or later")
                exit(1)
            }
        } else {
            try await setScreensaver(paperSaver, name: screensaverName, args: [])
        }
    }
    
    static func handleUnifiedSetPaper(_ paperSaver: PaperSaver, imagePath: String, args: [String]) async throws {
        let options = parseTargetingOptions(from: args)
        let imageURL = URL(fileURLWithPath: imagePath)
        let wallpaperOptions = WallpaperOptions()
        
        if options.isEverywhere {
            do {
                try await paperSaver.setWallpaperEverywhere(imageURL: imageURL, options: wallpaperOptions)
                print("✅ Successfully set wallpaper everywhere")
            } catch {
                throw error
            }
        } else if options.hasDisplayTarget && options.hasSpaceTarget {
            if #available(macOS 14.0, *) {
                if let displayNumber = options.displayNumber, let spaceNumber = options.spaceNumber {
                    do {
                        try await paperSaver.setWallpaperForDisplaySpace(
                            imageURL: imageURL,
                            displayNumber: displayNumber,
                            spaceNumber: spaceNumber,
                            options: wallpaperOptions
                        )
                        print("✅ Successfully set wallpaper for display \(displayNumber) space \(spaceNumber)")
                    } catch {
                        throw error
                    }
                } else {
                    throw PaperSaverError.invalidConfiguration("Invalid display/space combination")
                }
            } else {
                printError("Error: Display/Space commands require macOS 14.0 (Sonoma) or later")
                exit(1)
            }
        } else if options.hasDisplayTarget {
            if #available(macOS 14.0, *) {
                if let displayNumber = options.displayNumber {
                    do {
                        try await paperSaver.setWallpaperForDisplay(
                            imageURL: imageURL,
                            displayNumber: displayNumber,
                            options: wallpaperOptions
                        )
                        print("✅ Successfully set wallpaper for display \(displayNumber)")
                    } catch {
                        throw error
                    }
                } else {
                    throw PaperSaverError.invalidConfiguration("Invalid display number")
                }
            } else {
                printError("Error: Display commands require macOS 14.0 (Sonoma) or later")
                exit(1)
            }
        } else if options.hasSpaceTarget {
            if #available(macOS 14.0, *) {
                if let spaceUUID = options.spaceUUID {
                    do {
                        try await paperSaver.setWallpaperForSpace(
                            imageURL: imageURL,
                            spaceUUID: spaceUUID,
                            screen: nil,
                            options: wallpaperOptions
                        )
                        print("✅ Successfully set wallpaper for space \(spaceUUID)")
                    } catch {
                        throw error
                    }
                } else {
                    throw PaperSaverError.invalidConfiguration("Invalid space identifier")
                }
            } else {
                printError("Error: Space commands require macOS 14.0 (Sonoma) or later")
                exit(1)
            }
        } else {
            do {
                try await paperSaver.setWallpaperEverywhere(imageURL: imageURL, options: wallpaperOptions)
                print("✅ Successfully set wallpaper")
            } catch {
                throw error
            }
        }
    }
}
