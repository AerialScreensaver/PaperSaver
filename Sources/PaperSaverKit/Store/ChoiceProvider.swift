import Foundation

/// The `Provider` of a wallpaper-store choice: the identifier of the component that renders it.
///
/// Apple's own choices use `com.apple.wallpaper.*` identifiers. A third-party wallpaper
/// extension is identified by its bundle identifier.
public struct ChoiceProvider: RawRepresentable, Hashable, Sendable, Codable, CustomStringConvertible {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    /// A single image file (`{type: imageFile, url: {relative: …}}`).
    public static let image = ChoiceProvider(rawValue: "com.apple.wallpaper.choice.image")
    /// A `.saver` plug-in or an app-extension screensaver (`{module: {relative: …}}`).
    public static let screenSaver = ChoiceProvider(rawValue: "com.apple.wallpaper.choice.screen-saver")
    /// A Photos library collection (`{type: collection, identifier: …}`).
    public static let photos = ChoiceProvider(rawValue: "com.apple.wallpaper.extension.photos")
    /// Apple's aerial videos (`{assetID: …}`).
    public static let aerials = ChoiceProvider(rawValue: "com.apple.wallpaper.choice.aerials")
    /// The classic Macintosh screensavers.
    public static let macintosh = ChoiceProvider(rawValue: "com.apple.wallpaper.choice.macintosh")
    /// The default wallpaper of macOS 26 and later. Its configuration is empty.
    public static let neptuneOne = ChoiceProvider(rawValue: "com.apple.NeptuneOneExtension")
    /// The placeholder WallpaperAgent records in a `Linked` slot when nothing is set.
    public static let placeholder = ChoiceProvider(rawValue: "default")

    /// `true` for the agent's "nothing set" placeholder.
    public var isPlaceholder: Bool { self == .placeholder }

    /// `true` for choices Apple ships (`com.apple.*`).
    public var isAppleProvided: Bool { rawValue.hasPrefix("com.apple.") }

    /// `true` for a third-party wallpaper extension, identified by its bundle identifier.
    public var isThirdPartyExtension: Bool { !isPlaceholder && !isAppleProvided }

    public var description: String { rawValue }
}
