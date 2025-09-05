import Foundation

public struct WallpaperOptions: Sendable {
    public let style: WallpaperStyle
    
    public init(style: WallpaperStyle = .fill) {
        self.style = style
    }
    
    public static let `default` = WallpaperOptions()
    public static let fill = WallpaperOptions(style: .fill)
    public static let fit = WallpaperOptions(style: .fit)
    public static let stretch = WallpaperOptions(style: .stretch)
    public static let center = WallpaperOptions(style: .center)
    public static let tile = WallpaperOptions(style: .tile)
    public static let dynamic = WallpaperOptions(style: .dynamic)
}