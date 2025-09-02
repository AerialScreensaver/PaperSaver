import Foundation
import PaperSaver
import AppKit

@main
struct PaperSaverCLI {
    static let version = "0.1.0"
    
    enum Command: String, CaseIterable {
        case list
        case get
        case set
        case idleTime = "idle-time"
        case wallpaper
        case listSpaces = "list-spaces"
        case listDisplays = "list-displays"
        case getSpace = "get-space"
        case setSpaceScreensaver = "set-space-screensaver"
        case setDisplay = "set-display"
        case setSpace = "set-space"
        case restoreBackup = "restore-backup"
        case version
        case help
        
        var description: String {
            switch self {
            case .list:
                return "List all available screensavers"
            case .get:
                return "Get current screensaver"
            case .set:
                return "Set screensaver"
            case .idleTime:
                return "Get or set idle time"
            case .wallpaper:
                return "Manage wallpapers"
            case .listSpaces:
                return "List all spaces (Sonoma+)"
            case .listDisplays:
                return "List all displays with UUID mapping (Sonoma+)"
            case .getSpace:
                return "Get current active space (Sonoma+)"
            case .setSpaceScreensaver:
                return "Set screensaver for specific space (Sonoma+)"
            case .setDisplay:
                return "Set screensaver on all spaces of a display (Sonoma+)"
            case .setSpace:
                return "Set screensaver on specific display space (Sonoma+)"
            case .restoreBackup:
                return "Restore wallpaper/screensaver settings from backup"
            case .version:
                return "Show version information"
            case .help:
                return "Show this help message"
            }
        }
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
        
        if commandString == "--version" || commandString == "-v" {
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
            
        case .set:
            guard !args.isEmpty else {
                printError("Error: Screensaver name required")
                print("Usage: papersaver set <screensaver-name> [--screen <screen-id>]")
                exit(1)
            }
            try await setScreensaver(paperSaver, name: args[0], args: Array(args.dropFirst()))
            
        case .idleTime:
            try handleIdleTime(paperSaver, args: args)
            
        case .wallpaper:
            try await handleWallpaper(paperSaver, args: args)
            
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
            
        case .setSpaceScreensaver:
            if #available(macOS 14.0, *) {
                try await handleSetSpaceScreensaver(paperSaver, args: args)
            } else {
                printError("Error: Space commands require macOS 14.0 (Sonoma) or later")
                exit(1)
            }
            
        case .setDisplay:
            if #available(macOS 14.0, *) {
                try await handleSetDisplay(paperSaver, args: args)
            } else {
                printError("Error: Display commands require macOS 14.0 (Sonoma) or later")
                exit(1)
            }
            
