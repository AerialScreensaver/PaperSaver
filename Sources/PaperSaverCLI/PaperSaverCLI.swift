import Foundation
import PaperSaverKit
import AppKit
import ArgumentParser

// MARK: - Main Command

@main
struct PaperSaver: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "papersaver",
        abstract: "Command-line interface for PaperSaver",
        version: "0.1.0",
        subcommands: [
            List.self,
            Get.self,
            IdleTime.self,
            ListSpaces.self,
            ListDisplays.self,
            GetSpace.self,
            SetSaver.self,
            SetPaper.self,
            RestoreBackup.self,
        ]
    )
}

// MARK: - Shared Option Groups

struct OutputOptions: ParsableArguments {
    @Flag(name: .shortAndLong, help: "Output in JSON format")
    var json = false

    @Flag(name: .shortAndLong, help: "Show verbose output")
    var verbose = false
}

struct TargetingOptions: ParsableArguments {
    @Option(name: .long, help: "Target display by number (1, 2, 3...)")
    var display: Int?

    @Option(name: .long, help: "Target space by number (1, 2, 3...)")
    var space: Int?

    @Option(name: .customLong("space-uuid"), help: "Target space by UUID")
    var spaceUuid: String?

    @Option(name: .customLong("display-uuid"), help: "Target display by UUID")
    var displayUuid: String?

    var hasDisplayTarget: Bool {
        display != nil || displayUuid != nil
    }

    var hasSpaceTarget: Bool {
        space != nil || spaceUuid != nil
    }

    var isEverywhere: Bool {
        !hasDisplayTarget && !hasSpaceTarget
    }
}

// MARK: - List Command

struct List: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "List all available screensavers"
    )

    @OptionGroup var output: OutputOptions

    func run() async throws {
        let paperSaver = PaperSaverKit.PaperSaver()
        let screensavers = paperSaver.listAvailableScreensavers()

        if output.json {
            let jsonData = try JSONEncoder().encode(screensavers)
            print(String(data: jsonData, encoding: .utf8)!)
        } else {
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
                    print("  \u{2022} \(saver.name) (\(saver.type.displayName))")
                    if output.verbose {
                        print("    Path: \(saver.path.path)")
                    }
                }
            }

            if !userScreensavers.isEmpty {
                print("\nUser Screensavers:")
                for saver in userScreensavers {
                    print("  \u{2022} \(saver.name) (\(saver.type.displayName))")
                    if output.verbose {
                        print("    Path: \(saver.path.path)")
                    }
                }
            }

            print("\nTotal: \(screensavers.count) screensaver(s)")
        }
    }
}

// MARK: - Get Command

struct Get: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Get current screensaver"
    )

    @OptionGroup var output: OutputOptions

    @Option(name: .shortAndLong, help: "Target specific screen")
    var screen: Int?

    func run() async throws {
        let paperSaver = PaperSaverKit.PaperSaver()
        let nsScreen: NSScreen? = screen != nil ? NSScreen.main : nil

        guard let info = paperSaver.getActiveScreensaver(for: nsScreen) else {
            if output.json {
                print("{}")
            } else {
                print("No screensaver currently set")
            }
            return
        }

        if output.json {
            let jsonData = try JSONEncoder().encode(info)
            print(String(data: jsonData, encoding: .utf8)!)
        } else {
            print("Current Screensaver: \(info.name)")
            if let screenInfo = info.screen {
                print("Display ID: \(screenInfo.displayID)")
            }
        }
    }
}

// MARK: - IdleTime Command

struct IdleTime: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "idle-time",
        abstract: "Get or set idle time before screensaver starts",
        subcommands: [IdleTimeGet.self, IdleTimeSet.self],
        defaultSubcommand: IdleTimeGet.self
    )
}

struct IdleTimeGet: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "get",
        abstract: "Get current idle time"
    )

    @Flag(name: .shortAndLong, help: "Output in JSON format")
    var json = false

    func run() async throws {
        let paperSaver = PaperSaverKit.PaperSaver()
        let idleTime = paperSaver.getIdleTime()

        if json {
            print("{\"idleTime\": \(idleTime)}")
        } else {
            print("Current idle time: \(formatIdleTime(idleTime))")
        }
    }
}

struct IdleTimeSet: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "set",
        abstract: "Set idle time"
    )

    @Argument(help: "Idle time in seconds")
    var seconds: Int

    func run() async throws {
        let paperSaver = PaperSaverKit.PaperSaver()
        try paperSaver.setIdleTime(seconds: seconds)
        print("\u{2705} Idle time set to: \(formatIdleTime(seconds))")
    }
}

// MARK: - ListSpaces Command

