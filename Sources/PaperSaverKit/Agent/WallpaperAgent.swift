import Foundation
import Darwin

/// Controls the `WallpaperAgent` process, which reads the store only when it starts.
public protocol WallpaperAgentControlling: Sendable {
    /// Ends the running agent. launchd starts a new one within about a second.
    func restart() async throws
    /// Waits until a new agent process is running.
    func waitForRespawn(timeout: Duration) async throws
    /// Waits until the app extension with that bundle identifier has a running process.
    func waitForExtension(bundleIdentifier: String, timeout: Duration) async -> Bool
}

/// The real agent: `killall WallpaperAgent`, then a poll of the process list.
public struct WallpaperAgent: WallpaperAgentControlling {
    public static let processName = "WallpaperAgent"

    public init() {}

    /// The process identifiers of every running `WallpaperAgent`.
    public static func runningProcessIdentifiers() -> Set<pid_t> {
        let count = proc_listallpids(nil, 0)
        guard count > 0 else { return [] }
        var pids = [pid_t](repeating: 0, count: Int(count) + 64)
        let filled = proc_listallpids(&pids, Int32(pids.count * MemoryLayout<pid_t>.size))
        guard filled > 0 else { return [] }
        var found = Set<pid_t>()
        var buffer = [CChar](repeating: 0, count: Int(MAXPATHLEN))
        for pid in pids.prefix(Int(filled)) where pid > 0 {
            let length = proc_name(pid, &buffer, UInt32(buffer.count))
            guard length > 0 else { continue }
            let name = String(decoding: buffer.prefix(Int(length)).map { UInt8(bitPattern: $0) }, as: UTF8.self)
            if name == processName { found.insert(pid) }
        }
        return found
    }

    /// The bundle identifiers of the app extensions running right now, found by their
    /// executable path (`….appex/Contents/MacOS/…`).
    public static func runningExtensionBundleIdentifiers() -> Set<String> {
        let count = proc_listallpids(nil, 0)
        guard count > 0 else { return [] }
        var pids = [pid_t](repeating: 0, count: Int(count) + 64)
        let filled = proc_listallpids(&pids, Int32(pids.count * MemoryLayout<pid_t>.size))
        guard filled > 0 else { return [] }
        var found = Set<String>()
        var buffer = [CChar](repeating: 0, count: 4 * Int(MAXPATHLEN))  // PROC_PIDPATHINFO_MAXSIZE
        for pid in pids.prefix(Int(filled)) where pid > 0 {
            let length = proc_pidpath(pid, &buffer, UInt32(buffer.count))
            guard length > 0 else { continue }
            let path = String(decoding: buffer.prefix(Int(length)).map { UInt8(bitPattern: $0) }, as: UTF8.self)
            if let identifier = appExtensionBundleIdentifier(forExecutablePath: path) { found.insert(identifier) }
        }
        return found
    }

    /// The bundle identifier of the `.appex` an executable path belongs to, or `nil` when the
    /// path is not inside an app extension.
    public static func appExtensionBundleIdentifier(forExecutablePath path: String) -> String? {
        guard let range = path.range(of: ".appex/Contents/MacOS/") else { return nil }
        let bundlePath = String(path[..<range.lowerBound]) + ".appex"
        return Bundle(path: bundlePath)?.bundleIdentifier
    }

    public func restart() async throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/killall")
        process.arguments = [Self.processName]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        let status: Int32 = try await withCheckedThrowingContinuation { continuation in
            process.terminationHandler = { continuation.resume(returning: $0.terminationStatus) }
            do {
                try process.run()
            } catch {
                process.terminationHandler = nil
                continuation.resume(throwing: PaperSaverError.agentRestartFailed(error.localizedDescription))
            }
        }
        let output = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        // killall exits 1 when no process matched; the agent then starts on demand anyway.
        guard status == 0 || status == 1 else {
            throw PaperSaverError.agentRestartFailed("killall exited \(status)\(output.isEmpty ? "" : ": \(output)")")
        }
    }

    public func waitForRespawn(timeout: Duration) async throws {
        let before = Self.runningProcessIdentifiers()
        let deadline = ContinuousClock.now + timeout
        while ContinuousClock.now < deadline {
            let now = Self.runningProcessIdentifiers()
            if !now.isEmpty, now.isDisjoint(with: before) { return }
            try await Task.sleep(for: .milliseconds(100))
        }
        throw PaperSaverError.agentRestartFailed("no new \(Self.processName) process within \(timeout)")
    }

    public func waitForExtension(bundleIdentifier: String, timeout: Duration) async -> Bool {
        let deadline = ContinuousClock.now + timeout
        while true {
            if Self.runningExtensionBundleIdentifiers().contains(bundleIdentifier) { return true }
            if ContinuousClock.now >= deadline { return false }
            try? await Task.sleep(for: .milliseconds(200))
        }
    }
}

/// An agent that does nothing, for tests and for callers that restart it themselves.
public struct NoopWallpaperAgent: WallpaperAgentControlling {
    public init() {}
    public func restart() async throws {}
    public func waitForRespawn(timeout: Duration) async throws {}
    public func waitForExtension(bundleIdentifier: String, timeout: Duration) async -> Bool { true }
}

