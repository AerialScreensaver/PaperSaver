import Foundation

public class ConfigurationManager {
    private let plistManager = PlistManager.shared
    
    public init() {}
    
    public func createConfiguration(
        type: ConfigurationType,
        content: ConfigurationContent
    ) -> [String: Any] {
        var config: [String: Any] = [
            "Content": createContentDictionary(for: content),
            "LastSet": Date(),
            "LastUse": Date()
        ]
        
        if type == .desktop {
            config["Type"] = "individual"
        }
        
        return config
    }
    
    private func createContentDictionary(for content: ConfigurationContent) -> [String: Any] {
        var contentDict: [String: Any] = [
            "Choices": [
                [
                    "Configuration": content.configuration,
                    "Files": content.files ?? [],
                    "Provider": content.provider
                ]
            ]
        ]
        
        if let encodedOptions = content.encodedOptionValues {
            contentDict["EncodedOptionValues"] = encodedOptions
        }
        
        if let shuffle = content.shuffle {
            contentDict["Shuffle"] = shuffle
        }
        // Don't add Shuffle key if it's nil to avoid NSNull issues
        // The system will handle the default value
        
        return contentDict
    }
    
    public func updatePlistSection(
        at path: String,
        keyPath: [String],
        with value: Any
    ) throws -> [String: Any] {
        guard let plist = try? plistManager.read(at: path) else {
            throw PaperSaverError.plistReadError(path)
        }
        
        var current: Any = plist
        var containers: [(Any, String)] = []
        
        for (index, key) in keyPath.enumerated() {
            if index == keyPath.count - 1 {
                if var dict = current as? [String: Any] {
                    dict[key] = value
                    current = dict
                }
            } else {
                containers.append((current, key))
                if let dict = current as? [String: Any] {
                    if let next = dict[key] {
                        current = next
                    } else {
                        current = [String: Any]()
                    }
                }
            }
        }
        
        for (container, key) in containers.reversed() {
            if var dict = container as? [String: Any] {
                dict[key] = current
                current = dict
            }
        }
        
        return current as? [String: Any] ?? plist
    }
    
    public func restartWallpaperAgent() {
        let task = Process()
        task.launchPath = "/usr/bin/killall"
        task.arguments = ["WallpaperAgent"]
        task.launch()
    }
}

public enum ConfigurationType {
    case idle
    case desktop
}

public struct ConfigurationContent {
    let configuration: Data
    let files: [String]?
    let provider: String
    let encodedOptionValues: Data?
    let shuffle: Bool?
    
    public init(
        configuration: Data,
        files: [String]? = nil,
        provider: String,
        encodedOptionValues: Data? = nil,
        shuffle: Bool? = nil
    ) {
        self.configuration = configuration
        self.files = files
        self.provider = provider
        self.encodedOptionValues = encodedOptionValues
        self.shuffle = shuffle
    }
}