struct ListSpaces: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "list-spaces",
        abstract: "List all spaces with display information (macOS 14+)"
    )

    @Flag(name: .shortAndLong, help: "Output in JSON format")
    var json = false

    @Flag(name: .long, help: "Show debug information")
    var debug = false

    func run() async throws {
        guard #available(macOS 14.0, *) else {
            printError("Error: Space commands require macOS 14.0 (Sonoma) or later")
            throw ExitCode.failure
        }

        let paperSaver = PaperSaverKit.PaperSaver()
        let spaceTree = paperSaver.getNativeSpaceTree()

        if json {
            if let jsonData = try? JSONSerialization.data(withJSONObject: spaceTree, options: .prettyPrinted),
               let jsonString = String(data: jsonData, encoding: .utf8) {
                print(jsonString)
            } else {
                print("{}")
            }
        } else {
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
}

// MARK: - ListDisplays Command

struct ListDisplays: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "list-displays",
        abstract: "List displays with UUID to screen mapping (macOS 14+)"
    )

    @Flag(name: .shortAndLong, help: "Output in JSON format")
    var json = false

    func run() async throws {
        guard #available(macOS 14.0, *) else {
            printError("Error: Space commands require macOS 14.0 (Sonoma) or later")
            throw ExitCode.failure
        }

        let paperSaver = PaperSaverKit.PaperSaver()
        let displays = paperSaver.listDisplays()

        if json {
            if let jsonData = try? JSONEncoder().encode(displays) {
                print(String(data: jsonData, encoding: .utf8) ?? "{}")
            }
        } else {
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
                    print("\u{2022} \(display.friendlyName) (\(display.displayDescription))")
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
                        print("\u{2022} \(displayName) (\(display.displayDescription))")
                        print("  UUID: \(display.uuid)")
                    } else {
                        print("\u{2022} \(display.uuid)")
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
}

// MARK: - GetSpace Command

struct GetSpace: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "get-space",
        abstract: "Get current active space (macOS 14+)"
    )

    @Flag(name: .shortAndLong, help: "Output in JSON format")
    var json = false

    func run() async throws {
        guard #available(macOS 14.0, *) else {
            printError("Error: Space commands require macOS 14.0 (Sonoma) or later")
            throw ExitCode.failure
        }

        let paperSaver = PaperSaverKit.PaperSaver()

        guard let activeSpace = paperSaver.getActiveSpace() else {
            if json {
                print("{}")
            } else {
                print("No active space found (requires macOS 14.0+)")
            }
            return
        }

        if json {
            if let jsonData = try? JSONEncoder().encode(activeSpace) {
                print(String(data: jsonData, encoding: .utf8) ?? "{}")
            }
        } else {
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
}

// MARK: - SetSaver Command

