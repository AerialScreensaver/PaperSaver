import Foundation
import AppKit
import CoreGraphics

public struct WindowServerDisplayConfig {
    public let uuid: String
    public let resolution: CGSize
    public let refreshRate: Int
    public let position: CGPoint
    public let scale: Int
    public let depth: Int
    public let configVersion: Int
    public let isInCurrentConfig: Bool
    
    public init(
        uuid: String,
        resolution: CGSize,
        refreshRate: Int,
        position: CGPoint = .zero,
        scale: Int = 1,
        depth: Int = 8,
        configVersion: Int = 0,
        isInCurrentConfig: Bool = false
    ) {
        self.uuid = uuid
        self.resolution = resolution
        self.refreshRate = refreshRate
        self.position = position
        self.scale = scale
        self.depth = depth
        self.configVersion = configVersion
        self.isInCurrentConfig = isInCurrentConfig
    }
    
    public var displayDescription: String {
        let scaleText = scale > 1 ? " @ \(scale)x" : ""
        return "\(Int(resolution.width))x\(Int(resolution.height)) @ \(refreshRate)Hz\(scaleText)"
    }
}

@available(macOS 14.0, *)
public final class WindowServerDisplayManager: @unchecked Sendable {
    public static let shared = WindowServerDisplayManager()
    
    private init() {}
    
    public func getWindowServerDisplays() -> [WindowServerDisplayConfig] {
        guard let displaySets = readWindowServerPreferences() else {
            return []
        }
        
        return parseDisplayConfigurations(displaySets)
    }
    
    public func getCurrentlyConnectedDisplays() -> [WindowServerDisplayConfig] {
        return getWindowServerDisplays().filter { $0.isInCurrentConfig }
    }
    
    public func getHistoricalDisplays() -> [WindowServerDisplayConfig] {
        return getWindowServerDisplays().filter { !$0.isInCurrentConfig }
    }
    
    public func getAllKnownDisplayUUIDs() -> Set<String> {
        guard let displaySets = readWindowServerPreferences(),
              let underscan = displaySets["Underscan"] as? [String: Any] else {
            return Set()
        }
        
        return Set(underscan.keys)
    }
    
    public func getDisplayConfig(for uuid: String) -> WindowServerDisplayConfig? {
        return getWindowServerDisplays().first { $0.uuid == uuid }
    }
    
    private func readWindowServerPreferences() -> [String: Any]? {
        guard let displaySetsData = CFPreferencesCopyValue(
            "DisplaySets" as CFString,
            "com.apple.windowserver.displays" as CFString,
            kCFPreferencesCurrentUser,
            kCFPreferencesCurrentHost
        ) as? [String: Any] else {
            return nil
        }
        
        return displaySetsData
    }
    
    private func parseDisplayConfigurations(_ displaySets: [String: Any]) -> [WindowServerDisplayConfig] {
        guard let configs = displaySets["Configs"] as? [[String: Any]] else {
            return []
        }
        
        var displayConfigs: [WindowServerDisplayConfig] = []
        
        // Find the current configuration (highest ConfigVersion)
        let currentConfig = configs.first { ($0["ConfigVersion"] as? Int) == 1 }
        var currentDisplayUUIDs = Set<String>()
        
        if let current = currentConfig,
           let displayConfig = current["DisplayConfig"] as? [[String: Any]] {
            currentDisplayUUIDs = Set(displayConfig.compactMap { $0["UUID"] as? String })
        }
        
        // Process all configurations to build comprehensive display list
        var processedUUIDs = Set<String>()
        
        for (configIndex, config) in configs.enumerated() {
            guard let displayConfig = config["DisplayConfig"] as? [[String: Any]],
                  let configVersion = config["ConfigVersion"] as? Int else {
                continue
            }
            
            for display in displayConfig {
                guard let uuid = display["UUID"] as? String,
                      let currentInfo = display["CurrentInfo"] as? [String: Any],
                      let width = currentInfo["Wide"] as? Int,
                      let height = currentInfo["High"] as? Int,
                      let hz = currentInfo["Hz"] as? Int,
                      let scale = currentInfo["Scale"] as? Int,
                      let depth = currentInfo["Depth"] as? Int else {
                    continue
                }
                
                // Skip if we've already processed this UUID with current config
                if processedUUIDs.contains(uuid) {
                    continue
                }
                
                let originX = (currentInfo["OriginX"] as? String).flatMap { Int($0) } ?? (currentInfo["OriginX"] as? Int) ?? 0
                let originY = (currentInfo["OriginY"] as? String).flatMap { Int($0) } ?? (currentInfo["OriginY"] as? Int) ?? 0
                
                let displayConfig = WindowServerDisplayConfig(
                    uuid: uuid,
                    resolution: CGSize(width: width, height: height),
                    refreshRate: hz,
                    position: CGPoint(x: originX, y: originY),
                    scale: scale,
                    depth: depth,
                    configVersion: configVersion,
                    isInCurrentConfig: currentDisplayUUIDs.contains(uuid)
                )
                
                displayConfigs.append(displayConfig)
                
                // Mark as processed if this is from current config
                if currentDisplayUUIDs.contains(uuid) {
                    processedUUIDs.insert(uuid)
                }
            }
        }
        
        return displayConfigs.sorted { first, second in
            // Current config displays first
            if first.isInCurrentConfig && !second.isInCurrentConfig {
                return true
            }
            if second.isInCurrentConfig && !first.isInCurrentConfig {
                return false
            }
            
            // Then by UUID
            return first.uuid < second.uuid
        }
    }
}