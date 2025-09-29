import Foundation

/// Configuration options for wallpaper display.
///
/// This struct encapsulates the display settings for a wallpaper,
/// including how the image should be scaled and positioned on the screen.
/// Provides convenient static properties for common configurations.
public struct WallpaperOptions: Sendable {
    /// The display style to use for the wallpaper.
    ///
    /// Specifies how the wallpaper image should be scaled, positioned,
    /// and displayed on the screen (fill, fit, stretch, center, tile, or dynamic).
    public let style: WallpaperStyle

    /// Creates wallpaper options with the specified style.
    ///
    /// - Parameter style: The wallpaper display style to use.
    ///   Defaults to `.fill` which scales the image to fill the screen.
    public init(style: WallpaperStyle = .fill) {
        self.style = style
    }
    
    /// Default wallpaper options using fill style.
    ///
    /// The most commonly used wallpaper configuration that scales
    /// the image to fill the entire screen, cropping if necessary.
    public static let `default` = WallpaperOptions()

    /// Wallpaper options for fill style.
    ///
    /// Scales the image to completely fill the screen while maintaining
    /// aspect ratio. Parts of the image may be cropped.
    public static let fill = WallpaperOptions(style: .fill)

    /// Wallpaper options for fit style.
    ///
    /// Scales the image to fit entirely within the screen boundaries.
    /// Black bars may appear if aspect ratios don't match.
    public static let fit = WallpaperOptions(style: .fit)

    /// Wallpaper options for stretch style.
    ///
    /// Stretches the image to exactly match screen dimensions,
    /// potentially distorting the aspect ratio.
    public static let stretch = WallpaperOptions(style: .stretch)

    /// Wallpaper options for center style.
    ///
    /// Displays the image at its natural size, centered on the screen
    /// without scaling.
    public static let center = WallpaperOptions(style: .center)

    /// Wallpaper options for tile style.
    ///
    /// Repeats the image in a grid pattern to fill the screen.
    /// Useful for seamless textures and patterns.
    public static let tile = WallpaperOptions(style: .tile)

    /// Wallpaper options for dynamic style.
    ///
    /// Enables dynamic wallpaper features that change based on
    /// time of day or system appearance.
    public static let dynamic = WallpaperOptions(style: .dynamic)
}