import Foundation

public struct MissionControlSpace {
    public let spaceID: Int
    public let uuid: String
    public let displayIdentifier: String
    public let isCurrent: Bool
    public let isCollapsed: Bool
    public let isAutoCreated: Bool
    
    public init(
        spaceID: Int,
        uuid: String,
        displayIdentifier: String,
        isCurrent: Bool = false,
        isCollapsed: Bool = false,
        isAutoCreated: Bool = false
    ) {
        self.spaceID = spaceID
        self.uuid = uuid
        self.displayIdentifier = displayIdentifier
        self.isCurrent = isCurrent
        self.isCollapsed = isCollapsed
        self.isAutoCreated = isAutoCreated
    }
    
    public var isHistorical: Bool {
        return isCollapsed || isAutoCreated
    }
    
    public var displayName: String {
        switch displayIdentifier {
        case "Main":
            return "Main Display"
        default:
            if displayIdentifier.contains("-") {
                return "Display \(displayIdentifier.prefix(8))..."
            }
            return displayIdentifier
        }
    }
}

@available(macOS 14.0, *)
public final class SpacesManager: @unchecked Sendable {
    public static let shared = SpacesManager()
    
    private init() {}
    
    public func getMissionControlSpaces() -> [MissionControlSpace] {
        guard let spacesData = readSpacesPreferences() else {
            return []
        }
        
        return parseSpacesConfiguration(spacesData)
    }
    
    public func getCurrentSpaces() -> [MissionControlSpace] {
        return getMissionControlSpaces().filter { $0.isCurrent }
    }
    
    public func getActiveSpaces() -> [MissionControlSpace] {
        return getMissionControlSpaces().filter { !$0.isHistorical }
    }
    
    public func getSpaceByID(_ spaceID: Int) -> MissionControlSpace? {
        return getMissionControlSpaces().first { $0.spaceID == spaceID }
    }
    
    public func getSpaceByUUID(_ uuid: String) -> MissionControlSpace? {
        return getMissionControlSpaces().first { $0.uuid == uuid }
    }
    
    public func getCurrentSpaceForDisplay(_ displayIdentifier: String) -> MissionControlSpace? {
        return getCurrentSpaces().first { $0.displayIdentifier == displayIdentifier }
    }
    
    public func getSpacesForDisplay(_ displayIdentifier: String, includeHistorical: Bool = false) -> [MissionControlSpace] {
        let spaces = getMissionControlSpaces().filter { $0.displayIdentifier == displayIdentifier }
        return includeHistorical ? spaces : spaces.filter { !$0.isHistorical }
    }
    
    public func getDisplayIdentifiers() -> [String] {
        let spaces = getMissionControlSpaces()
        return Array(Set(spaces.map { $0.displayIdentifier })).sorted { first, second in
            if first == "Main" { return true }
            if second == "Main" { return false }
            return first < second
        }
    }
    
    private func readSpacesPreferences() -> [String: Any]? {
        let defaults = UserDefaults(suiteName: "com.apple.spaces")
        return defaults?.dictionary(forKey: "SpacesDisplayConfiguration")
    }
    
    private func parseSpacesConfiguration(_ config: [String: Any]) -> [MissionControlSpace] {
        guard let managementData = config["Management Data"] as? [String: Any],
              let monitors = managementData["Monitors"] as? [[String: Any]] else {
            return []
        }
        
        var spaces: [MissionControlSpace] = []
        
        for monitor in monitors {
            let displayIdentifier = monitor["Display Identifier"] as? String ?? "Unknown"
            
            // Get current space for this monitor
            var currentSpaceUUID: String?
            if let currentSpace = monitor["Current Space"] as? [String: Any],
               let uuid = currentSpace["uuid"] as? String {
                currentSpaceUUID = uuid
            }
            
            // Parse regular spaces
            if let monitorSpaces = monitor["Spaces"] as? [[String: Any]] {
                for spaceData in monitorSpaces {
                    let spaceID = spaceData["ManagedSpaceID"] as? Int ?? 0
                    let uuid = spaceData["uuid"] as? String ?? ""
                    let isCurrent = uuid == currentSpaceUUID
                    
                    let space = MissionControlSpace(
                        spaceID: spaceID,
                        uuid: uuid,
                        displayIdentifier: displayIdentifier,
                        isCurrent: isCurrent,
                        isCollapsed: false,
                        isAutoCreated: false
                    )
                    spaces.append(space)
                }
            }
            
            // Parse collapsed spaces
            if let collapsedSpace = monitor["Collapsed Space"] as? [String: Any] {
                let spaceID = collapsedSpace["ManagedSpaceID"] as? Int ?? 0
                let uuid = collapsedSpace["uuid"] as? String ?? ""
                let isAutoCreated = collapsedSpace["AutoCreated"] as? Int == 1
                
                let space = MissionControlSpace(
                    spaceID: spaceID,
                    uuid: uuid,
                    displayIdentifier: displayIdentifier,
                    isCurrent: false,
                    isCollapsed: true,
                    isAutoCreated: isAutoCreated
                )
                spaces.append(space)
            }
        }
        
        return spaces.sorted { $0.spaceID < $1.spaceID }
    }
}