struct SetSaver: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "set-saver",
        abstract: "Set screensaver with unified targeting options"
    )

    @Argument(help: "Screensaver name")
    var screensaverName: String

    @OptionGroup var targeting: TargetingOptions

    @Flag(name: .shortAndLong, help: "Show verbose output")
    var verbose = false

    @Flag(name: .customLong("no-restart"), help: "Skip WallpaperAgent restart")
    var noRestart = false

    @Flag(name: .customLong("debug-rollback"), help: "Enable detailed rollback logging")
    var debugRollback = false

    func run() async throws {
        let paperSaver = PaperSaverKit.PaperSaver()

        if targeting.isEverywhere {
            try await setScreensaverEverywhere(paperSaver)
        } else if targeting.hasDisplayTarget && targeting.hasSpaceTarget {
            try await setScreensaverForDisplaySpace(paperSaver)
        } else if targeting.hasDisplayTarget {
            try await setScreensaverForDisplay(paperSaver)
        } else if targeting.hasSpaceTarget {
            try await setScreensaverForSpace(paperSaver)
        }
    }

    private func setScreensaverEverywhere(_ paperSaver: PaperSaverKit.PaperSaver) async throws {
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

        try await paperSaver.setScreensaverEverywhere(module: screensaverName, skipRestart: noRestart, enableDebug: debugRollback)
        print("\u{2705} Successfully set screensaver to: \(screensaverName)")

        if verbose && !noRestart && !debugRollback {
            print("\nAuto-rollback protection is active - will revert if WallpaperAgent corrupts settings")
        } else if verbose && noRestart {
            print("\nNote: You may need to restart the wallpaper agent manually for changes to take effect:")
            print("  killall WallpaperAgent")
        }
    }

    private func setScreensaverForDisplaySpace(_ paperSaver: PaperSaverKit.PaperSaver) async throws {
        guard #available(macOS 14.0, *) else {
            printError("Error: Space/Display commands require macOS 14.0 (Sonoma) or later")
            throw ExitCode.failure
        }

        guard let displayNumber = targeting.display, let spaceNumber = targeting.space else {
            throw ValidationError("Both --display and --space are required for this operation")
        }

        if verbose {
            print("Setting screensaver '\(screensaverName)' on Display \(displayNumber) Space \(spaceNumber)...")
        }

        do {
            try await paperSaver.setScreensaverForDisplaySpace(module: screensaverName, displayNumber: displayNumber, spaceNumber: spaceNumber)
            print("\u{2705} Successfully set screensaver '\(screensaverName)' on Display \(displayNumber) Space \(spaceNumber)")

            if verbose {
                print("\nYou may need to restart the wallpaper agent for changes to take effect:")
                print("  killall WallpaperAgent")
            }
        } catch PaperSaverError.displayNotFound(let displayNum) {
            printError("Error: Display \(displayNum) not found")
            print("\nUse 'papersaver list-spaces' to see available displays")
            throw ExitCode.failure
        } catch PaperSaverError.spaceNotFoundOnDisplay(let displayNum, let spaceNum) {
            printError("Error: Space \(spaceNum) not found on Display \(displayNum)")
            print("\nUse 'papersaver list-spaces' to see available spaces")
            throw ExitCode.failure
        } catch PaperSaverError.screensaverNotFound(let name) {
            printError("Error: Screensaver '\(name)' not found")
            throw ExitCode.failure
        }
    }

    private func setScreensaverForDisplay(_ paperSaver: PaperSaverKit.PaperSaver) async throws {
        guard #available(macOS 14.0, *) else {
            printError("Error: Display commands require macOS 14.0 (Sonoma) or later")
            throw ExitCode.failure
        }

        guard let displayNumber = targeting.display else {
            throw ValidationError("--display is required for this operation")
        }

        if verbose {
            print("Setting screensaver '\(screensaverName)' on Display \(displayNumber)...")
        }

        do {
            try await paperSaver.setScreensaverForDisplay(module: screensaverName, displayNumber: displayNumber)
            print("\u{2705} Successfully set screensaver '\(screensaverName)' on Display \(displayNumber)")

            if verbose {
                print("\nNote: This sets the screensaver on all spaces of Display \(displayNumber)")
                print("\nYou may need to restart the wallpaper agent for changes to take effect:")
                print("  killall WallpaperAgent")
            }
        } catch PaperSaverError.displayNotFound(let displayNum) {
            printError("Error: Display \(displayNum) not found")
            print("\nUse 'papersaver list-spaces' to see available displays")
            throw ExitCode.failure
        } catch PaperSaverError.screensaverNotFound(let name) {
            printError("Error: Screensaver '\(name)' not found")
            throw ExitCode.failure
        }
    }

    private func setScreensaverForSpace(_ paperSaver: PaperSaverKit.PaperSaver) async throws {
        guard #available(macOS 14.0, *) else {
            printError("Error: Space commands require macOS 14.0 (Sonoma) or later")
            throw ExitCode.failure
        }

        if let spaceUUID = targeting.spaceUuid {
            do {
                try await paperSaver.setScreensaverForSpace(module: screensaverName, spaceUUID: spaceUUID, screen: nil)
                let shortUUID = String(spaceUUID.prefix(8)) + "..."
                print("\u{2705} Successfully set screensaver '\(screensaverName)' for space UUID \(shortUUID)")
            } catch PaperSaverError.screensaverNotFound(let name) {
                printError("Error: Screensaver '\(name)' not found")
                throw ExitCode.failure
            }
        } else {
            printError("Error: --space-uuid is required for space targeting without display")
            print("Usage: papersaver set-saver <name> --space-uuid <uuid>")
            throw ExitCode.failure
        }
    }
}

// MARK: - SetPaper Command

