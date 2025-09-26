import Foundation
import AppKit

public class PaperSaver {
    private let screensaverManager: ScreensaverManaging
    private let wallpaperManager: WallpaperManaging

    // MARK: - Initialization

    public init() {
        self.screensaverManager = ScreensaverManager()
        self.wallpaperManager = WallpaperManager()
    }

    public init(
        screensaverManager: ScreensaverManaging = ScreensaverManager(),
        wallpaperManager: WallpaperManaging = WallpaperManager()
    ) {
        self.screensaverManager = screensaverManager
        self.wallpaperManager = wallpaperManager
    }

    // MARK: - Screensaver Management

    // MARK: Core Screensaver Operations

    /// Returns a list of all available screensaver modules on the system.
    ///
    /// This function scans both system and user screensaver directories to find
    /// all installed screensaver modules, including traditional `.saver` files
    /// and modern App Extension screensavers.
    ///
    /// - Returns: An array of `ScreensaverModule` objects containing details about
    ///   each available screensaver, including name, type, and file path.
    /// - Note: The list includes both system screensavers (built into macOS) and
    ///   user-installed screensavers.
    public func listAvailableScreensavers() -> [ScreensaverModule] {
        return screensaverManager.listAvailableScreensavers()
    }

    /// Gets the currently active screensaver for a specific screen.
    ///
    /// This function retrieves information about the screensaver currently
    /// configured for the specified screen. It handles both single-screen
    /// and multi-screen configurations automatically.
    ///
    /// - Parameter screen: The target screen to query. If `nil`, uses the
    ///   current screen or main screen.
    /// - Returns: A `ScreensaverInfo` object with details about the active
    ///   screensaver, or `nil` if no screensaver is configured.
    /// - Note: On single-screen systems, the screen parameter is typically ignored.
    public func getActiveScreensaver(for screen: NSScreen? = nil) -> ScreensaverInfo? {
        return screensaverManager.getActiveScreensaver(for: screen)
    }

    /// Gets the names of all currently active screensavers across all screens and spaces.
    ///
    /// This function returns a comprehensive list of screensaver names that are
    /// currently configured across all displays and spaces in the system.
    /// Useful for getting an overview of the current screensaver configuration.
    ///
    /// - Returns: An array of screensaver names currently active in the system.
    ///   The array may contain duplicates if the same screensaver is used in
    ///   multiple locations.
    /// - Note: This function works across all spaces and displays, providing
    ///   a system-wide view of active screensavers.
    public func getActiveScreensavers() -> [String] {
        return screensaverManager.getActiveScreensavers()
    }

    /// Sets the screensaver for a specific screen.
    ///
    /// This function configures the specified screensaver module for the given
    /// screen. The operation is asynchronous and may take a moment to complete
    /// as the system updates its configuration.
    ///
    /// - Parameters:
    ///   - module: The name of the screensaver module to activate. Must match
    ///     an available screensaver from `listAvailableScreensavers()`.
    ///   - screen: The target screen to configure. If `nil`, applies to the
    ///     current or main screen.
    /// - Throws: `PaperSaverError.screensaverNotFound` if the specified module
    ///   doesn't exist, or `PaperSaverError.invalidConfiguration` if the
    ///   configuration cannot be applied.
    /// - Note: Changes take effect immediately but may require a moment to
    ///   be reflected in the system preferences.
    public func setScreensaver(module: String, for screen: NSScreen? = nil) async throws {
        try await screensaverManager.setScreensaver(module: module, screen: screen)
    }

    /// Sets the same screensaver across all screens and spaces.
    ///
    /// This function applies the specified screensaver module to all displays
    /// and spaces in the system, creating a unified screensaver experience.
    /// This is the most commonly used function for setting screensavers.
    ///
    /// - Parameter module: The name of the screensaver module to activate
    ///   system-wide. Must match an available screensaver from
    ///   `listAvailableScreensavers()`.
    /// - Throws: `PaperSaverError.screensaverNotFound` if the specified module
    ///   doesn't exist, or `PaperSaverError.invalidConfiguration` if the
    ///   configuration cannot be applied.
    /// - Note: This is equivalent to setting the screensaver in System
    ///   Preferences for all screens and spaces at once.
    public func setScreensaverEverywhere(module: String) async throws {
        try await screensaverManager.setScreensaverEverywhere(module: module)
    }

