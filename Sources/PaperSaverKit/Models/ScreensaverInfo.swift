import Foundation
import AppKit

/// The screensaver a store slot points at.
public struct ScreensaverInfo: Codable, Equatable, Sendable {
    /// The module's file name without extension for a `.saver` or app-extension screensaver,
    /// the bundle identifier for a wallpaper extension.
    public let name: String
    /// The module's file name with extension, or the bundle identifier.
    public let identifier: String
    /// The bundle path, when the screensaver is a bundle on disk.
    public let modulePath: String?
    /// The store provider.
    public let provider: String
    public let kind: ScreensaverType
    /// The display the query was scoped to, if any.
    public let displayUUID: String?

    public init(name: String, identifier: String, modulePath: String? = nil, provider: String, kind: ScreensaverType, displayUUID: String? = nil) {
        self.name = name
        self.identifier = identifier
        self.modulePath = modulePath
        self.provider = provider
        self.kind = kind
        self.displayUUID = displayUUID
    }

    /// Describes a slot's choice, or `nil` when the slot holds no screensaver (the agent's
    /// placeholder or the system default wallpaper).
    public init?(slot: SlotConfiguration, displayUUID: String? = nil) {
        guard let provider = slot.provider, !provider.isPlaceholder, provider != .neptuneOne else { return nil }
        if case .screenSaver(let url)? = slot.configuration {
            self.init(name: url.deletingPathExtension().lastPathComponent, identifier: url.lastPathComponent,
                      modulePath: url.path, provider: provider.rawValue, kind: ScreensaverType(bundleURL: url),
                      displayUUID: displayUUID)
            return
        }
        let kind: ScreensaverType
        if provider.isThirdPartyExtension { kind = .wallpaperExtension }
        else if provider == .aerials { kind = .sequoiaVideo }
        else if provider == .macintosh { kind = .builtInMac }
        else { kind = .defaultScreen }
        self.init(name: provider.rawValue, identifier: provider.rawValue, provider: provider.rawValue, kind: kind, displayUUID: displayUUID)
    }
}

/// A connected display, by Core Graphics identifier.
public struct ScreenIdentifier: Codable, Equatable, Sendable {
    public let displayID: CGDirectDisplayID

    public init(displayID: CGDirectDisplayID) {
        self.displayID = displayID
    }

    /// The identifier of an `NSScreen`.
    @MainActor
    public init?(from screen: NSScreen) {
        guard let displayID = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID else {
            return nil
        }
        self.displayID = displayID
    }

    /// The display UUID the wallpaper store uses for this display.
    public var uuid: String? {
        DisplayUUID.uuid(for: displayID)
    }
}
