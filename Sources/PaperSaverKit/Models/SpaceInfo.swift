import Foundation
import CoreGraphics

/// Information about a macOS space (virtual desktop).
///
/// This struct represents a space in macOS Mission Control, containing
/// details about its identity, associated displays, and current status.
/// Spaces allow users to organize windows and applications across multiple
/// virtual desktops.
public struct SpaceInfo: Codable, Equatable {
    /// The unique identifier for this space.
    ///
    /// A UUID string that uniquely identifies this space across the system.
    /// This identifier remains stable for the lifetime of the space but
    /// changes if the space is destroyed and recreated.
    public let uuid: String

    /// The UUIDs of displays associated with this space.
    ///
    /// An array of display UUID strings indicating which physical monitors
    /// this space appears on. In most cases, a space spans all connected
    /// displays, but some configurations may have space-specific display
    /// associations.
    public let displayUUIDs: [String]

    /// The user-assigned name of the space.
    ///
    /// The custom name given to this space in Mission Control, if any.
    /// This is `nil` for spaces that haven't been explicitly named by
    /// the user (most spaces have no custom name).
    public let name: String?

    /// The numeric identifier for this space.
    ///
    /// An integer ID assigned by Mission Control to identify this space.
    /// This is `nil` for spaces that don't have a numeric ID in the
    /// current system configuration. Space IDs may change when spaces
    /// are reordered or recreated.
    public let spaceID: Int?

    /// Legacy display identifier string.
    ///
    /// An older format display identifier that may be present in some
    /// space configurations. This is `nil` in most modern configurations
    /// where `displayUUIDs` is used instead.
    public let displayIdentifier: String?

    /// Whether this space is currently active and visible.
    ///
    /// `true` if this space is currently being displayed to the user,
    /// `false` if it's hidden behind other spaces. Only one space per
    /// display can be current at any given time.
    public let isCurrent: Bool

    /// Whether this space represents a historical configuration.
    ///
    /// `true` for spaces that existed in the past but are no longer
    /// active in the current system state. Historical spaces may be
    /// present in configuration files but don't correspond to actual
    /// usable spaces.
    public let isHistorical: Bool
    
    public init(
        uuid: String,
        displayUUIDs: [String] = [],
        name: String? = nil,
        spaceID: Int? = nil,
        displayIdentifier: String? = nil,
        isCurrent: Bool = false,
        isHistorical: Bool = false
    ) {
        self.uuid = uuid
        self.displayUUIDs = displayUUIDs
        self.name = name
        self.spaceID = spaceID
        self.displayIdentifier = displayIdentifier
        self.isCurrent = isCurrent
        self.isHistorical = isHistorical
    }
    
    /// The number of displays associated with this space.
    ///
    /// Returns the count of displays that this space appears on.
    /// Most spaces span all connected displays, so this typically
    /// matches the total number of connected monitors.
    ///
    /// - Returns: The number of associated displays.
    public var displayCount: Int {
        return displayUUIDs.count
    }
    
    
    /// Checks if this space is associated with a specific display.
    ///
    /// Determines whether this space appears on the display identified
    /// by the given UUID. Useful for filtering spaces by display in
    /// multi-monitor setups.
    ///
    /// - Parameter displayUUID: The UUID of the display to check.
    /// - Returns: `true` if this space appears on the specified display.
    public func contains(displayUUID: String) -> Bool {
        return displayUUIDs.contains(displayUUID)
    }
}

/// Information about a display (monitor) in the system.
///
/// This struct contains comprehensive information about a physical display,
/// including both currently connected displays and historical display
/// configurations that macOS remembers for future reconnection.
public struct DisplayInfo: Equatable {
    /// The unique identifier for this display.
    ///
    /// A UUID string that uniquely identifies this display across
    /// disconnection/reconnection cycles. macOS uses this to remember
    /// per-display settings like wallpaper and arrangement.
    public let uuid: String

    /// The Core Graphics display ID for this display.
    ///
    /// The system-assigned numeric identifier for this display when connected.
    /// This is `nil` for historical displays that are not currently connected
    /// to the system.
    public let displayID: CGDirectDisplayID?

    /// The screen rectangle for this display in the global coordinate space.
    ///
    /// The display's position and size in the virtual desktop coordinate
    /// system used by macOS. This is `nil` for displays that are not
    /// currently connected or lack geometry information.
    public let frame: CGRect?

    /// Whether this is the main display.
    ///
    /// `true` if this display contains the menu bar and is considered the
    /// primary display by macOS. Only one connected display can be the
    /// main display at any time.
    public let isMain: Bool

    /// Whether this display is currently connected.
    ///
    /// `true` for displays that are currently connected and active,
    /// `false` for historical display configurations that macOS remembers
    /// but are not currently available.
    public let isConnected: Bool

    /// The native resolution of this display.
    ///
    /// The display's native pixel dimensions. This is `nil` for displays
    /// where resolution information is not available or for historical
    /// configurations.
    public let resolution: CGSize?

    /// The refresh rate of this display in Hz.
    ///
    /// The display's refresh rate (e.g., 60, 120, 144). This is `nil`
    /// for displays where refresh rate information is not available.
    public let refreshRate: Int?

