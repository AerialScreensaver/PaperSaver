import Foundation

/// A Space as recorded in the `com.apple.spaces` preferences.
public struct MissionControlSpace: Sendable, Equatable {
    public let spaceID: Int
    public let uuid: String
    public let displayIdentifier: String
    public let isCurrent: Bool
    public let isCollapsed: Bool
    public let isAutoCreated: Bool

    public init(spaceID: Int, uuid: String, displayIdentifier: String, isCurrent: Bool = false, isCollapsed: Bool = false, isAutoCreated: Bool = false) {
        self.spaceID = spaceID
        self.uuid = uuid
        self.displayIdentifier = displayIdentifier
        self.isCurrent = isCurrent
        self.isCollapsed = isCollapsed
        self.isAutoCreated = isAutoCreated
    }

    /// Collapsed and auto-created Spaces belong to displays that are no longer connected.
    public var isHistorical: Bool { isCollapsed || isAutoCreated }
}

/// Reads `SpacesDisplayConfiguration` from the `com.apple.spaces` preferences, which also
/// records Spaces of displays that are not connected right now.
public enum MissionControlSpaces {
    public static func spaces() -> [MissionControlSpace] {
        guard let configuration = UserDefaults(suiteName: "com.apple.spaces")?.dictionary(forKey: "SpacesDisplayConfiguration") else {
            return []
        }
        return parse(configuration)
    }

    public static func space(withID spaceID: Int) -> MissionControlSpace? {
        spaces().first { $0.spaceID == spaceID }
    }

    static func parse(_ configuration: [String: Any]) -> [MissionControlSpace] {
        guard let management = configuration["Management Data"] as? [String: Any],
              let monitors = management["Monitors"] as? [[String: Any]] else {
            return []
        }
        var spaces: [MissionControlSpace] = []
        for monitor in monitors {
            let displayIdentifier = monitor["Display Identifier"] as? String ?? "Unknown"
            let currentUUID = (monitor["Current Space"] as? [String: Any])?["uuid"] as? String
            for space in monitor["Spaces"] as? [[String: Any]] ?? [] {
                let uuid = space["uuid"] as? String ?? ""
                spaces.append(MissionControlSpace(
                    spaceID: space["ManagedSpaceID"] as? Int ?? 0, uuid: uuid,
                    displayIdentifier: displayIdentifier, isCurrent: uuid == currentUUID))
            }
            if let collapsed = monitor["Collapsed Space"] as? [String: Any] {
                spaces.append(MissionControlSpace(
                    spaceID: collapsed["ManagedSpaceID"] as? Int ?? 0, uuid: collapsed["uuid"] as? String ?? "",
                    displayIdentifier: displayIdentifier, isCollapsed: true,
                    isAutoCreated: collapsed["AutoCreated"] as? Int == 1))
            }
        }
        return spaces.sorted { $0.spaceID < $1.spaceID }
    }
}
