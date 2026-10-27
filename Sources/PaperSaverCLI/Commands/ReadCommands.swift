import Foundation
import ArgumentParser
import PaperSaverKit

struct ListCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "list", abstract: "List the installed screensavers.")

    @OptionGroup var output: OutputOptions

    func run() async throws {
        let modules = await makePaperSaver(verbose: output.verbose).listAvailableScreensavers()
        if output.json { return try printJSON(modules) }
        guard !modules.isEmpty else { return print("No screensavers found.") }
        for (title, group) in [("System screensavers", modules.filter(\.isSystem)), ("Other screensavers", modules.filter { !$0.isSystem })] where !group.isEmpty {
            print("\(title):")
            for module in group.sorted(by: { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }) {
                print("  \(module.name) (\(module.type.displayName))")
                if output.verbose { print("    \(module.path.path)") }
            }
        }
        print("\(modules.count) screensaver(s).")
    }
}

struct GetCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "get", abstract: "Show the selected screensaver.")

    @OptionGroup var output: OutputOptions
    @OptionGroup var targeting: TargetingOptions

    func run() async throws {
        let target = try targeting.resolve()
        guard let info = makePaperSaver(verbose: output.verbose).activeScreensaver(in: target) else {
            if output.json { print("{}") } else { print("No screensaver selected for \(describe(target)).") }
            return
        }
        if output.json { return try printJSON(info) }
        print("Screensaver: \(info.name) (\(info.kind.displayName))")
        if let path = info.modulePath { print("Module:      \(path)") }
        print("Provider:    \(info.provider)")
    }
}

struct IdleTimeCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "idle-time", abstract: "Read or set the delay before the screensaver starts.",
        subcommands: [Get.self, Set.self], defaultSubcommand: Get.self)

    struct Get: AsyncParsableCommand {
        static let configuration = CommandConfiguration(commandName: "get", abstract: "Read the idle delay.")
        @Flag(name: .shortAndLong, help: "Print JSON.") var json = false
        func run() async throws {
            let seconds = PaperSaver().getIdleTime()
            if json { print("{\"idleTime\": \(seconds)}") } else { print("Idle time: \(formatIdleTime(seconds))") }
        }
    }

    struct Set: AsyncParsableCommand {
        static let configuration = CommandConfiguration(commandName: "set", abstract: "Set the idle delay (0 = never).")
        @Argument(help: "Seconds.") var seconds: Int
        func run() async throws {
            try PaperSaver().setIdleTime(seconds: seconds)
            print("Idle time set to \(formatIdleTime(seconds)).")
        }
    }
}

struct DisplaySleepCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "display-sleep", abstract: "Read the delay before the display turns off (change it in System Settings).",
        subcommands: [Get.self], defaultSubcommand: Get.self)

    struct Get: AsyncParsableCommand {
        static let configuration = CommandConfiguration(commandName: "get", abstract: "Read the display sleep delay.")
        @Flag(name: .shortAndLong, help: "Print JSON.") var json = false
        func run() async throws {
            guard let minutes = await PaperSaver().getDisplaySleep() else {
                throw ValidationError("pmset reported no display sleep setting")
            }
            if json { print("{\"displaySleep\": \(minutes)}") } else { print("Display sleep: \(formatIdleTime(minutes * 60))") }
        }
    }
}

struct ListSpacesCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "list-spaces", abstract: "List the connected displays and their Spaces, with the screensaver selected for each.")

    @OptionGroup var output: OutputOptions

    func run() async throws {
        let saver = makePaperSaver(verbose: output.verbose)
        let displays = saver.displaySpaces()
        if output.json { return try printJSON(displays) }
        for display in displays {
            print("Display \(display.displayNumber): \(display.name)")
            print("  UUID: \(display.uuid)")
            for space in display.spaces {
                let name = saver.activeScreensaver(in: .spaceOnDisplay(spaceUUID: space.uuid, displayUUID: display.uuid))?.name ?? "none"
                print("  Space \(space.number)\(space.isCurrent ? " (current)" : ""): \(space.uuid.isEmpty ? "\"\"" : space.uuid)  screensaver: \(name)")
            }
        }
    }
}

struct ListDisplaysCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "list-displays", abstract: "List every display the window server remembers.")

    @OptionGroup var output: OutputOptions

    func run() async throws {
        let saver = makePaperSaver(verbose: output.verbose)
        let displays = await MainActor.run { saver.listDisplays() }
        if output.json { return try printJSON(displays) }
        let numbers = Dictionary(uniqueKeysWithValues: saver.displaySpaces().map { ($0.uuid, $0.displayNumber) })
        for display in displays {
            let number = numbers[display.uuid].map { "Display \($0): " } ?? ""
            print("\(number)\(display.friendlyName) (\(display.displayDescription))\(display.isConnected ? "" : " [disconnected]")")
            print("  UUID: \(display.uuid)")
            if let id = display.displayID { print("  Display ID: \(id)") }
            if let frame = display.frame { print("  Position: (\(Int(frame.origin.x)), \(Int(frame.origin.y)))") }
        }
        print("\(displays.count) display(s), \(displays.filter(\.isConnected).count) connected.")
    }
}

struct GetSpaceCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "get-space", abstract: "Show the Space on screen.")

    @OptionGroup var output: OutputOptions

    func run() async throws {
        guard let space = makePaperSaver(verbose: output.verbose).getActiveSpace() else {
            if output.json { print("{}") } else { print("No active Space found.") }
            return
        }
        if output.json { return try printJSON(space) }
        print("Active Space: \(space.uuid.isEmpty ? "(first Space)" : space.uuid)")
        if let id = space.spaceID { print("Space ID: \(id)") }
        if !space.displayUUIDs.isEmpty { print("Displays: \(space.displayUUIDs.joined(separator: ", "))") }
    }
}