    // MARK: Advanced Screensaver Operations (macOS 14.0+)

    /// Sets the screensaver for a specific space identified by UUID.
    ///
    /// This advanced function allows you to configure different screensavers
    /// for individual spaces (virtual desktops) in macOS. Each space can have
    /// its own screensaver configuration.
    ///
    /// - Parameters:
    ///   - module: The name of the screensaver module to activate.
    ///   - spaceUUID: The UUID of the target space. Use `getActiveSpace()` or
    ///     space management functions to obtain valid UUIDs.
    ///   - screen: The target screen within the space. If `nil`, applies to
    ///     the main screen in that space.
    /// - Throws: `PaperSaverError.screensaverNotFound` if the module doesn't exist,
    ///   `PaperSaverError.spaceNotFound` if the UUID is invalid, or
    ///   `PaperSaverError.invalidConfiguration` for other configuration issues.
    /// - Note: This function requires macOS 14.0 or later for full space support.
    @available(macOS 14.0, *)
    public func setScreensaverForSpace(module: String, spaceUUID: String, screen: NSScreen? = nil) async throws {
        try await screensaverManager.setScreensaverForSpace(module: module, spaceUUID: spaceUUID, screen: screen)
    }

    /// Sets the screensaver for a specific space identified by numeric ID.
    ///
    /// This function provides an alternative way to target spaces using their
    /// numeric identifier instead of UUID. Useful when working with space
    /// numbers from Mission Control or other system tools.
    ///
    /// - Parameters:
    ///   - module: The name of the screensaver module to activate.
    ///   - spaceID: The numeric ID of the target space.
    ///   - screen: The target screen within the space. If `nil`, applies to
    ///     the main screen in that space.
    /// - Throws: `PaperSaverError.screensaverNotFound` if the module doesn't exist,
    ///   `PaperSaverError.spaceNotFound` if the space ID is invalid, or
    ///   `PaperSaverError.invalidConfiguration` for other configuration issues.
    /// - Note: Space IDs may change when spaces are created or destroyed.
    @available(macOS 14.0, *)
    public func setScreensaverForSpaceID(module: String, spaceID: Int, screen: NSScreen? = nil) async throws {
        try await screensaverManager.setScreensaverForSpaceID(module: module, spaceID: spaceID, screen: screen)
    }

    /// Sets the screensaver for all spaces on a specific display.
    ///
    /// This function configures the screensaver for an entire display,
    /// affecting all spaces on that display. Useful in multi-monitor
    /// setups where you want different screensavers per display.
    ///
    /// - Parameters:
    ///   - module: The name of the screensaver module to activate.
    ///   - displayNumber: The display number (typically 1 for main display,
    ///     2 for secondary, etc.).
    /// - Throws: `PaperSaverError.screensaverNotFound` if the module doesn't exist,
    ///   `PaperSaverError.displayNotFound` if the display number is invalid, or
    ///   `PaperSaverError.invalidConfiguration` for other configuration issues.
    /// - Note: Display numbers correspond to the system's display arrangement.
    @available(macOS 14.0, *)
    public func setScreensaverForDisplay(module: String, displayNumber: Int) async throws {
        try await screensaverManager.setScreensaverForDisplay(module: module, displayNumber: displayNumber)
    }

