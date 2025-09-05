import Foundation

public struct WallpaperInfo {
    public let imageURL: URL
    public let style: WallpaperStyle
    public let screen: ScreenIdentifier?
    public let spaceUUID: String?
    
    public init(
        imageURL: URL,
        style: WallpaperStyle = .fill,
        screen: ScreenIdentifier? = nil,
        spaceUUID: String? = nil
    ) {
        self.imageURL = imageURL
        self.style = style
        self.screen = screen
        self.spaceUUID = spaceUUID
    }
    
    public var imagePath: String {
        imageURL.path
    }
    
    public var imageName: String {
        imageURL.lastPathComponent
    }
}