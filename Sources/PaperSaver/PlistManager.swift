import Foundation
import CryptoKit

public final class PlistManager: @unchecked Sendable {
    public static let shared = PlistManager()
    
    private init() {}
    
    public func read(at path: String) throws -> [String: Any] {
        let url = URL(fileURLWithPath: path)
        
        guard FileManager.default.fileExists(atPath: path) else {
            throw PaperSaverError.fileNotFound(url)
        }
        
        do {
            let data = try Data(contentsOf: url)
            
            guard let plist = try PropertyListSerialization.propertyList(
                from: data,
                options: [],
                format: nil
            ) as? [String: Any] else {
                throw PaperSaverError.plistReadError(path)
            }
            
            return plist
        } catch let error as PaperSaverError {
            throw error
        } catch {
            throw PaperSaverError.plistReadError(path)
        }
    }
    
    public func write(_ dictionary: [String: Any], to path: String) throws {
        let url = URL(fileURLWithPath: path)
        
        // Create backup if file exists (don't fail if backup fails)
        if FileManager.default.fileExists(atPath: path) {
            _ = try? backup(at: path)
        }
        
        let directoryPath = url.deletingLastPathComponent().path
        if !FileManager.default.fileExists(atPath: directoryPath) {
            try FileManager.default.createDirectory(
                atPath: directoryPath,
                withIntermediateDirectories: true,
                attributes: nil
            )
        }
        
        do {
            let data = try PropertyListSerialization.data(
                fromPropertyList: dictionary,
                format: .binary,
                options: 0
            )
            
            try data.write(to: url)
        } catch {
            throw PaperSaverError.plistWriteError("\(path): \(error.localizedDescription)")
        }
    }
    
    public func readBinaryPlist(from data: Data) throws -> [String: Any] {
        do {
            guard let plist = try PropertyListSerialization.propertyList(
                from: data,
                options: [],
                format: nil
            ) as? [String: Any] else {
                throw PaperSaverError.plistReadError("binary data")
            }
            
            return plist
        } catch {
            throw PaperSaverError.plistReadError("binary data")
        }
    }
    
    public func createBinaryPlist(from dictionary: [String: Any]) throws -> Data {
        do {
            return try PropertyListSerialization.data(
                fromPropertyList: dictionary,
                format: .binary,
                options: 0
            )
        } catch {
            throw PaperSaverError.plistWriteError("binary data")
        }
    }
    
    public func backup(at path: String) throws -> URL {
        let url = URL(fileURLWithPath: path)
        let backupURL = url.appendingPathExtension("backup")
        
        guard FileManager.default.fileExists(atPath: path) else {
            throw PaperSaverError.fileNotFound(url)
        }
        
        try FileManager.default.copyItem(at: url, to: backupURL)
        return backupURL
    }
    
    public func restore(backupAt backupPath: String, to originalPath: String) throws {
        let backupURL = URL(fileURLWithPath: backupPath)
        let originalURL = URL(fileURLWithPath: originalPath)
        
        guard FileManager.default.fileExists(atPath: backupPath) else {
            throw PaperSaverError.fileNotFound(backupURL)
        }
        
        if FileManager.default.fileExists(atPath: originalPath) {
            try FileManager.default.removeItem(at: originalURL)
        }
        
        try FileManager.default.copyItem(at: backupURL, to: originalURL)
    }

    public func calculateChecksum(at path: String) throws -> String {
        let url = URL(fileURLWithPath: path)

        guard FileManager.default.fileExists(atPath: path) else {
            throw PaperSaverError.fileNotFound(url)
        }

        let data = try Data(contentsOf: url)
        let hash = SHA256.hash(data: data)
        return hash.compactMap { String(format: "%02x", $0) }.joined()
    }

    public func createScreensaverConfiguration(moduleURL: URL) throws -> Data {
        // Determine screensaver type from URL extension
        let `extension` = moduleURL.pathExtension.lowercased()
        let screensaverType = ScreensaverType.allCases.first { $0.fileExtension == `extension` } ?? .traditional
        
        return try createScreensaverConfiguration(moduleURL: moduleURL, type: screensaverType)
    }
    
    public func createScreensaverConfiguration(moduleURL: URL, type: ScreensaverType) throws -> Data {
        switch type {
        case .traditional:
            return try createTraditionalScreensaverConfiguration(moduleURL: moduleURL)
        case .appExtension:
            return try createNeptuneExtensionConfiguration()
        case .sequoiaVideo:
            return try createSequoiaVideoConfiguration()
        case .builtInMac:
            // Built-in Mac screensavers have empty configuration
            return Data()
        case .defaultScreen:
            // Default screensaver has empty configuration
            return Data()
        }
    }
    
    private func createTraditionalScreensaverConfiguration(moduleURL: URL) throws -> Data {
        // Remove trailing slash if present (shouldn't be there for .saver files)
        let urlString = moduleURL.absoluteString
        let cleanURLString = urlString.hasSuffix("/") ? String(urlString.dropLast()) : urlString
        
        let config: [String: Any] = [
            "module": [
                "relative": cleanURLString
            ]
        ]
        
        return try createBinaryPlist(from: config)
    }
    
