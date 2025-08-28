import Foundation

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
                        throw PaperSaverError.plistWriteError(path)
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
    
    public func decodeBase64Plist(from base64String: String) throws -> [String: Any] {
        guard let data = Data(base64Encoded: base64String) else {
            throw PaperSaverError.invalidConfiguration("Invalid base64 encoding")
        }
        
        return try readBinaryPlist(from: data)
    }
    
    public func encodeAsBase64Plist(_ dictionary: [String: Any]) throws -> String {
        let data = try createBinaryPlist(from: dictionary)
        return data.base64EncodedString()
    }
    
    public func createScreensaverConfiguration(moduleURL: URL) throws -> Data {
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
    
    public func decodeScreensaverConfiguration(from data: Data) throws -> String? {
        let plist = try readBinaryPlist(from: data)
        
        if let module = plist["module"] as? [String: Any],
           let relative = module["relative"] as? String,
           let url = URL(string: relative) {
            return url.deletingPathExtension().lastPathComponent
        }
        
        return nil
    }
}
