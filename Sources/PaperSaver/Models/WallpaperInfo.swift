import Foundation

/// Information about a currently configured wallpaper.
///
/// This struct contains details about a wallpaper that is currently set
/// for a specific screen or space, including the image location, display
/// style, and scope of application.
public struct WallpaperInfo {
    /// The URL of the wallpaper image.
    ///
    /// The file system location of the wallpaper image. This can be:
    /// - A local file URL for user-selected images
    /// - A system URL for built-in wallpapers
    /// - A dynamic wallpaper collection URL for time-based wallpapers
    public let imageURL: URL

    /// The display style used for this wallpaper.
    ///
    /// Specifies how the wallpaper image is scaled and positioned on
    /// the display (fill, fit, stretch, center, tile, or dynamic).
    public let style: WallpaperStyle

    /// The specific screen this wallpaper is applied to.
    ///
    /// When `nil`, the wallpaper applies to all screens or the default
    /// screen. When populated, indicates this wallpaper is specific to
    /// a particular display identified by its Core Graphics display ID.
    public let screen: ScreenIdentifier?

    /// The UUID of the space this wallpaper is specific to.
    ///
    /// When `nil`, the wallpaper applies to all spaces on the target
    /// screen(s). When populated, indicates this wallpaper is only
    /// active when the specified space is visible.
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
    
    /// The file system path of the wallpaper image.
    ///
    /// Returns the path component of the image URL as a string.
    /// Useful for displaying the wallpaper location or performing
    /// file system operations.
    ///
    /// - Returns: The absolute file path to the wallpaper image.
    public var imagePath: String {
        imageURL.path
    }
    
    /// The filename of the wallpaper image.
    ///
    /// Returns just the filename and extension from the image URL,
    /// without the directory path. Useful for displaying a short
    /// name for the wallpaper in user interfaces.
    ///
    /// - Returns: The filename of the wallpaper image.
    public var imageName: String {
        imageURL.lastPathComponent
    }
}