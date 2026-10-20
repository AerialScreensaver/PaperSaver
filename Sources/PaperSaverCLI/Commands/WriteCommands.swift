import Foundation
import AppKit
import ArgumentParser
import PaperSaverKit

extension WallpaperPlacement: ExpressibleByArgument {}

struct SetSaverCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "set-saver",
        abstract: "Select a screensaver by name.",
        discussion: "The name is the bundle's file name without extension, as `list` prints it. The desktop wallpaper is left alone.")

    @Argument(help: "The screensaver name.") var name: String
    @OptionGroup var targeting: TargetingOptions
    @OptionGroup var write: WriteFlags
    @Flag(name: .shortAndLong, help: "Print what the library does, to standard error.") var verbose = false

    func run() async throws {
        let target = try targeting.resolve()
        let saver = makePaperSaver(verbose: verbose)
        try await performWrite("Screensaver \(name) for \(describe(target))") {
            try await saver.setScreensaver(module: name, target: target, options: write.options)
        }
    }
}

struct SetPaperCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "set-paper",
        abstract: "Set a static image as the desktop wallpaper.",
        discussion: "Goes through NSWorkspace, which applies the image at once. With --space-uuid the image is written into the store for that Space instead.")

    @Argument(help: "An image file.", transform: { URL(fileURLWithPath: $0) }) var image: URL
    @Option(name: .long, help: "A display by number (1 is the main display); every display when omitted.") var display: Int?
    @Option(name: .customLong("display-uuid"), help: "A display by UUID.") var displayUUID: String?
    @Option(name: .long, help: "fill, fit, stretch or center.") var placement: WallpaperPlacement = .fill
    @Option(name: .customLong("space-uuid"), help: "Write the image into the store for this Space (restarts WallpaperAgent).") var spaceUUID: String?
    @OptionGroup var write: WriteFlags
    @Flag(name: .shortAndLong, help: "Print what the library does, to standard error.") var verbose = false

    func run() async throws {
        let saver = makePaperSaver(verbose: verbose)
        if let spaceUUID {
            var target = StoreTarget.space(uuid: spaceUUID)
            if let uuid = try resolvedDisplayUUID() { target = .spaceOnDisplay(spaceUUID: spaceUUID, displayUUID: uuid) }
            try await performWrite("Image \(image.lastPathComponent) for \(describe(target))") {
                try await saver.setWallpaper(imageURL: image, target: target, options: write.options)
            }
            return
        }
        let displayTarget: DisplayTarget = try resolvedDisplayUUID().map { .uuid($0) } ?? .all
        let image = self.image, placement = self.placement
        do {
            try await MainActor.run { try saver.setWallpaper(imageURL: image, on: displayTarget, placement: placement) }
            print("Wallpaper set to \(image.lastPathComponent) (\(placement.rawValue)).")
        } catch let error as PaperSaverError {
            printError(error.localizedDescription)
            throw ExitCode.failure
        }
    }

    private func resolvedDisplayUUID() throws -> String? {
        if let displayUUID { return displayUUID }
        guard let display else { return nil }
        guard let uuid = DisplayTopology.snapshot().display(number: display)?.uuid else {
            throw ValidationError("Display \(display) not found (see `papersaver list-displays`).")
        }
        return uuid
    }
}

struct GetPaperCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "get-paper", abstract: "Show the static image NSWorkspace reports for a display.")

    @Option(name: .long, help: "A display by number (1 is the main display); the main display when omitted.") var display: Int?
    @Option(name: .customLong("display-uuid"), help: "A display by UUID.") var displayUUID: String?
    @Flag(name: .shortAndLong, help: "Print JSON.") var json = false

    func run() async throws {
        var target: DisplayTarget = .main
        if let displayUUID { target = .uuid(displayUUID) }
        if let display {
            guard let uuid = DisplayTopology.snapshot().display(number: display)?.uuid else {
                throw ValidationError("Display \(display) not found (see `papersaver list-displays`).")
            }
            target = .uuid(uuid)
        }
        let saver = makePaperSaver(verbose: false)
        let info = await MainActor.run { saver.getCurrentWallpaper(for: target) }
        guard let info else {
            if json { print("{}") } else { print("No static image wallpaper reported for that display.") }
            return
        }
        if json { return try printJSON(info) }
        print("Image:     \(info.imagePath)")
        print("Placement: \(info.placement.rawValue)")
        if let uuid = info.displayUUID { print("Display:   \(uuid)") }
    }
}