    /// The scaling factor for this display.
    ///
    /// The HiDPI/Retina scaling factor (1 for standard resolution,
    /// 2 for 2x Retina, etc.). This is `nil` for displays where
    /// scaling information is not available.
    public let scale: Int?

    /// The configuration version when this display was last seen.
    ///
    /// A version number indicating when this display configuration was
    /// recorded. Higher numbers indicate more recent configurations.
    /// This is `nil` for currently connected displays.
    public let configVersion: Int?

    /// The human-readable name of this display.
    ///
    /// The manufacturer-provided display name (e.g., "Studio Display",
    /// "ROG PG278Q"). This is `nil` for displays where the name cannot
    /// be determined or for generic/historical configurations.
    public let displayName: String?
    
    public init(
        uuid: String,
        displayID: CGDirectDisplayID? = nil,
        frame: CGRect? = nil,
        isMain: Bool = false,
        isConnected: Bool = false,
        resolution: CGSize? = nil,
        refreshRate: Int? = nil,
        scale: Int? = nil,
        configVersion: Int? = nil,
        displayName: String? = nil
    ) {
        self.uuid = uuid
        self.displayID = displayID
        self.frame = frame
        self.isMain = isMain
        self.isConnected = isConnected
        self.resolution = resolution
        self.refreshRate = refreshRate
        self.scale = scale
        self.configVersion = configVersion
        self.displayName = displayName
    }
    
    /// A shortened version of the display UUID for display purposes.
    ///
    /// Returns the first 8 characters of the UUID followed by "..."
    /// for use in user interfaces where the full UUID would be too long.
    ///
    /// - Returns: Truncated UUID string suitable for UI display.
    public var shortUUID: String {
        return String(uuid.prefix(8)) + "..."
    }
    
    /// A formatted string describing the display's technical specifications.
    ///
    /// Returns a human-readable description of the display's resolution,
    /// refresh rate, and scaling factor. Falls back to frame size or
    /// "Unknown resolution" if detailed information is unavailable.
    ///
    /// - Returns: Formatted specification string (e.g., "3008x1692 @ 60Hz @ 2x").
    public var displayDescription: String {
        if let resolution = resolution {
            let scaleText = (scale ?? 1) > 1 ? " @ \(scale!)x" : ""
            let refreshText = refreshRate.map { " @ \($0)Hz" } ?? ""
            return "\(Int(resolution.width))x\(Int(resolution.height))\(refreshText)\(scaleText)"
        } else if let frame = frame {
            return "\(Int(frame.width))x\(Int(frame.height))"
        } else {
            return "Unknown resolution"
        }
    }
    
    /// A user-friendly name for this display.
    ///
    /// Returns the most appropriate display name based on available information.
    /// Prefers the manufacturer display name when available, falls back to
    /// generic names with UUID fragments, and includes status indicators
    /// for main displays and historical configurations.
    ///
    /// - Returns: Human-readable display name suitable for user interfaces.
    public var friendlyName: String {
        if let name = displayName {
            // Use the actual display name when available
            if isMain && isConnected {
                return "\(name) (Main)"
            } else {
                return name
            }
        } else if isMain && isConnected {
            return "Main Display \(shortUUID)"
        } else if isConnected {
            return "Display \(shortUUID)"
        } else {
            let configText = configVersion.map { " (last seen: Config \($0))" } ?? ""
            return "Display \(shortUUID)\(configText)"
        }
    }
    
}

extension DisplayInfo: Codable {
    private enum CodingKeys: String, CodingKey {
        case uuid
        case displayID
        case frame
        case isMain
        case isConnected
        case resolution
        case refreshRate
        case scale
        case configVersion
        case displayName
    }
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        uuid = try container.decode(String.self, forKey: .uuid)
        displayID = try container.decodeIfPresent(UInt32.self, forKey: .displayID)
        frame = try container.decodeIfPresent(CGRect.self, forKey: .frame)
        isMain = try container.decode(Bool.self, forKey: .isMain)
        isConnected = try container.decode(Bool.self, forKey: .isConnected)
        resolution = try container.decodeIfPresent(CGSize.self, forKey: .resolution)
        refreshRate = try container.decodeIfPresent(Int.self, forKey: .refreshRate)
        scale = try container.decodeIfPresent(Int.self, forKey: .scale)
        configVersion = try container.decodeIfPresent(Int.self, forKey: .configVersion)
        displayName = try container.decodeIfPresent(String.self, forKey: .displayName)
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(uuid, forKey: .uuid)
        try container.encodeIfPresent(displayID, forKey: .displayID)
        try container.encodeIfPresent(frame, forKey: .frame)
        try container.encode(isMain, forKey: .isMain)
        try container.encode(isConnected, forKey: .isConnected)
        try container.encodeIfPresent(resolution, forKey: .resolution)
        try container.encodeIfPresent(refreshRate, forKey: .refreshRate)
        try container.encodeIfPresent(scale, forKey: .scale)
        try container.encodeIfPresent(configVersion, forKey: .configVersion)
        try container.encodeIfPresent(displayName, forKey: .displayName)
    }
}

