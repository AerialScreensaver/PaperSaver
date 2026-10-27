import Foundation
import ArgumentParser
import PaperSaverKit

@main
struct PaperSaverCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "papersaver",
        abstract: "Select screensavers and wallpapers from the command line.",
        discussion: """
            Writes the wallpaper store System Settings reads (~/Library/Application Support/\
            com.apple.wallpaper/Store/Index.plist), restarts WallpaperAgent and checks the agent \
            kept the change. Static images go through NSWorkspace and need no restart.
            """,
        version: PaperSaverKitInfo.version,
        subcommands: [
            ListCommand.self, GetCommand.self, IdleTimeCommand.self,
            ListSpacesCommand.self, ListDisplaysCommand.self, GetSpaceCommand.self,
            SetSaverCommand.self, SetPaperCommand.self, GetPaperCommand.self,
            WallpaperExtensionCommand.self, StoreCommand.self, RepairOptionsCommand.self,
            RestoreBackupCommand.self,
        ])
}

// MARK: - Shared options

struct OutputOptions: ParsableArguments {
    @Flag(name: .shortAndLong, help: "Print JSON.")
    var json = false

    @Flag(name: .shortAndLong, help: "Print what the library does, to standard error.")
    var verbose = false
}

struct WriteFlags: ParsableArguments {
    @Flag(name: .customLong("no-restart"), help: "Write the store without restarting WallpaperAgent (the change applies at the next restart).")
    var noRestart = false

    @Flag(name: .customLong("no-verify"), help: "Restart the agent but do not read the store back.")
    var noVerify = false

    @Flag(name: .customLong("no-rollback"), help: "Leave the written store in place when verification fails.")
    var noRollback = false

    var options: WriteOptions {
        var options = WriteOptions.default
        options.restartAgent = !noRestart
        options.verify = !noRestart && !noVerify
        options.rollbackOnFailure = !noRollback
        return options
    }
}

/// `--display N | --display-uuid U` and `--space N | --space-uuid S`, resolved to one store target.
struct TargetingOptions: ParsableArguments {
    @Option(name: .long, help: "A display by number, as `list-displays` prints them (1 is the main display).")
    var display: Int?

    @Option(name: .customLong("display-uuid"), help: "A display by UUID.")
    var displayUUID: String?

    @Option(name: .long, help: "A Space by number, as `list-spaces` prints them.")
    var space: Int?

    @Option(name: .customLong("space-uuid"), help: "A Space by UUID.")
    var spaceUUID: String?

    func validate() throws {
        if display != nil && displayUUID != nil { throw ValidationError("Use --display or --display-uuid, not both.") }
        if space != nil && spaceUUID != nil { throw ValidationError("Use --space or --space-uuid, not both.") }
    }

    func resolve() throws -> StoreTarget {
        let topology = DisplayTopology.snapshot()
        var resolvedDisplay: String? = displayUUID
        if let display {
            guard let uuid = topology.display(number: display)?.uuid else {
                throw PaperSaverError.displayNotFound("\(display) (see `papersaver list-displays`)")
            }
            resolvedDisplay = uuid
        }
        var resolvedSpace: String? = spaceUUID
        if let space {
            guard let uuid = topology.displays.flatMap(\.spaces).first(where: { $0.number == space })?.uuid else {
                throw PaperSaverError.spaceNotFound("\(space) (see `papersaver list-spaces`)")
            }
            resolvedSpace = uuid
        }
        switch (resolvedDisplay, resolvedSpace) {
        case (nil, nil): return .everywhere
        case (let d?, nil): return .display(uuid: d)
        case (nil, let s?): return .space(uuid: s)
        case (let d?, let s?): return .spaceOnDisplay(spaceUUID: s, displayUUID: d)
        }
    }
}

// MARK: - Helpers

func makePaperSaver(verbose: Bool) -> PaperSaver {
    var configuration = PaperSaverConfiguration()
    configuration.log = verbose ? .standardError(minimumLevel: .debug) : .standardError(minimumLevel: .warning)
    return PaperSaver(configuration: configuration)
}

func printJSON<T: Encodable>(_ value: T) throws {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    print(String(decoding: try encoder.encode(value), as: UTF8.self))
}

func printError(_ message: String) {
    FileHandle.standardError.write(Data("error: \(message)\n".utf8))
}

func describe(_ outcome: WriteOutcome) -> String {
    switch outcome {
    case .applied: return "applied and verified"
    case .appliedUnverified: return "applied (not verified)"
    case .appliedButExtensionNotRunning: return "written and verified, but the extension has no running process; run again or killall WallpaperAgent"
    case .writtenWithoutRestart: return "written; restart WallpaperAgent to apply (killall WallpaperAgent)"
    }
}

func describe(_ target: StoreTarget) -> String {
    switch target {
    case .everywhere: return "every display and Space"
    case .space(let uuid): return "Space \(uuid)"
    case .display(let uuid): return "display \(uuid)"
    case .spaceOnDisplay(let space, let display): return "Space \(space) on display \(display)"
    }
}

func formatIdleTime(_ seconds: Int) -> String {
    if seconds == 0 { return "Never" }
    if seconds < 60 { return "\(seconds) seconds" }
    if seconds < 3600 { let m = seconds / 60; return "\(m) minute\(m == 1 ? "" : "s")" }
    let h = seconds / 3600, m = (seconds % 3600) / 60
    return "\(h) hour\(h == 1 ? "" : "s")" + (m == 0 ? "" : " \(m) minute\(m == 1 ? "" : "s")")
}

/// Runs a store write and turns library errors into exit codes.
///
/// `body` is escaping on purpose: Swift 6.1 crashes (ClosureLifetimeFixup, signal 11) and
/// Swift 6.3 hangs compiling a non-escaping async closure passed here from a command's `run()`.
/// Callers capture local copies, never `self`.
func performWrite(_ description: String, _ body: @escaping @Sendable () async throws -> WriteOutcome) async throws {
    do {
        let outcome = try await body()
        print("\(description): \(describe(outcome))")
    } catch let error as PaperSaverError {
        printError(error.localizedDescription)
        throw ExitCode.failure
    }
}