/// How a store write is applied and checked.
public struct WriteOptions: Sendable, Equatable {
    /// Restart the agent so it reads the new store. Without it the change takes effect at the
    /// next login or the next restart of the agent.
    public var restartAgent = true
    /// After the restart, re-read the store and check the agent kept the change.
    public var verify = true
    /// On a failed verification, put the previous store back and restart the agent again.
    public var rollbackOnFailure = true
    /// How long to wait for a new agent process.
    public var respawnTimeout: Duration = .seconds(5)
    /// How long the store file must stay unchanged before it is read back.
    public var quietPeriod: Duration = .milliseconds(750)
    /// The most time spent waiting for the store to settle.
    public var settleTimeout: Duration = .seconds(4)
    /// After a desktop write that names a wallpaper extension, how long to wait for that
    /// extension's process. Measured on macOS 27.2: about one restart in three fails to connect
    /// the extension (ExtensionKit error 2 while the previous instance is torn down) and the
    /// agent does not retry; another restart recovers.
    public var extensionLaunchTimeout: Duration = .seconds(6)
    /// How many extra agent restarts to try when the extension's process does not appear.
    public var extensionRelaunchAttempts = 1

    public init() {}

    public static let `default` = WriteOptions()

    /// Write the file and stop.
    public static let noRestart: WriteOptions = {
        var options = WriteOptions()
        options.restartAgent = false
        options.verify = false
        return options
    }()
}

/// What a write achieved.
public enum WriteOutcome: Sendable, Equatable {
    /// The agent restarted and the store still holds the change.
    case applied
    /// The agent restarted; verification was off.
    case appliedUnverified
    /// The store holds the change, but the wallpaper extension it names had no running process
    /// after the restarts allowed by `WriteOptions.extensionRelaunchAttempts`.
    case appliedButExtensionNotRunning
    /// The file was written; the agent was not restarted.
    case writtenWithoutRestart
}

/// The one write path: read, edit, write, restart, settle, verify, roll back.
struct StoreWriter: Sendable {
    let file: StoreFile
    let agent: any WallpaperAgentControlling
    let log: PaperSaverLog

    func apply(
        expectation: String,
        options: WriteOptions,
        expectedExtension: String? = nil,
        edit: @Sendable (WallpaperStore) throws -> WallpaperStore,
        verify: @Sendable (WallpaperStore) -> Bool
    ) async throws -> WriteOutcome {
        let current = try file.read()
        let edited = try edit(current)
        let snapshot = try file.write(edited)
        log.info("wrote \(file.url.lastPathComponent) (\(expectation))")

        guard options.restartAgent else { return .writtenWithoutRestart }

        try await agent.restart()
        do {
            try await agent.waitForRespawn(timeout: options.respawnTimeout)
        } catch {
            log.warning("\(error.localizedDescription); continuing")
        }
        await settle(quietPeriod: options.quietPeriod, timeout: options.settleTimeout)

        guard options.verify else { return .appliedUnverified }

        let after = try file.read()
        if verify(after) {
            log.info("verified: \(expectation)")
            guard let expectedExtension else { return .applied }
            return await confirmExtensionLaunched(expectedExtension, options: options)
        }

        log.error("verification failed: \(expectation)")
        guard options.rollbackOnFailure else {
            throw PaperSaverError.verificationFailed(expected: expectation, rolledBack: false)
        }
        try file.restore(snapshot)
        try await agent.restart()
        throw PaperSaverError.verificationFailed(expected: expectation, rolledBack: true)
    }

    /// Waits for the extension's process, restarting the agent again when it does not appear.
    private func confirmExtensionLaunched(_ bundleIdentifier: String, options: WriteOptions) async -> WriteOutcome {
        var attempt = 0
        while true {
            if await agent.waitForExtension(bundleIdentifier: bundleIdentifier, timeout: options.extensionLaunchTimeout) {
                if attempt > 0 { log.info("\(bundleIdentifier) is running after \(attempt) extra restart(s)") }
                return .applied
            }
            guard attempt < options.extensionRelaunchAttempts else {
                log.error("\(bundleIdentifier) has no running process; the store is correct but the desktop may show the agent's fallback")
                return .appliedButExtensionNotRunning
            }
            attempt += 1
            log.warning("\(bundleIdentifier) did not launch within \(options.extensionLaunchTimeout); restarting \(WallpaperAgent.processName) again (\(attempt)/\(options.extensionRelaunchAttempts))")
            do {
                try await agent.restart()
                try await agent.waitForRespawn(timeout: options.respawnTimeout)
            } catch {
                log.warning("\(error.localizedDescription)")
            }
            await settle(quietPeriod: options.quietPeriod, timeout: options.settleTimeout)
        }
    }

    /// Waits until the store file has not changed for `quietPeriod`, or `timeout` passes.
    private func settle(quietPeriod: Duration, timeout: Duration) async {
        let deadline = ContinuousClock.now + timeout
        var last = file.modificationStamp()
        var stableSince = ContinuousClock.now
        while ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(100))
            let stamp = file.modificationStamp()
            if stamp != last {
                last = stamp
                stableSince = ContinuousClock.now
            } else if ContinuousClock.now - stableSince >= quietPeriod {
                return
            }
        }
    }
}
