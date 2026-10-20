import Foundation

/// The bytes of the store before a write, so that write can be undone exactly.
public struct StoreSnapshot: Sendable, Equatable {
    /// The previous contents, or `nil` when no store file existed.
    public let previousContents: Data?
    public let capturedAt: Date
}

/// What is known about the `.backup` file next to the store.
public struct BackupInfo: Sendable, Equatable {
    public let url: URL
    public let modificationDate: Date
    public let size: Int
}

/// The size and modification date of the store file, used to detect the agent rewriting it.
public struct ModificationStamp: Sendable, Equatable {
    public let modificationDate: Date
    public let size: Int
}

/// Reads and writes the wallpaper store file.
///
/// Every write refreshes `Index.plist.backup` with the previous contents and returns a
/// `StoreSnapshot` of them, so a failed write can be undone with exactly what it replaced.
public struct StoreFile: Sendable {
    public let url: URL

    public init(url: URL = SystemPaths.wallpaperStoreURL) {
        self.url = url
    }

    public var backupURL: URL {
        url.appendingPathExtension("backup")
    }

    // MARK: Reading

    public func readRaw() throws -> Data {
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw PaperSaverError.fileNotFound(url)
        }
        do {
            return try Data(contentsOf: url)
        } catch {
            throw PaperSaverError.plistReadError("\(url.path): \(error.localizedDescription)")
        }
    }

    public func readPlist() throws -> [String: Any] {
        let data = try readRaw()
        guard let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] else {
            throw PaperSaverError.plistReadError("\(url.path): not a property-list dictionary")
        }
        return plist
    }

    public func read() throws -> WallpaperStore {
        try StoreCodec.decode(try readPlist())
    }

    // MARK: Writing

    /// Writes the store as a binary property list, atomically, after refreshing the backup.
    @discardableResult
    public func write(_ store: WallpaperStore) throws -> StoreSnapshot {
        try write(plist: StoreCodec.encode(store))
    }

    @discardableResult
    public func write(plist: [String: Any]) throws -> StoreSnapshot {
        let data: Data
        do {
            data = try PropertyListSerialization.data(fromPropertyList: plist, format: .binary, options: 0)
        } catch {
            throw PaperSaverError.plistWriteError("\(url.path): \(error.localizedDescription)")
        }
        return try writeRaw(data)
    }

    @discardableResult
    public func writeRaw(_ data: Data) throws -> StoreSnapshot {
        let previous = try? readRaw()
        let snapshot = StoreSnapshot(previousContents: previous, capturedAt: Date())
        do {
            let directory = url.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            if let previous {
                // `copyItem` refuses to overwrite, which is how 0.3.1 ended up with a backup
                // that was never refreshed after the first write.
                try previous.write(to: backupURL, options: .atomic)
            }
            try data.write(to: url, options: .atomic)
        } catch let error as PaperSaverError {
            throw error
        } catch {
            throw PaperSaverError.plistWriteError("\(url.path): \(error.localizedDescription)")
        }
        return snapshot
    }

    /// Puts back the bytes a write replaced.
    public func restore(_ snapshot: StoreSnapshot) throws {
        do {
            if let previous = snapshot.previousContents {
                try previous.write(to: url, options: .atomic)
            } else if FileManager.default.fileExists(atPath: url.path) {
                try FileManager.default.removeItem(at: url)
            }
        } catch {
            throw PaperSaverError.plistWriteError("\(url.path): \(error.localizedDescription)")
        }
    }

    /// Copies `Index.plist.backup` over the store.
    public func restoreFromBackupFile() throws {
        guard FileManager.default.fileExists(atPath: backupURL.path) else {
            throw PaperSaverError.fileNotFound(backupURL)
        }
        do {
            let data = try Data(contentsOf: backupURL)
            try data.write(to: url, options: .atomic)
        } catch {
            throw PaperSaverError.plistWriteError("\(url.path): \(error.localizedDescription)")
        }
    }

    // MARK: Inspection

    public func backupInfo() -> BackupInfo? {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: backupURL.path),
              let date = attributes[.modificationDate] as? Date,
              let size = attributes[.size] as? Int else {
            return nil
        }
        return BackupInfo(url: backupURL, modificationDate: date, size: size)
    }

    public func modificationStamp() -> ModificationStamp? {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
              let date = attributes[.modificationDate] as? Date,
              let size = attributes[.size] as? Int else {
            return nil
        }
        return ModificationStamp(modificationDate: date, size: size)
    }
}
