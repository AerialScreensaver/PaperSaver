import Foundation

/// Represents a screensaver extension discovered via pluginkit
public struct PluginkitExtension: Codable, Equatable, Hashable {
    public let bundleIdentifier: String
    public let version: String
    public let uuid: String
    public let path: URL

    public var displayName: String {
        path.deletingPathExtension().lastPathComponent
    }

    public var isSystem: Bool {
        path.path.hasPrefix("/System/")
    }

    public init(bundleIdentifier: String, version: String, uuid: String, path: URL) {
        self.bundleIdentifier = bundleIdentifier
        self.version = version
        self.uuid = uuid
        self.path = path
    }
}

/// Manages interactions with the pluginkit CLI tool
public final class PluginkitManager: @unchecked Sendable {
    public static let shared = PluginkitManager()

    private init() {}

    /// Discovers all registered screensaver extensions via pluginkit
    /// - Returns: Array of discovered extensions
    public func discoverScreensaverExtensions() throws -> [PluginkitExtension] {
        let output = try runPluginkit(arguments: ["-m", "-v", "-p", "com.apple.screensaver"])
        return parsePluginkitOutput(output)
    }

    /// Registers an appex extension with the system
    /// - Parameter path: Path to the .appex bundle
    public func registerExtension(at path: URL) throws {
        _ = try runPluginkit(arguments: ["-a", path.path])
    }

    /// Unregisters an appex extension from the system
    /// - Parameter path: Path to the .appex bundle
    public func unregisterExtension(at path: URL) throws {
        _ = try runPluginkit(arguments: ["-r", path.path])
    }

    /// Check if a bundle identifier is registered
    /// - Parameter bundleIdentifier: The bundle ID to check
    /// - Returns: True if the extension is registered
    public func isExtensionRegistered(bundleIdentifier: String) throws -> Bool {
        let extensions = try discoverScreensaverExtensions()
        return extensions.contains { $0.bundleIdentifier == bundleIdentifier }
    }

    /// Find an extension by its display name
    /// - Parameter name: The display name to search for
    /// - Returns: The matching extension, if found
    public func findExtension(byName name: String) throws -> PluginkitExtension? {
        let extensions = try discoverScreensaverExtensions()
        return extensions.first { $0.displayName == name }
    }

    /// Find an extension by its bundle identifier
    /// - Parameter bundleIdentifier: The bundle ID to search for
    /// - Returns: The matching extension, if found
    public func findExtension(byBundleIdentifier bundleIdentifier: String) throws -> PluginkitExtension? {
        let extensions = try discoverScreensaverExtensions()
        return extensions.first { $0.bundleIdentifier == bundleIdentifier }
    }

    // MARK: - Private

    private func runPluginkit(arguments: [String]) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/pluginkit")
        process.arguments = arguments

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        try process.run()
        process.waitUntilExit()

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: data, encoding: .utf8) ?? ""

        // pluginkit returns non-zero when no matches found, which is not an error
        // Only throw for actual execution failures
        if process.terminationStatus != 0 && !output.isEmpty && output.contains("error") {
            throw PluginkitError.commandFailed(output)
        }

        return output
    }

    /// Parse pluginkit -m -v -p com.apple.screensaver output
    /// Fields are tab-separated: "bundleID(version)\tUUID\ttimestamp\tpath"
    private func parsePluginkitOutput(_ output: String) -> [PluginkitExtension] {
        var extensions: [PluginkitExtension] = []

        let lines = output.components(separatedBy: "\n")
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { continue }

            // Parse bundle identifier and version
            // Format: "com.apple.screensaver.flurry(1.0)"
            guard let parenOpen = trimmed.firstIndex(of: "("),
                  let parenClose = trimmed.firstIndex(of: ")") else {
                continue
            }

            let bundleIdentifier = String(trimmed[..<parenOpen])
            let version = String(trimmed[trimmed.index(after: parenOpen)..<parenClose])

            // After the closing paren, fields are tab-separated: UUID, timestamp, path
            // Paths may contain spaces (e.g. "Aerial Companion.app"), so we must
            // split by tab only — not by whitespace.
            let remainder = String(trimmed[trimmed.index(after: parenClose)...])
            let tabComponents = remainder.components(separatedBy: "\t")
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }

            // Expect at least 3 fields: UUID, timestamp, path
            guard tabComponents.count >= 3 else { continue }

            let uuid = tabComponents[0]
            let path = tabComponents.last!

            guard path.hasPrefix("/") else { continue }

            let ext = PluginkitExtension(
                bundleIdentifier: bundleIdentifier,
                version: version,
                uuid: uuid,
                path: URL(fileURLWithPath: path)
            )
            extensions.append(ext)
        }

        return extensions
    }
}

public enum PluginkitError: LocalizedError {
    case commandFailed(String)
    case extensionNotFound(String)

    public var errorDescription: String? {
        switch self {
        case .commandFailed(let output):
            return "pluginkit command failed: \(output)"
        case .extensionNotFound(let name):
            return "Extension not found: \(name)"
        }
    }
}