    /// Sets the screensaver for a specific space on a specific display.
    ///
    /// This is the most granular screensaver configuration function, allowing
    /// you to target a specific space on a specific display. Perfect for
    /// complex multi-monitor, multi-space setups.
    ///
    /// - Parameters:
    ///   - module: The name of the screensaver module to activate.
    ///   - displayNumber: The display number (1 for main, 2 for secondary, etc.).
    ///   - spaceNumber: The space number on that display (1-based indexing).
    /// - Throws: `PaperSaverError.screensaverNotFound` if the module doesn't exist,
    ///   `PaperSaverError.displayNotFound` if the display number is invalid,
    ///   `PaperSaverError.spaceNotFoundOnDisplay` if the space doesn't exist on
    ///   that display, or `PaperSaverError.invalidConfiguration` for other issues.
    /// - Warning: Space numbers may change when spaces are added or removed.
    @available(macOS 14.0, *)
    public func setScreensaverForDisplaySpace(module: String, displayNumber: Int, spaceNumber: Int) async throws {
        try await screensaverManager.setScreensaverForDisplaySpace(module: module, displayNumber: displayNumber, spaceNumber: spaceNumber)
    }

    // MARK: Idle Time Management

    /// Gets the current screensaver idle time setting.
    ///
    /// This function retrieves the amount of time the system waits before
    /// activating the screensaver when there's no user activity.
    ///
    /// - Returns: The idle time in seconds. Returns `0` if the screensaver
    ///   is set to "Never" activate.
    /// - Note: The returned value corresponds to the "Start after" setting
    ///   in System Preferences > Desktop & Screen Saver.
    public func getIdleTime() -> Int {
        return screensaverManager.getIdleTime()
    }

    /// Sets the screensaver idle time.
    ///
    /// This function configures how long the system waits before activating
    /// the screensaver when there's no user activity. The change takes effect
    /// immediately.
    ///
    /// - Parameter seconds: The idle time in seconds. Use `0` to set the
    ///   screensaver to "Never" activate. Common values are 60 (1 minute),
    ///   300 (5 minutes), 600 (10 minutes), etc.
    /// - Throws: `PaperSaverError.invalidConfiguration` if the seconds value
    ///   is negative or otherwise invalid.
    /// - Note: This is equivalent to changing the "Start after" setting in
    ///   System Preferences > Desktop & Screen Saver.
    public func setIdleTime(seconds: Int) throws {
        try screensaverManager.setIdleTime(seconds: seconds)
    }

    // MARK: - Wallpaper Management

    // MARK: Core Wallpaper Operations

    /// Gets the current wallpaper information for a specific screen.
    ///
    /// This function retrieves details about the wallpaper currently set
    /// for the specified screen, including the image path and display options.
    ///
    /// - Parameter screen: The target screen to query. If `nil`, uses the
    ///   current screen or main screen.
    /// - Returns: A `WallpaperInfo` object containing the wallpaper path and
    ///   configuration, or `nil` if no wallpaper is set or the information
    ///   cannot be retrieved.
    /// - Note: The returned path may be a file URL or a reference to a
    ///   system wallpaper collection.
    public func getCurrentWallpaper(for screen: NSScreen? = nil) -> WallpaperInfo? {
        return wallpaperManager.getCurrentWallpaper(for: screen)
    }

    /// Sets the wallpaper for a specific screen.
    ///
    /// This function configures a new wallpaper image for the specified screen.
    /// The operation is asynchronous and may take a moment to complete as the
    /// system processes and applies the image.
    ///
    /// - Parameters:
    ///   - imageURL: The URL of the image file to use as wallpaper. Must be
    ///     a valid image format (JPEG, PNG, HEIF, etc.).
    ///   - screen: The target screen to configure. If `nil`, applies to the
    ///     current or main screen.
    ///   - options: Display options for the wallpaper (scaling, positioning, etc.).
    ///     Defaults to `.default` which uses system preferences.
    /// - Throws: `PaperSaverError.fileNotFound` if the image doesn't exist,
    ///   `PaperSaverError.invalidConfiguration` if the image format is unsupported,
    ///   or other I/O errors during the operation.
    /// - Note: The image file must be accessible and in a supported format.
    public func setWallpaper(imageURL: URL, screen: NSScreen? = nil, options: WallpaperOptions = .default) async throws {
        try await wallpaperManager.setWallpaper(imageURL: imageURL, screen: screen, options: options)
    }

