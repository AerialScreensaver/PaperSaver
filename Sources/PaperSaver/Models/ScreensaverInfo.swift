import Foundation
import AppKit

public struct ScreensaverInfo: Codable, Equatable {
    public let name: String
    public let identifier: String
    public let modulePath: String?
    public let screen: ScreenIdentifier?
    public let configuration: [String: Any]?
    
    public init(
        name: String,
        identifier: String,
        modulePath: String? = nil,
        screen: ScreenIdentifier? = nil,
        configuration: [String: Any]? = nil
    ) {
        self.name = name
        self.identifier = identifier
        self.modulePath = modulePath
        self.screen = screen
        self.configuration = configuration
    }
    
    private enum CodingKeys: String, CodingKey {
        case name
        case identifier
        case modulePath
        case screen
    }
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decode(String.self, forKey: .name)
        identifier = try container.decode(String.self, forKey: .identifier)
        modulePath = try container.decodeIfPresent(String.self, forKey: .modulePath)
        screen = try container.decodeIfPresent(ScreenIdentifier.self, forKey: .screen)
        configuration = nil
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(name, forKey: .name)
        try container.encode(identifier, forKey: .identifier)
        try container.encodeIfPresent(modulePath, forKey: .modulePath)
        try container.encodeIfPresent(screen, forKey: .screen)
    }
    
    public static func == (lhs: ScreensaverInfo, rhs: ScreensaverInfo) -> Bool {
        return lhs.name == rhs.name &&
               lhs.identifier == rhs.identifier &&
               lhs.modulePath == rhs.modulePath &&
               lhs.screen == rhs.screen
    }
}

public struct ScreenIdentifier: Codable, Equatable {
    public let displayID: CGDirectDisplayID
    public let spaceID: Int?
    
    public init(displayID: CGDirectDisplayID, spaceID: Int? = nil) {
        self.displayID = displayID
        self.spaceID = spaceID
    }
    
    public init?(from screen: NSScreen) {
        guard let displayID = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID else {
            return nil
        }
        self.displayID = displayID
        self.spaceID = nil
    }
}