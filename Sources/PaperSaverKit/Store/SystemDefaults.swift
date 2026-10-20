import Foundation

/// The choice the system itself puts in a slot when nothing is selected.
public enum SystemDefaults {
    /// The default wallpaper of macOS 26 and later: provider `com.apple.NeptuneOneExtension`,
    /// empty configuration, no files, empty option values and no shuffle.
    public static func neptuneOne(date: Date = Date()) -> SlotConfiguration {
        SlotConfiguration(
            choice: WallpaperChoice(provider: .neptuneOne),
            optionValues: .values(.empty),
            shuffle: .null,
            date: date)
    }

    /// The agent's "nothing set" placeholder: provider `default`, empty configuration and the
    /// string `$null` for option values and shuffle. The agent writes it itself in `Linked`
    /// and `Idle` slots and, measured on macOS 27.2, keeps it as the `Desktop` of an
    /// `individual` section.
    public static func placeholder(date: Date = Date()) -> SlotConfiguration {
        SlotConfiguration(
            choice: WallpaperChoice(provider: .placeholder),
            optionValues: .null,
            shuffle: .null,
            date: date)
    }

    /// The system default for a slot on the running macOS.
    public static func slot(_ slot: WallpaperSlot) -> SlotConfiguration {
        self.slot(slot, on: ProcessInfo.processInfo.operatingSystemVersion)
    }

    /// `neptuneOne` on macOS 26 and later, where it is what System Settings records; the
    /// placeholder before that, where the default choice has not been captured.
    public static func slot(_ slot: WallpaperSlot, on version: OperatingSystemVersion) -> SlotConfiguration {
        version.majorVersion >= 26 ? neptuneOne() : placeholder()
    }
}