    /// Sets the same wallpaper across all screens and spaces.
    ///
    /// This function applies the specified wallpaper image to all displays
    /// and spaces in the system, creating a unified desktop experience.
    /// This is the most commonly used function for setting wallpapers.
    ///
    /// - Parameters:
    ///   - imageURL: The URL of the image file to use as wallpaper. Must be
    ///     a valid image format (JPEG, PNG, HEIF, etc.).
    ///   - options: Display options for the wallpaper (scaling, positioning, etc.).
    ///     Defaults to `.default` which uses system preferences.
    /// - Throws: `PaperSaverError.fileNotFound` if the image doesn't exist,
    ///   `PaperSaverError.invalidConfiguration` if the image format is unsupported,
    ///   or other I/O errors during the operation.
    /// - Note: This is equivalent to setting the wallpaper in System
    ///   Preferences for all screens and spaces at once.
    public func setWallpaperEverywhere(imageURL: URL, options: WallpaperOptions = .default) async throws {
        try await wallpaperManager.setWallpaperEverywhere(imageURL: imageURL, options: options)
    }

    // MARK: Advanced Wallpaper Operations (macOS 14.0+)

    /// Sets the wallpaper for a specific space identified by UUID.
    ///
    /// This advanced function allows you to configure different wallpapers
    /// for individual spaces (virtual desktops) in macOS. Each space can have
    /// its own unique wallpaper.
    ///
    /// - Parameters:
    ///   - imageURL: The URL of the image file to use as wallpaper.
    ///   - spaceUUID: The UUID of the target space. Use `getActiveSpace()` or
    ///     space management functions to obtain valid UUIDs.
    ///   - screen: The target screen within the space. If `nil`, applies to
    ///     the main screen in that space.
    ///   - options: Display options for the wallpaper (scaling, positioning, etc.).
    /// - Throws: `PaperSaverError.fileNotFound` if the image doesn't exist,
    ///   `PaperSaverError.spaceNotFound` if the UUID is invalid, or
    ///   `PaperSaverError.invalidConfiguration` for other configuration issues.
    /// - Note: This function requires macOS 14.0 or later for full space support.
    @available(macOS 14.0, *)
    public func setWallpaperForSpace(imageURL: URL, spaceUUID: String, screen: NSScreen? = nil, options: WallpaperOptions = .default) async throws {
        try await wallpaperManager.setWallpaperForSpace(imageURL: imageURL, spaceUUID: spaceUUID, screen: screen, options: options)
    }

    /// Sets the wallpaper for a specific space identified by numeric ID.
    ///
    /// This function provides an alternative way to target spaces using their
    /// numeric identifier instead of UUID. Useful when working with space
    /// numbers from Mission Control or other system tools.
    ///
    /// - Parameters:
    ///   - imageURL: The URL of the image file to use as wallpaper.
    ///   - spaceID: The numeric ID of the target space.
    ///   - screen: The target screen within the space. If `nil`, applies to
    ///     the main screen in that space.
    ///   - options: Display options for the wallpaper (scaling, positioning, etc.).
    /// - Throws: `PaperSaverError.fileNotFound` if the image doesn't exist,
    ///   `PaperSaverError.spaceNotFound` if the space ID is invalid, or
    ///   `PaperSaverError.invalidConfiguration` for other configuration issues.
    /// - Note: Space IDs may change when spaces are created or destroyed.
    @available(macOS 14.0, *)
    public func setWallpaperForSpaceID(imageURL: URL, spaceID: Int, screen: NSScreen? = nil, options: WallpaperOptions = .default) async throws {
        try await wallpaperManager.setWallpaperForSpaceID(imageURL: imageURL, spaceID: spaceID, screen: screen, options: options)
    }

