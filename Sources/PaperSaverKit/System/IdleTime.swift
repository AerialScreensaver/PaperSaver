import Foundation

/// The screensaver idle delay, stored in the current-host `com.apple.screensaver` preferences.
public enum IdleTime {
    private static let domain = "com.apple.screensaver"
    private static let key = "idleTime"

    /// Seconds of inactivity before the screensaver starts; 0 means never.
    public static func seconds() -> Int {
        CFPreferencesCopyValue(key as CFString, domain as CFString, kCFPreferencesCurrentUser, kCFPreferencesCurrentHost) as? Int ?? 0
    }

    public static func set(seconds: Int) throws {
        guard seconds >= 0 else {
            throw PaperSaverError.invalidConfiguration("idle time must be zero or positive")
        }
        CFPreferencesSetValue(key as CFString, seconds as CFNumber, domain as CFString, kCFPreferencesCurrentUser, kCFPreferencesCurrentHost)
        guard CFPreferencesSynchronize(domain as CFString, kCFPreferencesCurrentUser, kCFPreferencesCurrentHost) else {
            throw PaperSaverError.plistWriteError("com.apple.screensaver idleTime")
        }
    }
}
