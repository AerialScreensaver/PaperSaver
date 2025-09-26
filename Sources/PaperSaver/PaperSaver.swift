import Foundation
import AppKit

public class PaperSaver {
    private let screensaverManager: ScreensaverManaging
    private let wallpaperManager: WallpaperManaging
    
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
    
    public func setScreensaver(module: String, for screen: NSScreen? = nil) async throws {
        try await screensaverManager.setScreensaver(module: module, screen: screen)
    }
    
    public func getActiveScreensaver(for screen: NSScreen? = nil) -> ScreensaverInfo? {
        return screensaverManager.getActiveScreensaver(for: screen)
    }

    public func getActiveScreensavers() -> [String] {
        return screensaverManager.getActiveScreensavers()
    }

    public func setIdleTime(seconds: Int) throws {
        try screensaverManager.setIdleTime(seconds: seconds)
    }
    
    public func getIdleTime() -> Int {
        return screensaverManager.getIdleTime()
    }
    
    public func listAvailableScreensavers() -> [ScreensaverModule] {
        return screensaverManager.listAvailableScreensavers()
    }
    
    public func setWallpaper(imageURL: URL, screen: NSScreen? = nil, options: WallpaperOptions = .default) async throws {
        try await wallpaperManager.setWallpaper(imageURL: imageURL, screen: screen, options: options)
    }
    
    public func getCurrentWallpaper(for screen: NSScreen? = nil) -> WallpaperInfo? {
        return wallpaperManager.getCurrentWallpaper(for: screen)
    }
    
    public func setWallpaperEverywhere(imageURL: URL, options: WallpaperOptions = .default) async throws {
        try await wallpaperManager.setWallpaperEverywhere(imageURL: imageURL, options: options)
    }
    
    @available(macOS 14.0, *)
    public func setWallpaperForSpace(imageURL: URL, spaceUUID: String, screen: NSScreen? = nil, options: WallpaperOptions = .default) async throws {
        try await wallpaperManager.setWallpaperForSpace(imageURL: imageURL, spaceUUID: spaceUUID, screen: screen, options: options)
    }
    
    @available(macOS 14.0, *)
    public func setWallpaperForSpaceID(imageURL: URL, spaceID: Int, screen: NSScreen? = nil, options: WallpaperOptions = .default) async throws {
        try await wallpaperManager.setWallpaperForSpaceID(imageURL: imageURL, spaceID: spaceID, screen: screen, options: options)
    }
    
    @available(macOS 14.0, *)
    public func setWallpaperForDisplay(imageURL: URL, displayNumber: Int, options: WallpaperOptions = .default) async throws {
        try await wallpaperManager.setWallpaperForDisplay(imageURL: imageURL, displayNumber: displayNumber, options: options)
    }
    
    @available(macOS 14.0, *)
    public func setWallpaperForDisplaySpace(imageURL: URL, displayNumber: Int, spaceNumber: Int, options: WallpaperOptions = .default) async throws {
        try await wallpaperManager.setWallpaperForDisplaySpace(imageURL: imageURL, displayNumber: displayNumber, spaceNumber: spaceNumber, options: options)
    }
    
    
    
    @available(macOS 14.0, *)
    public func getActiveSpace() -> SpaceInfo? {
        guard let spaceManager = screensaverManager as? SpaceManaging else { return nil }
        return spaceManager.getActiveSpace()
    }
    
    
    @available(macOS 14.0, *)
    public func getSpaceByID(_ spaceID: Int) -> SpaceInfo? {
        guard let spaceManager = screensaverManager as? SpaceManaging else { return nil }
        return spaceManager.getSpaceByID(spaceID)
    }
    
    @available(macOS 14.0, *)
    public func listDisplays() -> [DisplayInfo] {
        guard let spaceManager = screensaverManager as? SpaceManaging else { return [] }
        return spaceManager.listDisplays()
    }

    
    @available(macOS 14.0, *)
    public func setScreensaverForSpaceID(module: String, spaceID: Int, screen: NSScreen? = nil) async throws {
        try await screensaverManager.setScreensaverForSpaceID(module: module, spaceID: spaceID, screen: screen)
    }
    
    @available(macOS 14.0, *)
    public func setScreensaverForSpace(module: String, spaceUUID: String, screen: NSScreen? = nil) async throws {
        try await screensaverManager.setScreensaverForSpace(module: module, spaceUUID: spaceUUID, screen: screen)
    }
    
    @available(macOS 14.0, *)
    public func getNativeSpaceTree() -> [String: Any] {
        guard let spaceManager = screensaverManager as? SpaceManaging else { return [:] }
        return spaceManager.getNativeSpaceTree()
    }
    
    public func setScreensaverEverywhere(module: String) async throws {
        try await screensaverManager.setScreensaverEverywhere(module: module)
    }
    
    @available(macOS 14.0, *)
    public func setScreensaverForDisplay(module: String, displayNumber: Int) async throws {
        try await screensaverManager.setScreensaverForDisplay(module: module, displayNumber: displayNumber)
    }
    
    @available(macOS 14.0, *)
    public func setScreensaverForDisplaySpace(module: String, displayNumber: Int, spaceNumber: Int) async throws {
        try await screensaverManager.setScreensaverForDisplaySpace(module: module, displayNumber: displayNumber, spaceNumber: spaceNumber)
    }
    
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
}