struct SetPaper: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "set-paper",
        abstract: "Set wallpaper with unified targeting options"
    )

    @Argument(help: "Path to wallpaper image")
    var imagePath: String

    @OptionGroup var targeting: TargetingOptions

    func run() async throws {
        let paperSaver = PaperSaverKit.PaperSaver()
        let imageURL = URL(fileURLWithPath: imagePath)
        let wallpaperOptions = WallpaperOptions()

        if targeting.isEverywhere {
            try await paperSaver.setWallpaperEverywhere(imageURL: imageURL, options: wallpaperOptions)
            print("\u{2705} Successfully set wallpaper everywhere")
        } else if targeting.hasDisplayTarget && targeting.hasSpaceTarget {
            try await setWallpaperForDisplaySpace(paperSaver, imageURL: imageURL, options: wallpaperOptions)
        } else if targeting.hasDisplayTarget {
            try await setWallpaperForDisplay(paperSaver, imageURL: imageURL, options: wallpaperOptions)
        } else if targeting.hasSpaceTarget {
            try await setWallpaperForSpace(paperSaver, imageURL: imageURL, options: wallpaperOptions)
        }
    }

    private func setWallpaperForDisplaySpace(_ paperSaver: PaperSaverKit.PaperSaver, imageURL: URL, options: WallpaperOptions) async throws {
        guard #available(macOS 14.0, *) else {
            printError("Error: Display/Space commands require macOS 14.0 (Sonoma) or later")
            throw ExitCode.failure
        }

        guard let displayNumber = targeting.display, let spaceNumber = targeting.space else {
            throw ValidationError("Both --display and --space are required for this operation")
        }

        try await paperSaver.setWallpaperForDisplaySpace(
            imageURL: imageURL,
            displayNumber: displayNumber,
            spaceNumber: spaceNumber,
            options: options
        )
        print("\u{2705} Successfully set wallpaper for display \(displayNumber) space \(spaceNumber)")
    }

    private func setWallpaperForDisplay(_ paperSaver: PaperSaverKit.PaperSaver, imageURL: URL, options: WallpaperOptions) async throws {
        guard #available(macOS 14.0, *) else {
            printError("Error: Display commands require macOS 14.0 (Sonoma) or later")
            throw ExitCode.failure
        }

        guard let displayNumber = targeting.display else {
            throw ValidationError("--display is required for this operation")
        }

        try await paperSaver.setWallpaperForDisplay(
            imageURL: imageURL,
            displayNumber: displayNumber,
            options: options
        )
        print("\u{2705} Successfully set wallpaper for display \(displayNumber)")
    }

    private func setWallpaperForSpace(_ paperSaver: PaperSaverKit.PaperSaver, imageURL: URL, options: WallpaperOptions) async throws {
        guard #available(macOS 14.0, *) else {
            printError("Error: Space commands require macOS 14.0 (Sonoma) or later")
            throw ExitCode.failure
        }

        guard let spaceUUID = targeting.spaceUuid else {
            printError("Error: --space-uuid is required for space targeting without display")
            throw ExitCode.failure
        }

        try await paperSaver.setWallpaperForSpace(
            imageURL: imageURL,
            spaceUUID: spaceUUID,
            screen: nil,
            options: options
        )
        print("\u{2705} Successfully set wallpaper for space \(spaceUUID)")
    }
}

// MARK: - RestoreBackup Command

struct RestoreBackup: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "restore-backup",
        abstract: "Restore wallpaper/screensaver settings from backup"
    )

    @Flag(name: .shortAndLong, help: "Show verbose output")
    var verbose = false

    @Flag(name: .shortAndLong, help: "Skip confirmation prompts")
    var force = false

    func run() async throws {
        guard #available(macOS 14.0, *) else {
            printError("Error: Restore requires macOS 14.0 (Sonoma) or later")
            throw ExitCode.failure
        }

        let paperSaver = PaperSaverKit.PaperSaver()

        if verbose {
            print("Checking for backup file...")
        }

        let backupInfo = paperSaver.getBackupInfo()

        guard backupInfo.exists else {
            printError("Error: No backup file found")
            print("\nBackups are automatically created before each screensaver modification.")
            print("Make some screensaver changes first, then you can restore if needed.")
            throw ExitCode.failure
        }

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

        if !force {
            print("\n\u{26A0}\u{FE0F}  This will overwrite your current wallpaper/screensaver settings.")
            print("Are you sure you want to restore from backup? (y/N): ", terminator: "")

            if let response = readLine()?.lowercased(),
               response == "y" || response == "yes" {
                // Proceed
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
            print("\u{2705} Successfully restored wallpaper/screensaver settings from backup")

            if verbose {
                print("\nYou may need to restart the wallpaper agent for changes to take effect:")
                print("  killall WallpaperAgent")
            }
        } catch PaperSaverError.fileNotFound(_) {
            printError("Error: Backup file not found or is no longer accessible")
            throw ExitCode.failure
        }
    }
}

// MARK: - Helper Functions

