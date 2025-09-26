import Foundation
import CoreGraphics

public struct SpaceInfo: Codable, Equatable {
    public let uuid: String
    public let displayUUIDs: [String]
    public let name: String?
    public let spaceID: Int?
    public let displayIdentifier: String?
    public let isCurrent: Bool
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
    
    public var displayCount: Int {
        return displayUUIDs.count
    }
    
    
    public func contains(displayUUID: String) -> Bool {
        return displayUUIDs.contains(displayUUID)
    }
}

public struct DisplayInfo: Equatable {
    public let uuid: String
    public let displayID: CGDirectDisplayID?
    public let frame: CGRect?
    public let isMain: Bool
    public let isConnected: Bool
    public let resolution: CGSize?
    public let refreshRate: Int?
    public let scale: Int?
    public let configVersion: Int?
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
    
    public var shortUUID: String {
        return String(uuid.prefix(8)) + "..."
    }
    
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