    /// Sets the wallpaper for all spaces on a specific display.
    ///
    /// This function configures the wallpaper for an entire display,
    /// affecting all spaces on that display. Useful in multi-monitor
    /// setups where you want different wallpapers per display.
    ///
    /// - Parameters:
    ///   - imageURL: The URL of the image file to use as wallpaper.
    ///   - displayNumber: The display number (typically 1 for main display,
    ///     2 for secondary, etc.).
    ///   - options: Display options for the wallpaper (scaling, positioning, etc.).
    /// - Throws: `PaperSaverError.fileNotFound` if the image doesn't exist,
    ///   `PaperSaverError.displayNotFound` if the display number is invalid, or
    ///   `PaperSaverError.invalidConfiguration` for other configuration issues.
    /// - Note: Display numbers correspond to the system's display arrangement.
    @available(macOS 14.0, *)
    public func setWallpaperForDisplay(imageURL: URL, displayNumber: Int, options: WallpaperOptions = .default) async throws {
        try await wallpaperManager.setWallpaperForDisplay(imageURL: imageURL, displayNumber: displayNumber, options: options)
    }

    /// Sets the wallpaper for a specific space on a specific display.
    ///
    /// This is the most granular wallpaper configuration function, allowing
    /// you to target a specific space on a specific display. Perfect for
    /// complex multi-monitor, multi-space setups with unique wallpapers.
    ///
    /// - Parameters:
    ///   - imageURL: The URL of the image file to use as wallpaper.
    ///   - displayNumber: The display number (1 for main, 2 for secondary, etc.).
    ///   - spaceNumber: The space number on that display (1-based indexing).
    ///   - options: Display options for the wallpaper (scaling, positioning, etc.).
    /// - Throws: `PaperSaverError.fileNotFound` if the image doesn't exist,
    ///   `PaperSaverError.displayNotFound` if the display number is invalid,
    ///   `PaperSaverError.spaceNotFoundOnDisplay` if the space doesn't exist on
    ///   that display, or `PaperSaverError.invalidConfiguration` for other issues.
    /// - Warning: Space numbers may change when spaces are added or removed.
    @available(macOS 14.0, *)
    public func setWallpaperForDisplaySpace(imageURL: URL, displayNumber: Int, spaceNumber: Int, options: WallpaperOptions = .default) async throws {
        try await wallpaperManager.setWallpaperForDisplaySpace(imageURL: imageURL, displayNumber: displayNumber, spaceNumber: spaceNumber, options: options)
    }

    // MARK: - Space & Display Management (macOS 14.0+)

    /// Gets information about the currently active space.
    ///
    /// This function retrieves details about the space (virtual desktop)
    /// that is currently visible and active on the system.
    ///
    /// - Returns: A `SpaceInfo` object containing the space's name, UUID,
    ///   and display information, or `nil` if the information cannot be
    ///   retrieved.
    /// - Note: The active space is the one currently visible to the user.
    ///   In multi-monitor setups, this typically refers to the space on
    ///   the main display that has focus.
    @available(macOS 14.0, *)
    public func getActiveSpace() -> SpaceInfo? {
        guard let spaceManager = screensaverManager as? SpaceManaging else { return nil }
        return spaceManager.getActiveSpace()
    }

    /// Gets information about a specific space by its numeric ID.
    ///
    /// This function retrieves details about a space using its numeric
    /// identifier, which can be useful when working with space numbers
    /// from Mission Control or other system tools.
    ///
    /// - Parameter spaceID: The numeric ID of the space to query.
    /// - Returns: A `SpaceInfo` object containing the space's details,
    ///   or `nil` if the space doesn't exist or information cannot be retrieved.
    /// - Note: Space IDs may change when spaces are created, destroyed,
    ///   or reordered through Mission Control.
    @available(macOS 14.0, *)
    public func getSpaceByID(_ spaceID: Int) -> SpaceInfo? {
        guard let spaceManager = screensaverManager as? SpaceManaging else { return nil }
        return spaceManager.getSpaceByID(spaceID)
    }