    private func createNeptuneExtensionConfiguration() throws -> Data {
        // Neptune extensions use different configuration structure
        // Based on analysis, we'll create a placeholder structure
        // This will need to be refined based on actual .appex analysis
        let config: [String: Any] = [
            "values": [
                "legacyScreenSaverGenerationCount": 4,  // Observed value from analysis
                "style": "dynamic"  // Placeholder - may vary
            ],
            "picker": [
                "id": 0
            ]
        ]
        
        return try createBinaryPlist(from: config)
    }
    
    private func createSequoiaVideoConfiguration() throws -> Data {
        // Sequoia video screensavers use values/appearance/picker structure
        let config: [String: Any] = [
            "values": [
                "appearance": "automatic",  // Could be automatic, light, dark
                "picker": [
                    "id": 0
                ]
            ]
        ]
        
        return try createBinaryPlist(from: config)
    }
    
    public func decodeScreensaverConfiguration(from data: Data) throws -> String? {
        let plist = try readBinaryPlist(from: data)
        
        // Try traditional screensaver format first
        if let module = plist["module"] as? [String: Any],
           let relative = module["relative"] as? String,
           let url = URL(string: relative) {
            return url.deletingPathExtension().lastPathComponent
        }
        
        // Try Neptune Extension format
        if let values = plist["values"] as? [String: Any],
           values["legacyScreenSaverGenerationCount"] != nil {
            // For Neptune extensions, we need to extract the name differently
            // This is a placeholder - we'll need to refine based on actual structure
            return "Neptune Extension"
        }
        
        // Try Sequoia video format
        if let values = plist["values"] as? [String: Any],
           let appearance = values["appearance"] as? String {
            // For Sequoia video screensavers, we might extract name differently
            return "Sequoia Video (\(appearance))"
        }
        
        return nil
    }
    
    public func decodeScreensaverConfigurationWithType(from data: Data) throws -> (name: String?, type: ScreensaverType) {
        let plist = try readBinaryPlist(from: data)
        
        // Try traditional screensaver format first
        if let module = plist["module"] as? [String: Any],
           let relative = module["relative"] as? String,
           let url = URL(string: relative) {
            let name = url.deletingPathExtension().lastPathComponent
            let `extension` = url.pathExtension.lowercased()
            let type = ScreensaverType.allCases.first { $0.fileExtension == `extension` } ?? .traditional
            return (name, type)
        }
        
        // Try Neptune Extension format
        if let values = plist["values"] as? [String: Any],
           values["legacyScreenSaverGenerationCount"] != nil {
            return ("Neptune Extension", .appExtension)
        }
        
        // Try Sequoia video format
        if let values = plist["values"] as? [String: Any],
           let appearance = values["appearance"] as? String {
            return ("Sequoia Video (\(appearance))", .sequoiaVideo)
        }
        
        return (nil, .traditional)
    }
    
    public func createWallpaperConfiguration(imageURL: URL) throws -> Data {
        let wallpaperConfig: [String: Any] = [
            "type": "imageFile",
            "url": [
                "relative": imageURL.absoluteString
            ]
        ]
        
        return try createBinaryPlist(from: wallpaperConfig)
    }
    
    public func decodeWallpaperConfiguration(from data: Data) throws -> String? {
        let plist = try readBinaryPlist(from: data)
        
        if let url = plist["url"] as? [String: Any],
           let relative = url["relative"] as? String {
            return relative
        }
        
        return nil
    }
    
    public func createWallpaperOptions(style: WallpaperStyle = .fill) throws -> Data {
        let optionsConfig: [String: Any] = [
            "values": [
                "style": [
                    "picker": [
                        "_0": [
                            "id": style.rawValue
                        ]
                    ]
                ]
            ]
        ]
        
        return try createBinaryPlist(from: optionsConfig)
    }
}

/// The display style for wallpaper images.
///
/// Specifies how a wallpaper image should be scaled, positioned, and
/// displayed on the screen. Each style affects how the image fills
/// or fits within the available screen space.
public enum WallpaperStyle: String, Sendable {
    /// Scale the image to fill the entire screen, cropping if necessary.
    ///
    /// The image is scaled to completely fill the screen while maintaining
    /// its aspect ratio. Parts of the image may be cropped if the aspect
    /// ratios don't match. This is the most common wallpaper style.
    case fill = "fill"

    /// Scale the image to fit entirely within the screen.
    ///
    /// The image is scaled to fit completely within the screen boundaries
    /// while maintaining its aspect ratio. Black bars may appear if the
    /// aspect ratios don't match. No part of the image is cropped.
    case fit = "fit"

    /// Stretch the image to exactly match the screen dimensions.
    ///
    /// The image is scaled to exactly fill the screen, potentially
    /// distorting the aspect ratio. The entire image is visible but
    /// may appear stretched or squashed.
    case stretch = "stretch"

    /// Display the image at its natural size, centered on the screen.
    ///
    /// The image is displayed at its original size without scaling,
    /// positioned in the center of the screen. If the image is smaller
    /// than the screen, the background color shows around it.
    case center = "center"

    /// Tile the image to fill the screen by repeating it.
    ///
    /// The image is repeated in a grid pattern to fill the entire
    /// screen. Useful for seamless textures and patterns. The image
    /// is displayed at its original size.
    case tile = "tile"

    /// Use dynamic wallpaper features (time-based or adaptive).
    ///
    /// For dynamic wallpapers that change based on time of day or
    /// system appearance. The exact behavior depends on the specific
    /// wallpaper and system settings.
    case dynamic = "dynamic"
}