        case .setSpace:
            if #available(macOS 14.0, *) {
                try await handleSetSpace(paperSaver, args: args)
            } else {
                printError("Error: Space commands require macOS 14.0 (Sonoma) or later")
                exit(1)
            }
            
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
                }
            }
            
            if !userScreensavers.isEmpty {
                print("\nUser Screensavers:")
                for saver in userScreensavers {
                    print("  • \(saver.name) (\(saver.type.displayName))")
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
        
        try await paperSaver.setScreensaver(module: name, for: screen)
        
        print("✅ Successfully set screensaver to: \(name)")
        
        if verbose {
            print("\nNote: You may need to restart the wallpaper agent for changes to take effect:")
            print("  killall WallpaperAgent")
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
    
    static func handleWallpaper(_ paperSaver: PaperSaver, args: [String]) async throws {
        guard !args.isEmpty else {
            print("Wallpaper commands:")
            print("  get              Get current wallpaper")
            print("  set <path>       Set wallpaper from file path")
            print("  list-options     List wallpaper scaling options")
            return
        }
        
        let subcommand = args[0]
        
        switch subcommand {
        case "get":
            if let screen = NSScreen.main,
               let url = paperSaver.getCurrentWallpaper(for: screen) {
                print("Current wallpaper: \(url.path)")
            } else {
                print("No wallpaper currently set")
            }
            
        case "set":
            guard args.count >= 2 else {
                printError("Error: Wallpaper path required")
                print("Usage: papersaver wallpaper set <path> [--screen <screen-id>] [--scaling <option>]")
                exit(1)
            }
            
            let path = args[1]
            let url = URL(fileURLWithPath: path.expandingTildeInPath)
            
            guard FileManager.default.fileExists(atPath: url.path) else {
                printError("Error: File not found at path: \(path)")
                exit(1)
            }
            
            let screen = getScreen(from: args)
            let options = WallpaperOptions()
            
            try await paperSaver.setWallpaper(url: url, screen: screen, options: options)
            print("✅ Successfully set wallpaper")
            
        case "list-options":
            print("Wallpaper Scaling Options:")
            print("  • fill      - Fill screen, cropping if necessary")
            print("  • fit       - Fit entire image on screen")
            print("  • stretch   - Stretch to fill screen")
            print("  • center    - Center image without scaling")
            print("  • tile      - Tile image across screen")
            
        default:
            printError("Error: Unknown wallpaper subcommand '\(subcommand)'")
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
        
        guard let plist = try? plistManager.read(at: indexPath),
              let spaces = plist["Spaces"] as? [String: Any] else {
            if debug { print("DEBUG: Failed to read plist or no Spaces found") }
            return nil
        }
        
        if debug {
            print("DEBUG: Found \(spaces.keys.count) space configurations in plist")
            print("DEBUG: Space keys available: \(spaces.keys.sorted())")
        }
        
        // Try the specific space UUID first
        var spaceConfig: [String: Any]?
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
        
        guard let config = spaceConfig,
              let displays = config["Displays"] as? [String: Any] else {
            if debug { print("DEBUG: No valid space config or Displays found") }
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
        
        // Find the connected display first, fall back to sorted order
        var displayKeysToCheck: [String] = []
        
        // First, add any connected displays
        for displayKey in displays.keys {
            if connectedUUIDs.contains(displayKey) {
                displayKeysToCheck.append(displayKey)
                if debug {
                    print("DEBUG: Found connected display: \(displayKey)")
                }
            }
        }
        
        // Then add remaining displays in sorted order (for fallback)
        let sortedDisplayKeys = displays.keys.sorted()
        for displayKey in sortedDisplayKeys {
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
    static func printSpaceTree(_ paperSaver: PaperSaver, _ spaceTree: [String: Any], debug: Bool = false) {
        guard let monitors = spaceTree["monitors"] as? [[String: Any]] else {
            print("No space data available")
            return
        }
        
        if monitors.isEmpty {
            print("No displays found (requires macOS 14.0+)")
            return
        }
        
        print("Spaces (Tree View):")
        print("=" * 50)
        
        var totalSpaces = 0
        var currentSpaces: [String] = []
        
        for monitor in monitors {
            guard let name = monitor["name"] as? String,
                  let displayNumber = monitor["display_number"] as? Int,
                  let spaces = monitor["spaces"] as? [[String: Any]] else {
                continue
            }
            
            print("\nDisplay \(displayNumber): \(name)")
            
            for space in spaces {
                guard let spaceNumber = space["space_number"] as? Int,
                      let spaceID = space["id"] as? NSNumber,
                      let managedID = space["managed_id"] as? NSNumber,
                      let spaceUUID = space["uuid"] as? String,
                      let isCurrent = space["is_current"] as? Bool else {
                    continue
                }
                
                let currentIndicator = isCurrent ? " (Current)" : ""
                print("  Space \(spaceNumber): ID=\(spaceID)\(currentIndicator)")
                print("    UUID: \(spaceUUID)")
                
                // Get and display screensaver info
                if debug {
                    print("    === SCREENSAVER DEBUG FOR SPACE \(spaceNumber) ===")
                }
                if let screensaverName = getScreensaverForSpace(paperSaver, spaceUUID: spaceUUID, debug: debug) {
                    print("    Screensaver: \(screensaverName)")
                } else {
                    print("    Screensaver: None")
                }
                if debug {
                    print("    === END SCREENSAVER DEBUG ===")
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
            set <name>              Set screensaver
            idle-time [get|set]     Get or set idle time before screensaver starts
            wallpaper <subcommand>  Manage wallpapers
            
          Enhanced Screensaver Commands:
            set-display <name>      Set screensaver on all spaces of a display (Sonoma+)
            set-space <name>        Set screensaver on specific display space (Sonoma+)
            restore-backup          Restore wallpaper/screensaver settings from backup (Sonoma+)
            
          Sonoma+ Space Commands:
            list-spaces             List all spaces with display information
            list-displays           List displays with UUID to screen mapping
            get-space               Get current active space
            set-space-screensaver   Set screensaver for specific space
            
            help, --help, -h        Show this help message
            version, --version, -v  Show version information
        
        OPTIONS:
            --screen, -s <id>       Target specific screen (default: all screens)
            --json, -j              Output in JSON format
            --verbose, -v           Show verbose output
            --force, -f             Skip confirmation prompts (restore-backup only)
            --display <number>      Target specific display by number (1, 2, 3...)
            --space <number>        Target specific space by number (1, 2, 3...)
            --space-id <id>         Target specific space by ID (set-space-screensaver)
            --space-uuid <uuid>     Target specific space by UUID (set-space-screensaver)
        
        EXAMPLES:
            papersaver list
            papersaver get --json
            papersaver set Aerial
            papersaver set Fliqlo --screen 0
            papersaver idle-time get
            papersaver idle-time set 300
            papersaver wallpaper set ~/Pictures/background.jpg
            
          Enhanced Screensaver Examples:
            papersaver set-display Aerial --display 1
            papersaver set-space Aerial --display 1 --space 4
            papersaver restore-backup
            papersaver restore-backup --force --verbose
            
          Sonoma+ Space Examples:
            papersaver list-spaces
            papersaver list-displays --json
            papersaver get-space
            papersaver set-space-screensaver Aerial --space-id 3
            papersaver set-space-screensaver Aerial --space-uuid 6CE21993-87A6-4708-80D3-F803E0C6B050
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

extension String {
    var expandingTildeInPath: String {
        return NSString(string: self).expandingTildeInPath
    }
}