    /// Lists all displays currently connected to the system.
    ///
    /// This function provides information about all displays (monitors)
    /// that are currently connected, including both active displays and
    /// historical display configurations that the system remembers.
    ///
    /// - Returns: An array of `DisplayInfo` objects containing details
    ///   about each display, including resolution, identifier, and status.
    ///   Returns an empty array if no display information is available.
    /// - Note: The list includes both currently connected displays and
    ///   previously connected displays that macOS remembers for configuration
    ///   purposes.
    @available(macOS 14.0, *)
    public func listDisplays() -> [DisplayInfo] {
        guard let spaceManager = screensaverManager as? SpaceManaging else { return [] }
        return spaceManager.listDisplays()
    }

    /// Gets the raw space configuration tree from the system.
    ///
    /// This function provides access to the underlying space and display
    /// configuration data as stored by macOS. Useful for debugging or
    /// advanced space management scenarios.
    ///
    /// - Returns: A dictionary containing the raw space tree data from
    ///   the system preferences. The structure includes monitors, spaces,
    ///   and their relationships. Returns an empty dictionary if the
    ///   information cannot be accessed.
    /// - Warning: This function returns low-level system data and is
    ///   primarily intended for debugging purposes. The structure may
    ///   change between macOS versions.
    @available(macOS 14.0, *)
    public func getNativeSpaceTree() -> [String: Any] {
        guard let spaceManager = screensaverManager as? SpaceManaging else { return [:] }
        return spaceManager.getNativeSpaceTree()
    }

    // MARK: - Backup & Restore (macOS 14.0+)

    /// Gets information about the current configuration backup.
    ///
    /// This function checks for the existence of a backup file containing
    /// the previous wallpaper and screensaver configuration, which can be
    /// used to restore settings if needed.
    ///
    /// - Returns: A tuple containing:
    ///   - `exists`: Whether a backup file exists
    ///   - `date`: The modification date of the backup file, or `nil` if
    ///     the file doesn't exist or the date cannot be determined
    ///   - `size`: The size of the backup file in bytes, or `nil` if
    ///     the file doesn't exist or the size cannot be determined
    /// - Note: Backups are automatically created when making configuration
    ///   changes through PaperSaver's advanced functions.
    @available(macOS 14.0, *)
    public func getBackupInfo() -> (exists: Bool, date: Date?, size: Int64?) {
        let indexPath = SystemPaths.wallpaperIndexPath
        let backupPath = indexPath + ".backup"

        guard FileManager.default.fileExists(atPath: backupPath) else {
            return (false, nil, nil)
        }

        do {
            let attributes = try FileManager.default.attributesOfItem(atPath: backupPath)
            let date = attributes[.modificationDate] as? Date
            let size = attributes[.size] as? Int64
            return (true, date, size)
        } catch {
            return (true, nil, nil)
        }
    }

    /// Restores wallpaper and screensaver configuration from backup.
    ///
    /// This function restores the system's wallpaper and screensaver
    /// configuration from a previously created backup file. This can be
    /// useful to undo configuration changes or recover from issues.
    ///
    /// - Throws: `PaperSaverError.fileNotFound` if no backup file exists,
    ///   `PaperSaverError.plistReadError` if the backup file is corrupted,
    ///   or `PaperSaverError.plistWriteError` if the restore operation fails
    ///   due to permissions or other system issues.
    /// - Note: This operation immediately takes effect and will change the
    ///   current wallpaper and screensaver settings to match the backup.
    /// - Warning: This operation cannot be undone. Consider using
    ///   `getBackupInfo()` first to verify the backup exists and check its date.
    @available(macOS 14.0, *)
    public func restoreFromBackup() throws {
        let indexPath = SystemPaths.wallpaperIndexPath
        let backupPath = indexPath + ".backup"

        guard FileManager.default.fileExists(atPath: backupPath) else {
            throw PaperSaverError.fileNotFound(URL(fileURLWithPath: backupPath))
        }

        let plistManager = PlistManager.shared
        try plistManager.restore(backupAt: backupPath, to: indexPath)
    }
}