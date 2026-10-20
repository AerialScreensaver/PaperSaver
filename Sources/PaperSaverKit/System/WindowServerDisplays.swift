import Foundation
import CoreGraphics

/// A display as recorded in the window server's preferences, connected or not.
public struct WindowServerDisplayConfig: Sendable, Equatable {
    public let uuid: String
    public let resolution: CGSize
    public let refreshRate: Int
    public let scale: Int
    public let configVersion: Int
    public let isInCurrentConfig: Bool

    public init(uuid: String, resolution: CGSize, refreshRate: Int, scale: Int = 1, configVersion: Int = 0, isInCurrentConfig: Bool = false) {
        self.uuid = uuid
        self.resolution = resolution
        self.refreshRate = refreshRate
        self.scale = scale
        self.configVersion = configVersion
        self.isInCurrentConfig = isInCurrentConfig
    }
}

/// Reads `DisplaySets` from `com.apple.windowserver.displays`, which remembers every display
/// the Mac has used. The wallpaper store keys per-display sections by these UUIDs.
public enum WindowServerDisplays {
    public static func displays() -> [WindowServerDisplayConfig] {
        guard let sets = displaySets() else { return [] }
        return parse(sets)
    }

    /// Every display UUID the window server has recorded.
    public static func knownDisplayUUIDs() -> Set<String> {
        guard let underscan = displaySets()?["Underscan"] as? [String: Any] else { return [] }
        return Set(underscan.keys)
    }

    private static func displaySets() -> [String: Any]? {
        CFPreferencesCopyValue("DisplaySets" as CFString, "com.apple.windowserver.displays" as CFString,
                               kCFPreferencesCurrentUser, kCFPreferencesCurrentHost) as? [String: Any]
    }

    static func parse(_ sets: [String: Any]) -> [WindowServerDisplayConfig] {
        guard let configs = sets["Configs"] as? [[String: Any]] else { return [] }
        let current = configs.first { ($0["ConfigVersion"] as? Int) == 1 }
        let currentUUIDs = Set((current?["DisplayConfig"] as? [[String: Any]])?.compactMap { $0["UUID"] as? String } ?? [])

        var result: [WindowServerDisplayConfig] = []
        var seen = Set<String>()
        for config in configs {
            guard let displays = config["DisplayConfig"] as? [[String: Any]],
                  let version = config["ConfigVersion"] as? Int else { continue }
            for display in displays {
                guard let uuid = display["UUID"] as? String,
                      let info = display["CurrentInfo"] as? [String: Any],
                      let width = info["Wide"] as? Int, let height = info["High"] as? Int,
                      let hz = info["Hz"] as? Int, let scale = info["Scale"] as? Int,
                      !seen.contains(uuid) else { continue }
                result.append(WindowServerDisplayConfig(
                    uuid: uuid, resolution: CGSize(width: width, height: height), refreshRate: hz,
                    scale: scale, configVersion: version, isInCurrentConfig: currentUUIDs.contains(uuid)))
                if currentUUIDs.contains(uuid) { seen.insert(uuid) }
            }
        }
        return result.sorted {
            if $0.isInCurrentConfig != $1.isInCurrentConfig { return $0.isInCurrentConfig }
            return $0.uuid < $1.uuid
        }
    }
}