struct WallpaperExtensionCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "wallpaper-extension",
        abstract: "Show, list, set or clear a wallpaper extension (com.apple.wallpaper extension point).",
        discussion: """
            Wallpaper extensions, such as Aerial 4.1, render the desktop and can also serve as the \
            screensaver. They are identified by bundle identifier. Screensaver extensions \
            (com.apple.screensaver extension point, like Apple's Flurry or the AppexSaverMinimal \
            sample) and .saver plug-ins are a different kind: select those by name with `set-saver`.
            """,
        subcommands: [Get.self, List.self, Set.self, Clear.self], defaultSubcommand: Get.self)

    struct List: AsyncParsableCommand {
        static let configuration = CommandConfiguration(commandName: "list", abstract: "List the registered wallpaper extensions.")
        @OptionGroup var output: OutputOptions

        func run() async throws {
            let extensions = try await makePaperSaver(verbose: output.verbose).listWallpaperExtensions()
                .sorted { ($0.isSystem ? 1 : 0, $0.bundleIdentifier) < ($1.isSystem ? 1 : 0, $1.bundleIdentifier) }
            if output.json { return try printJSON(extensions) }
            for ext in extensions {
                print("\(ext.bundleIdentifier)\(ext.version.isEmpty ? "" : " (\(ext.version))")\(ext.isSystem ? " [Apple]" : "")")
                if output.verbose { print("  \(ext.path.path)") }
            }
        }
    }

    enum SlotArgument: String, ExpressibleByArgument, CaseIterable {
        case desktop, screensaver, idle
        var slot: WallpaperSlot { self == .desktop ? .desktop : .screensaver }
    }

    enum OtherArgument: String, ExpressibleByArgument, CaseIterable {
        case keep, clear, clearIfSame = "clear-if-same", mirror
        var policy: OtherSlotPolicy {
            switch self {
            case .keep: return .keep
            case .clear: return .clearToSystemDefault
            case .clearIfSame: return .clearIfSameProvider
            case .mirror: return .mirror
            }
        }
    }

    enum StrategyArgument: String, ExpressibleByArgument, CaseIterable {
        case automatic, idleSection = "idle-section", materializeDesktop = "materialize-desktop"
        var strategy: ScreensaverOnlyStrategy {
            switch self {
            case .automatic: return .automatic
            case .idleSection: return .idleSection
            case .materializeDesktop: return .materializeSystemDefaultDesktop
            }
        }
    }

    struct Get: AsyncParsableCommand {
        static let configuration = CommandConfiguration(commandName: "get", abstract: "Show the extension in each slot.")
        @OptionGroup var output: OutputOptions
        @OptionGroup var targeting: TargetingOptions

        func run() async throws {
            let target = try targeting.resolve()
            let saver = makePaperSaver(verbose: output.verbose)
            let wallpaper = saver.getCurrentWallpaperExtension(in: target)
            let screensaver = saver.getCurrentScreensaverExtension(in: target)
            if output.json {
                struct Result: Encodable { let wallpaper: String?; let screensaver: String? }
                return try printJSON(Result(wallpaper: wallpaper, screensaver: screensaver))
            }
            print("Desktop wallpaper extension: \(wallpaper ?? "(none)")")
            print("Screensaver extension:       \(screensaver ?? "(none)")")
        }
    }

    struct Set: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "set", abstract: "Put a wallpaper extension in a slot.",
            discussion: "The bundle identifier must be one `wallpaper-extension list` prints. For a screensaver extension or a .saver plug-in, use `set-saver NAME`.")
        @Argument(help: "The wallpaper extension's bundle identifier, as `wallpaper-extension list` prints it.") var bundleID: String
        @Option(name: .long, help: "desktop or screensaver.") var slot: SlotArgument
        @Option(name: .long, help: "What happens to the other slot: keep, clear, clear-if-same (default) or mirror.") var other: OtherArgument = .clearIfSame
        @Option(name: .long, help: "The opaque configuration token the extension expects.") var config: String?
        @Option(name: .long, help: "How a screensaver-only section is written: automatic (default: idle-section when another section has a desktop, else materialize-desktop), idle-section or materialize-desktop.") var strategy: StrategyArgument = .automatic
        @OptionGroup var targeting: TargetingOptions
        @OptionGroup var write: WriteFlags
        @Flag(name: .shortAndLong, help: "Print what the library does, to standard error.") var verbose = false

        func run() async throws {
            let target = try targeting.resolve()
            var configuration = PaperSaverConfiguration()
            configuration.log = verbose ? .standardError(minimumLevel: .debug) : .standardError(minimumLevel: .warning)
            configuration.screensaverOnlyStrategy = strategy.strategy
            let saver = PaperSaver(configuration: configuration)
            try await performWrite("\(bundleID) as \(slot.slot.rawValue) for \(describe(target))") {
                try await saver.setWallpaperExtension(bundleID: bundleID, configuration: Data((config ?? "").utf8),
                                                      slot: slot.slot, otherSlot: other.policy, target: target, options: write.options)
            }
        }
    }

    struct Clear: AsyncParsableCommand {
        static let configuration = CommandConfiguration(commandName: "clear", abstract: "Put the system default back in a slot.")
        @Option(name: .long, help: "desktop or screensaver.") var slot: SlotArgument
        @OptionGroup var targeting: TargetingOptions
        @OptionGroup var write: WriteFlags
        @Flag(name: .shortAndLong, help: "Print what the library does, to standard error.") var verbose = false

        func run() async throws {
            let target = try targeting.resolve()
            let saver = makePaperSaver(verbose: verbose)
            try await performWrite("System default as \(slot.slot.rawValue) for \(describe(target))") {
                try await saver.clearWallpaperExtension(slot: slot.slot, target: target, options: write.options)
            }
        }
    }
}

