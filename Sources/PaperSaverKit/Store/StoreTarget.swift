import Foundation

/// Which part of the wallpaper store a read or write addresses.
public enum StoreTarget: Sendable, Equatable {
    /// Every display and every Space: `AllSpacesAndDisplays`, `SystemDefault` and all
    /// per-Space and per-display sections that exist.
    case everywhere
    /// One Space on every display it appears on.
    case space(uuid: String)
    /// One display, on every Space.
    case display(uuid: String)
    /// One Space on one display.
    case spaceOnDisplay(spaceUUID: String, displayUUID: String)
}

/// Which of the two slots of a store section a choice occupies.
public enum WallpaperSlot: String, Sendable, CaseIterable, Codable {
    /// The desktop wallpaper (`Desktop`).
    case desktop
    /// The screensaver (`Idle`).
    case screensaver

    /// The other slot.
    public var other: WallpaperSlot {
        self == .desktop ? .screensaver : .desktop
    }

    var storeKey: String {
        self == .desktop ? "Desktop" : "Idle"
    }
}
