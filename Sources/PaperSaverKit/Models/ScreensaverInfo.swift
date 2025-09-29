import Foundation
import AppKit

/// Information about a currently active screensaver configuration.
///
/// This struct contains details about a screensaver that is currently set
/// for a specific screen or space, including its display name, unique identifier,
/// file system location, and target screen information.
public struct ScreensaverInfo: Codable, Equatable {
    /// The user-friendly display name of the screensaver.
    ///
    /// This is the name shown in System Preferences and corresponds to
    /// the screensaver's bundle name or display name. Examples: "Aerial",
    /// "Random", "Flurry".
    public let name: String

    /// The unique internal identifier for the screensaver.
    ///
    /// This is typically the bundle identifier or internal name used by
    /// macOS to identify the screensaver module. May differ from the
    /// user-facing `name`. Examples: "com.apple.ScreenSaver.Flurry",
    /// "Aerial".
    public let identifier: String

    /// The file system path to the screensaver module.
    ///
    /// Contains the full path to the `.saver` bundle or app extension.
    /// This is `nil` for built-in system screensavers that don't have
    /// discrete file locations, such as the default "Random" screensaver.
    public let modulePath: String?

    /// The specific screen this screensaver configuration applies to.
    ///
    /// When `nil`, the screensaver applies to all screens or the current
    /// screen. When populated, indicates this configuration is specific
    /// to a particular display identified by its Core Graphics display ID.
    public let screen: ScreenIdentifier?
    
    public init(
        name: String,
        identifier: String,
        modulePath: String? = nil,
        screen: ScreenIdentifier? = nil
    ) {
        self.name = name
        self.identifier = identifier
        self.modulePath = modulePath
        self.screen = screen
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

/// Uniquely identifies a specific physical display/screen.
///
/// This struct wraps a Core Graphics display ID to provide a stable
/// identifier for a specific monitor or display. Used to associate
/// screensaver and wallpaper configurations with particular screens
/// in multi-monitor setups.
public struct ScreenIdentifier: Codable, Equatable {
    /// The Core Graphics display ID for this screen.
    ///
    /// This is a system-assigned identifier that uniquely identifies
    /// a specific physical display. The ID remains consistent as long
    /// as the display remains connected, but may change if displays
    /// are disconnected and reconnected.
    public let displayID: CGDirectDisplayID

    /// Creates a screen identifier from an NSScreen object.
    ///
    /// Extracts the Core Graphics display ID from the NSScreen's device
    /// description dictionary. This is the standard way to create a
    /// ScreenIdentifier from Cocoa screen objects.
    ///
    /// - Parameter screen: The NSScreen to create an identifier for.
    /// - Returns: A ScreenIdentifier if the display ID can be extracted,
    ///   or `nil` if the screen doesn't have a valid display ID.
    public init?(from screen: NSScreen) {
        guard let displayID = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID else {
            return nil
        }
        self.displayID = displayID
    }
}