import Foundation

/// The display sleep delay for the current power source, as reported by `pmset -g`.
///
/// Read-only on purpose: changing it writes the system power-management preferences,
/// which needs root. Send users to System Settings › Lock Screen instead.
public enum DisplaySleep {

    /// Minutes of inactivity before the display turns off; 0 means never, `nil` means
    /// `pmset` failed or reported no display sleep setting.
    public static func minutes() async -> Int? {
        guard let output = await runPmset() else { return nil }
        return parse(pmsetOutput: output)
    }

    /// Reads the `displaysleep` line of `pmset -g`, such as
    /// ` displaysleep         30 (display sleep prevented by firefox)`.
    static func parse(pmsetOutput output: String) -> Int? {
        for line in output.split(whereSeparator: \.isNewline) {
            let tokens = line.split(whereSeparator: \.isWhitespace)
            guard tokens.count >= 2, tokens[0] == "displaysleep" else { continue }
            return Int(tokens[1])
        }
        return nil
    }

    private static func runPmset() async -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/pmset")
        process.arguments = ["-g"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        let status: Int32? = await withCheckedContinuation { continuation in
            process.terminationHandler = { continuation.resume(returning: $0.terminationStatus) }
            do {
                try process.run()
            } catch {
                process.terminationHandler = nil
                continuation.resume(returning: nil)
            }
        }
        guard status == 0 else { return nil }
        return String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
    }
}