func formatIdleTime(_ seconds: Int) -> String {
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

func printError(_ message: String) {
    fputs("\u{274C} \(message)\n", stderr)
}

@available(macOS 14.0, *)
func getScreensaverForSpace(_ paperSaver: PaperSaverKit.PaperSaver, spaceUUID: String, debug: Bool = false) -> String? {
    let plistManager = PlistManager.shared
    let indexPath = SystemPaths.wallpaperIndexPath

    let lookupUUID = spaceUUID.isEmpty ? "" : spaceUUID

    if debug {
        print("DEBUG: Looking up screensaver for space UUID: '\(spaceUUID)'")
        print("DEBUG: Using lookup UUID: '\(lookupUUID)'")
    }

    guard let plist = try? plistManager.read(at: indexPath) else {
        if debug { print("DEBUG: Failed to read plist") }
        return nil
    }

    var spaceConfig: [String: Any]?

    if let allSpacesAndDisplays = plist["AllSpacesAndDisplays"] as? [String: Any] {
        var hasValidScreensaverData = false

        if let idle = allSpacesAndDisplays["Idle"] as? [String: Any],
           let content = idle["Content"] as? [String: Any],
           let choices = content["Choices"] as? [[String: Any]],
           let firstChoice = choices.first,
           let configurationData = firstChoice["Configuration"] as? Data,
           !configurationData.isEmpty {
            hasValidScreensaverData = true
            if debug { print("DEBUG: AllSpacesAndDisplays.Idle has valid screensaver data") }
        }

        if !hasValidScreensaverData,
           let linked = allSpacesAndDisplays["Linked"] as? [String: Any],
           let content = linked["Content"] as? [String: Any],
           let choices = content["Choices"] as? [[String: Any]],
           let firstChoice = choices.first,
           let configurationData = firstChoice["Configuration"] as? Data,
           !configurationData.isEmpty {
            hasValidScreensaverData = true
            if debug { print("DEBUG: AllSpacesAndDisplays.Linked has valid screensaver data (Automatic mode)") }
        }

        if hasValidScreensaverData {
            spaceConfig = allSpacesAndDisplays
            if debug { print("DEBUG: Using AllSpacesAndDisplays configuration") }
        } else {
            if debug { print("DEBUG: AllSpacesAndDisplays exists but has no valid screensaver data, checking per-space config") }
        }
    }

    if spaceConfig == nil {
        if let spaces = plist["Spaces"] as? [String: Any], !spaces.isEmpty {
            if debug {
                print("DEBUG: Found \(spaces.keys.count) space configurations in plist")
                print("DEBUG: Space keys available: \(spaces.keys.sorted())")
            }

            if let config = spaces[lookupUUID] as? [String: Any] {
                spaceConfig = config
                if debug { print("DEBUG: Found exact match for UUID '\(lookupUUID)'") }
            } else if !lookupUUID.isEmpty {
                spaceConfig = spaces[""] as? [String: Any]
                if debug {
                    if spaceConfig != nil {
                        print("DEBUG: UUID '\(lookupUUID)' not found, using default space configuration")
                    } else {
                        print("DEBUG: UUID '\(lookupUUID)' not found, and no default configuration available")
                    }
                }
            }
        }
    }

    if spaceConfig == nil {
        if let systemDefault = plist["SystemDefault"] as? [String: Any] {
            if debug { print("DEBUG: Using SystemDefault configuration (lowest priority)") }
            spaceConfig = systemDefault
        }
    }

    guard let config = spaceConfig else {
        if debug { print("DEBUG: No valid space config found") }
        return nil
    }

    if debug {
        print("DEBUG: Space UUID value: '\(spaceUUID)', isEmpty: \(spaceUUID.isEmpty)")
    }

    if let idle = config["Idle"] as? [String: Any],
       let content = idle["Content"] as? [String: Any],
       let choices = content["Choices"] as? [[String: Any]],
       let firstChoice = choices.first,
       let configurationData = firstChoice["Configuration"] as? Data {

        if debug {
            print("DEBUG: Using direct Idle configuration (SystemDefault)")
        }

        if let (name, type) = try? plistManager.decodeScreensaverConfigurationWithType(from: configurationData) {
            if let screensaverName = name {
                if debug {
                    print("DEBUG: Successfully decoded screensaver name from SystemDefault: '\(screensaverName)' type: '\(type.displayName)'")
                }
                return "\(screensaverName) (\(type.displayName))"
            }
        }

        if let moduleName = try? plistManager.decodeScreensaverConfiguration(from: configurationData) {
            if debug {
                print("DEBUG: Old method decoded module name from SystemDefault: '\(moduleName)'")
            }
            return moduleName
        }
    }

    if let linked = config["Linked"] as? [String: Any],
       let content = linked["Content"] as? [String: Any],
       let choices = content["Choices"] as? [[String: Any]],
       let firstChoice = choices.first {

        if debug {
            print("DEBUG: Using direct Linked configuration")
        }

        if let provider = firstChoice["Provider"] as? String {
            if debug {
                print("DEBUG: Linked provider: '\(provider)'")
            }

            if provider == "com.apple.wallpaper.choice.image" ||
               provider == "com.apple.wallpaper.choice.dynamic" ||
               provider.starts(with: "com.apple.wallpaper.") {
                if debug {
                    print("DEBUG: Detected Automatic mode (wallpaper as screensaver)")
                }
                return "Automatic (uses wallpaper)"
            }
        }

        if let configurationData = firstChoice["Configuration"] as? Data {
            if let (name, type) = try? plistManager.decodeScreensaverConfigurationWithType(from: configurationData) {
                if let screensaverName = name {
                    if debug {
                        print("DEBUG: Successfully decoded screensaver name from Linked: '\(screensaverName)' type: '\(type.displayName)'")
                    }
                    return "\(screensaverName) (\(type.displayName))"
                }
            }

            if let moduleName = try? plistManager.decodeScreensaverConfiguration(from: configurationData) {
                if debug {
                    print("DEBUG: Old method decoded module name from Linked: '\(moduleName)'")
                }
                return moduleName
            }
        }
    }

    if debug {
        print("DEBUG: Checking for Default section for space UUID '\(spaceUUID)'")
        if let defaultConfig = config["Default"] as? [String: Any] {
            print("DEBUG: Found Default config")
            if defaultConfig["Idle"] is [String: Any] {
                print("DEBUG: Found Idle in Default")
            }
            if defaultConfig["Linked"] is [String: Any] {
                print("DEBUG: Found Linked in Default")
            }
        } else {
            print("DEBUG: No Default section found")
        }
    }

    if let defaultConfig = config["Default"] as? [String: Any] {
        if debug {
            print("DEBUG: Checking Default -> Idle for space UUID '\(spaceUUID)'")
            if defaultConfig["Idle"] != nil {
                print("DEBUG: Found Idle in Default section")
            } else {
                print("DEBUG: No Idle found in Default section")
            }
        }

        if let idle = defaultConfig["Idle"] as? [String: Any],
           let content = idle["Content"] as? [String: Any],
           let choices = content["Choices"] as? [[String: Any]],
           let firstChoice = choices.first,
           let configurationData = firstChoice["Configuration"] as? Data {

            if debug {
                print("DEBUG: Using Default -> Idle configuration for space UUID '\(spaceUUID)' (takes precedence over Linked)")
            }

            if let (name, type) = try? plistManager.decodeScreensaverConfigurationWithType(from: configurationData) {
                if let screensaverName = name {
                    if debug {
                        print("DEBUG: Successfully decoded screensaver name from Default: '\(screensaverName)' type: '\(type.displayName)'")
                    }
                    return "\(screensaverName) (\(type.displayName))"
                }
            }

            if let moduleName = try? plistManager.decodeScreensaverConfiguration(from: configurationData) {
                if debug {
                    print("DEBUG: Old method decoded module name from Default: '\(moduleName)'")
                }
                return moduleName
            }
        }
    }

    if let defaultConfig = config["Default"] as? [String: Any],
       let linked = defaultConfig["Linked"] as? [String: Any],
       let content = linked["Content"] as? [String: Any],
       let choices = content["Choices"] as? [[String: Any]],
       let firstChoice = choices.first,
       let configurationData = firstChoice["Configuration"] as? Data {

        if debug {
            print("DEBUG: Found Linked configuration with nested Content structure in Default")
            print("DEBUG: Configuration data size: \(configurationData.count) bytes")
            print("DEBUG: First choice keys: \(firstChoice.keys.sorted())")
            if let provider = firstChoice["Provider"] as? String {
                print("DEBUG: Provider: '\(provider)'")
            }
        }

        if let provider = firstChoice["Provider"] as? String,
           provider == "com.apple.NeptuneOneExtension" && configurationData.isEmpty {
            if debug {
                print("DEBUG: Found Neptune extension with empty config - this is a dynamic desktop")
            }
            return "Dynamic Desktop (App Extension)"
        }

        if let (name, type) = try? plistManager.decodeScreensaverConfigurationWithType(from: configurationData) {
            if let screensaverName = name {
                if debug {
                    print("DEBUG: Successfully decoded Linked screensaver name from Default: '\(screensaverName)' type: '\(type.displayName)'")
                }
                return "\(screensaverName) (\(type.displayName))"
            } else {
                if debug {
                    print("DEBUG: Type-aware method returned nil name for type: '\(type.displayName)'")
                }
            }
        } else {
            if debug {
                print("DEBUG: Type-aware decoding failed for Linked configuration")
            }
        }

        if let moduleName = try? plistManager.decodeScreensaverConfiguration(from: configurationData) {
            if debug {
                print("DEBUG: Old method decoded Linked module name from Default: '\(moduleName)'")
            }
            return moduleName
        } else {
            if debug {
                print("DEBUG: Old method also failed to decode Linked configuration")
            }
        }
    }

    if let defaultConfig = config["Default"] as? [String: Any],
       let linked = defaultConfig["Linked"] as? [String: Any],
       let provider = linked["Provider"] as? String {

        if debug {
            print("DEBUG: Found simple Linked configuration in Default with provider: '\(provider)'")
        }

        if provider == "com.apple.NeptuneOneExtension" {
            if debug {
                print("DEBUG: Linked configuration is a dynamic desktop")
            }
            return "Dynamic Desktop (App Extension)"
        }
    }

    guard let displays = config["Displays"] as? [String: Any] else {
        if debug { print("DEBUG: No Displays found in space config") }
        return nil
    }

    if debug {
        print("DEBUG: Found \(displays.keys.count) displays in space configuration")
    }

    let connectedDisplays = paperSaver.listDisplays().filter { $0.isConnected }
    let connectedUUIDs = Set(connectedDisplays.map { $0.uuid })

    if debug {
        print("DEBUG: Connected display UUIDs: \(connectedUUIDs)")
        print("DEBUG: Available display keys in space: \(displays.keys.sorted())")
    }

    func isValidDisplayKey(_ key: String) -> Bool {
        let uuidPattern = "^[0-9A-F]{8}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{12}$"
        let regex = try? NSRegularExpression(pattern: uuidPattern, options: [.caseInsensitive])
        let range = NSRange(location: 0, length: key.count)
        return regex?.firstMatch(in: key, options: [], range: range) != nil
    }

    var displayKeysToCheck: [String] = []

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

    let validDisplayKeys = displays.keys.filter(isValidDisplayKey).sorted()
    for displayKey in validDisplayKeys {
        if !displayKeysToCheck.contains(displayKey) {
            displayKeysToCheck.append(displayKey)
        }
    }

    if debug {
        print("DEBUG: Processing displays in priority order: \(displayKeysToCheck)")
    }

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

        if let idle = displayConfig["Idle"] as? [String: Any],
           let content = idle["Content"] as? [String: Any],
           let choices = content["Choices"] as? [[String: Any]],
           let firstChoice = choices.first,
           let configurationData = firstChoice["Configuration"] as? Data {

            if debug {
                print("DEBUG: Display '\(displayKey)' Idle keys: \(idle.keys.sorted())")
                print("DEBUG: Display '\(displayKey)' Content keys: \(content.keys.sorted())")
                print("DEBUG: Display '\(displayKey)' has \(choices.count) choice(s)")
                print("DEBUG: Display '\(displayKey)' first choice keys: \(firstChoice.keys.sorted())")

                if let provider = firstChoice["Provider"] as? String {
                    print("DEBUG: Display '\(displayKey)' provider: '\(provider)'")
                }
                print("DEBUG: Display '\(displayKey)' configuration data size: \(configurationData.count) bytes")
            }

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
        } else {
            if debug {
                print("DEBUG: Display '\(displayKey)' has no Idle configuration")
            }
        }

        if let linked = displayConfig["Linked"] as? [String: Any],
           let content = linked["Content"] as? [String: Any],
           let choices = content["Choices"] as? [[String: Any]],
           let firstChoice = choices.first,
           let configurationData = firstChoice["Configuration"] as? Data {

            if debug {
                print("DEBUG: Display '\(displayKey)' found Linked configuration with nested Content structure")
                print("DEBUG: Display '\(displayKey)' configuration data size: \(configurationData.count) bytes")
                if let provider = firstChoice["Provider"] as? String {
                    print("DEBUG: Display '\(displayKey)' provider: '\(provider)'")
                }
            }

            if let provider = firstChoice["Provider"] as? String,
               provider == "com.apple.NeptuneOneExtension" && configurationData.isEmpty {
                if debug {
                    print("DEBUG: Display '\(displayKey)' found Neptune extension with empty config - this is a dynamic desktop")
                }
                return "Dynamic Desktop (App Extension)"
            }

            if let (name, type) = try? plistManager.decodeScreensaverConfigurationWithType(from: configurationData) {
                if let screensaverName = name {
                    if debug {
                        print("DEBUG: Successfully decoded Linked screensaver name from display '\(displayKey)': '\(screensaverName)' type: '\(type.displayName)'")
                    }
                    return "\(screensaverName) (\(type.displayName))"
                }
            }

            if let moduleName = try? plistManager.decodeScreensaverConfiguration(from: configurationData) {
                if debug {
                    print("DEBUG: Old method decoded Linked module name from display '\(displayKey)': '\(moduleName)'")
                }
                return moduleName
            }
        }

        if let linked = displayConfig["Linked"] as? [String: Any],
           let provider = linked["Provider"] as? String {

            if debug {
                print("DEBUG: Display '\(displayKey)' found simple Linked configuration with provider: '\(provider)'")
            }

            if provider == "com.apple.NeptuneOneExtension" {
                if debug {
                    print("DEBUG: Display '\(displayKey)' Linked configuration is a dynamic desktop")
                }
                return "Dynamic Desktop (App Extension)"
            }
        }
    }

    if debug {
        print("DEBUG: No screensaver configuration found in any display")
    }
    return nil
}

