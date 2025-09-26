import Foundation

public enum ScreensaverType: String, Codable, CaseIterable {
    case traditional = "saver"
    case quartz = "qtz"
    case appExtension = "appex"
    case sequoiaVideo = "video"
    case builtInMac = "macintosh"
    case defaultScreen = "default"
    
    public var fileExtension: String {
        switch self {
        case .traditional: return "saver"
        case .quartz: return "qtz"
        case .appExtension: return "appex"
        case .sequoiaVideo: return ""
        case .builtInMac, .defaultScreen: return ""
        }
    }
    
    public var providerIdentifier: String {
        switch self {
        case .traditional, .quartz:
            return "com.apple.wallpaper.choice.screen-saver"
        case .appExtension:
            return "com.apple.NeptuneOneExtension"
        case .sequoiaVideo:
            return "com.apple.wallpaper.choice.sequoia"
        case .builtInMac:
            return "com.apple.wallpaper.choice.macintosh"
        case .defaultScreen:
            return "default"
        }
    }
    
    public var displayName: String {
        switch self {
        case .traditional: return "Screen Saver"
        case .quartz: return "Quartz Composition"
        case .appExtension: return "App Extension"
        case .sequoiaVideo: return "Video Screensaver"
        case .builtInMac: return "Classic Mac"
        case .defaultScreen: return "Default"
        }
    }
}

public struct ScreensaverModule: Codable, Equatable {
    public let name: String
    public let identifier: String
    public let path: URL
    public let type: ScreensaverType
    public let isSystem: Bool
    public let thumbnail: URL?
    
    public init(
        name: String,
        identifier: String,
        path: URL,
        type: ScreensaverType,
        isSystem: Bool = false,
        thumbnail: URL? = nil
    ) {
        self.name = name
        self.identifier = identifier
        self.path = path
        self.type = type
        self.isSystem = isSystem
        self.thumbnail = thumbnail
    }
    
}