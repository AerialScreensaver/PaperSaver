import Foundation

public struct ScreensaverModule: Codable, Equatable {
    public let name: String
    public let identifier: String
    public let path: URL
    public let isSystem: Bool
    public let thumbnail: URL?
    
    public init(
        name: String,
        identifier: String,
        path: URL,
        isSystem: Bool = false,
        thumbnail: URL? = nil
    ) {
        self.name = name
        self.identifier = identifier
        self.path = path
        self.isSystem = isSystem
        self.thumbnail = thumbnail
    }
    
    public var isAvailable: Bool {
        FileManager.default.fileExists(atPath: path.path)
    }
}