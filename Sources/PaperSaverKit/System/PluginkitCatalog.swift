import Foundation

/// An app extension pluginkit knows about.
public struct PluginkitExtension: Codable, Equatable, Hashable, Sendable {
    public let bundleIdentifier: String
    public let version: String
    public let uuid: String
    public let path: URL
    /// The status pluginkit prints before the entry: `+` elected, `-` superseded, `!` disabled,
    /// `?` unknown, or none.
    public let status: String?

    /// The bundle's file name without extension, which is the name System Settings lists the
    /// screensaver under when it has no display name.
    public var displayName: String {
        path.deletingPathExtension().lastPathComponent
    }

    public var isSystem: Bool {
        path.path.hasPrefix("/System/")
    }

    public init(bundleIdentifier: String, version: String, uuid: String, path: URL, status: String? = nil) {
        self.bundleIdentifier = bundleIdentifier
        self.version = version
        self.uuid = uuid
        self.path = path
        self.status = status
    }
}

/// Parses `pluginkit -m -v` output.
///
/// Each line is `[status] bundleID(version)<tab>UUID<tab>timestamp<tab>path`. Paths may
/// contain spaces, so fields are split on tabs only.
public enum PluginkitOutputParser {
    public static func parse(_ output: String) -> [PluginkitExtension] {
        var extensions: [PluginkitExtension] = []
        for rawLine in output.components(separatedBy: .newlines) {
            var line = Substring(rawLine.trimmingCharacters(in: .whitespaces))
            guard !line.isEmpty else { continue }
            var status: String?
            if let first = line.first, "+-!?".contains(first) {
                status = String(first)
                line = line.dropFirst().drop { $0 == " " }
            }
            // The head is `bundleID(version)`; Apple's wallpaper extensions print `((null))`.
            let head = line.prefix { $0 != "\t" }
            guard let open = head.firstIndex(of: "("), let close = head.lastIndex(of: ")"), open < close else { continue }
            let bundleIdentifier = String(head[..<open])
            var version = String(head[head.index(after: open)..<close])
            if version == "(null)" { version = "" }
            let fields = line[line.index(after: close)...]
                .components(separatedBy: "\t")
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
            guard fields.count >= 3, let path = fields.last, path.hasPrefix("/") else { continue }
            extensions.append(PluginkitExtension(
                bundleIdentifier: bundleIdentifier, version: version, uuid: fields[0],
                path: URL(fileURLWithPath: path), status: status))
        }
        return extensions
    }
}

/// The screensaver extensions registered with pluginkit, cached for a short time because
/// listing them runs a subprocess.
public actor PluginkitCatalog {
    public static let screensaverExtensionPoint = "com.apple.screensaver"
    public static let wallpaperExtensionPoint = "com.apple.wallpaper"

    private let ttl: Duration
    private let extensionPoint: String
    private var cached: (extensions: [PluginkitExtension], at: ContinuousClock.Instant)?

    public init(extensionPoint: String = PluginkitCatalog.screensaverExtensionPoint, ttl: Duration = .seconds(5)) {
        self.extensionPoint = extensionPoint
        self.ttl = ttl
    }

    /// Every registered extension for the extension point.
    public func extensions() async throws -> [PluginkitExtension] {
        if let cached, ContinuousClock.now - cached.at < ttl { return cached.extensions }
        let output = try await Self.run(arguments: ["-m", "-v", "-p", extensionPoint])
        let extensions = PluginkitOutputParser.parse(output)
        cached = (extensions, ContinuousClock.now)
        return extensions
    }

    public func invalidate() {
        cached = nil
    }

    public func find(byName name: String) async throws -> PluginkitExtension? {
        try await extensions().first { $0.displayName == name }
    }

    public func find(byBundleIdentifier bundleIdentifier: String) async throws -> PluginkitExtension? {
        try await extensions().first { $0.bundleIdentifier == bundleIdentifier }
    }

    public func isRegistered(bundleIdentifier: String) async throws -> Bool {
        try await find(byBundleIdentifier: bundleIdentifier) != nil
    }

    /// `pluginkit -a`: registers the bundle at `url`.
    public func register(at url: URL) async throws {
        _ = try await Self.run(arguments: ["-a", url.path])
        invalidate()
    }

    /// `pluginkit -r`: removes the registration of the bundle at `url`.
    public func unregister(at url: URL) async throws {
        _ = try await Self.run(arguments: ["-r", url.path])
        invalidate()
    }

    /// Runs `/usr/bin/pluginkit`. A non-zero exit with no output is how pluginkit reports
    /// "no match" and is not an error.
    static func run(arguments: [String]) async throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/pluginkit")
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        let status: Int32 = try await withCheckedThrowingContinuation { continuation in
            process.terminationHandler = { continuation.resume(returning: $0.terminationStatus) }
            do {
                try process.run()
            } catch {
                process.terminationHandler = nil
                continuation.resume(throwing: PaperSaverError.pluginkitFailed(error.localizedDescription))
            }
        }
        let output = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        if status != 0, output.localizedCaseInsensitiveContains("error") {
            throw PaperSaverError.pluginkitFailed(output.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        return output
    }
}