struct StoreCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "store", abstract: "Inspect the wallpaper store.", subcommands: [Dump.self], defaultSubcommand: Dump.self)

    struct Dump: AsyncParsableCommand {
        static let configuration = CommandConfiguration(commandName: "dump", abstract: "Print every section of the store with its providers and option keys.")
        @OptionGroup var output: OutputOptions

        func run() async throws {
            let summary = StoreSummary(try makePaperSaver(verbose: output.verbose).readStore())
            if output.json { return try printJSON(summary) }
            for section in summary.sections {
                print("\(section.path) [\(section.type)]")
                for (label, slot) in [("Desktop", section.desktop), ("Idle", section.idle), ("Linked", section.linked)] {
                    guard let slot else { continue }
                    print("  \(label): \(slot.provider)")
                    print("    configuration: \(slot.configuration)")
                    print("    options: \(slot.optionValues)  shuffle: \(slot.shuffle)")
                }
            }
        }
    }
}

struct RestoreBackupCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "restore-backup", abstract: "Put back the store as it was before the last write.")

    @Flag(name: .shortAndLong, help: "Do not ask for confirmation.") var force = false
    @Flag(name: .customLong("no-restart"), help: "Do not restart WallpaperAgent afterwards.") var noRestart = false

    func run() async throws {
        let saver = makePaperSaver(verbose: false)
        guard let backup = saver.backupInfo() else {
            printError("no backup file; one is written before every store change")
            throw ExitCode.failure
        }
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .medium
        print("Backup from \(formatter.string(from: backup.modificationDate)), \(backup.size) bytes.")
        if !force {
            print("Overwrite the current wallpaper and screensaver selection with it? (y/N): ", terminator: "")
            guard let answer = readLine()?.lowercased(), answer == "y" || answer == "yes" else {
                print("Cancelled.")
                return
            }
        }
        do {
            try await saver.restoreFromBackup(restartAgent: !noRestart)
            print(noRestart ? "Restored; restart WallpaperAgent to apply." : "Restored and WallpaperAgent restarted.")
        } catch let error as PaperSaverError {
            printError(error.localizedDescription)
            throw ExitCode.failure
        }
    }
}
