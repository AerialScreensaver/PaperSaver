import Foundation
import AppKit

public struct WallpaperOptions: Codable, Sendable {
    public enum ScalingMode: String, Codable, Sendable {
        case fill
        case fit
        case stretch
        case center
        case tile
        
        public var nsImageScaling: NSImageScaling {
            switch self {
            case .fill:
                return .scaleProportionallyUpOrDown
            case .fit:
                return .scaleProportionallyDown
            case .stretch:
                return .scaleAxesIndependently
            case .center:
                return .scaleNone
            case .tile:
                return .scaleNone
            }
        }
    }
    
    public let scaling: ScalingMode
    public let allowClipping: Bool
    public let backgroundColor: NSColor?
    public let imageAlignment: NSImageAlignment
    
    public init(
        scaling: ScalingMode = .fill,
        allowClipping: Bool = true,
        backgroundColor: NSColor? = nil,
        imageAlignment: NSImageAlignment = .alignCenter
    ) {
        self.scaling = scaling
        self.allowClipping = allowClipping
        self.backgroundColor = backgroundColor
        self.imageAlignment = imageAlignment
    }
    
    public static let `default` = WallpaperOptions()
    
    public static let fill = WallpaperOptions(scaling: .fill)
    public static let fit = WallpaperOptions(scaling: .fit, allowClipping: false)
    public static let center = WallpaperOptions(scaling: .center, allowClipping: false)
    public static let stretch = WallpaperOptions(scaling: .stretch)
    public static let tile = WallpaperOptions(scaling: .tile)
    
    private enum CodingKeys: String, CodingKey {
        case scaling
        case allowClipping
        case imageAlignment
    }
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        scaling = try container.decode(ScalingMode.self, forKey: .scaling)
        allowClipping = try container.decode(Bool.self, forKey: .allowClipping)
        imageAlignment = NSImageAlignment(rawValue: try container.decode(UInt.self, forKey: .imageAlignment)) ?? .alignCenter
        backgroundColor = nil
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(scaling, forKey: .scaling)
        try container.encode(allowClipping, forKey: .allowClipping)
        try container.encode(imageAlignment.rawValue, forKey: .imageAlignment)
    }
}