@available(macOS 14.0, *)
func getWallpaperForSpace(spaceUUID: String, debug: Bool = false) -> String? {
    let plistManager = PlistManager.shared
    let indexPath = SystemPaths.wallpaperIndexPath

    let lookupUUID = spaceUUID.isEmpty ? "" : spaceUUID

    if debug {
        print("DEBUG: Looking up wallpaper for space UUID: '\(spaceUUID)'")
        print("DEBUG: Using lookup UUID: '\(lookupUUID)'")
    }

    guard let plist = try? plistManager.read(at: indexPath) else {
        if debug { print("DEBUG: Failed to read plist") }
        return nil
    }

    var spaceConfig: [String: Any]?

    if let spaces = plist["Spaces"] as? [String: Any], !spaces.isEmpty {
        if debug {
            print("DEBUG: Found \(spaces.keys.count) space configurations in plist")
        }

        if let config = spaces[lookupUUID] as? [String: Any] {
            spaceConfig = config
            if debug { print("DEBUG: Found exact match for UUID '\(lookupUUID)'") }
        } else if !lookupUUID.isEmpty {
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
        if debug { print("DEBUG: No Spaces configurations found, using AllSpacesAndDisplays configuration") }
        spaceConfig = allSpacesAndDisplays
    } else if let systemDefault = plist["SystemDefault"] as? [String: Any] {
        if debug { print("DEBUG: No Spaces or AllSpacesAndDisplays found, using SystemDefault configuration") }
        spaceConfig = systemDefault
    }

    guard let config = spaceConfig else {
        if debug { print("DEBUG: No valid space config found") }
        return nil
    }

    var wallpaperConfig: [String: Any]?
    var provider: String?
    var firstChoice: [String: Any]?

    if let systemDesktop = config["Desktop"] as? [String: Any] {
        wallpaperConfig = systemDesktop
        if debug { print("DEBUG: Found Desktop directly in config (SystemDefault)") }
    } else if let defaultConfig = config["Default"] as? [String: Any],
              let defaultDesktop = defaultConfig["Desktop"] as? [String: Any] {
        wallpaperConfig = defaultDesktop
        if debug { print("DEBUG: Found Desktop under Default section") }
    } else if let systemLinked = config["Linked"] as? [String: Any] {
        wallpaperConfig = systemLinked
        if debug { print("DEBUG: Found Linked directly in config (Automatic mode)") }
    } else if let defaultConfig = config["Default"] as? [String: Any],
              let defaultLinked = defaultConfig["Linked"] as? [String: Any] {
        wallpaperConfig = defaultLinked
        if debug { print("DEBUG: Found Linked under Default section (Automatic mode)") }
    }

    guard let wallpaperConfiguration = wallpaperConfig,
          let content = wallpaperConfiguration["Content"] as? [String: Any],
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

    guard providerName == "com.apple.wallpaper.choice.image" else {
        if debug { print("DEBUG: Provider is not an image type: \(providerName)") }
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

    if let urlString = try? plistManager.decodeWallpaperConfiguration(from: configurationData),
       let url = URL(string: urlString) {
        if debug {
            print("DEBUG: Decoded wallpaper URL: \(url)")
        }
        return url.path
    }

    if debug { print("DEBUG: Failed to decode wallpaper configuration") }
    return nil
}

@available(macOS 14.0, *)
func printSpaceTree(_ paperSaver: PaperSaverKit.PaperSaver, _ spaceTree: [String: Any], debug: Bool = false) {
    let displayColor = "\u{001B}[1;36m"
    let spaceColor = "\u{001B}[1;33m"
    let activeColor = "\u{001B}[1;32m"
    let uuidColor = "\u{001B}[34m"
    let wallpaperColor = "\u{001B}[35m"
    let screensaverColor = "\u{001B}[36m"
    let reset = "\u{001B}[0m"

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

            let wallpaperInfo = getWallpaperForSpace(spaceUUID: spaceUUID, debug: debug) ?? "None"
            print("    \u{2514}\u{2500} \(wallpaperColor)Wallpaper\(reset): \(wallpaperInfo)")

            if debug {
                print("    === SCREENSAVER DEBUG FOR SPACE \(spaceNumber) ===")
            }
            let screensaver = getScreensaverForSpace(paperSaver, spaceUUID: spaceUUID, debug: debug) ?? "None"
            print("    \u{2514}\u{2500} \(screensaverColor)Screensaver\(reset): \(screensaver)")
            if debug {
                print("    === END SCREENSAVER DEBUG ===")
                print("    \u{2514}\u{2500} \(uuidColor)UUID\(reset): \(spaceUUID)")
                print("    \u{2514}\u{2500} \(uuidColor)ID\(reset): \(spaceID)")
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

// MARK: - String Extension

extension String {
    static func * (left: String, right: Int) -> String {
        return String(repeating: left, count: right)
    }
}
