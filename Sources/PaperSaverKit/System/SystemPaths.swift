import Foundation

/// Where the system keeps the wallpaper store and screensaver modules.
public enum SystemPaths {
    /// `~/Library/Application Support/com.apple.wallpaper/Store/Index.plist`.
    public static var wallpaperStoreURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/com.apple.wallpaper/Store/Index.plist")
    }

    /// `wallpaperStoreURL` as a path string.
    public static var wallpaperIndexPath: String { wallpaperStoreURL.path }

    /// The directories that can hold `.saver` plug-ins and Apple's app-extension screensavers,
    /// limited to the ones that exist.
    public static func screensaverModulesDirectories() -> [URL] {
        var directories = [
            URL(fileURLWithPath: "/System/Library/Screen Savers"),
            URL(fileURLWithPath: "/Library/Screen Savers"),
            URL(fileURLWithPath: "/System/Library/ExtensionKit/Extensions"),
        ]
        if let userLibrary = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask).first {
            directories.append(userLibrary.appendingPathComponent("Screen Savers"))
        }
        return directories.filter { FileManager.default.fileExists(atPath: $0.path) }
    }

    /// The `.saver` or `.appex` bundle named `moduleName` in the standard directories, if any.
    public static func screensaverModuleURL(inStandardDirectories moduleName: String) -> URL? {
        for directory in screensaverModulesDirectories() {
            for ext in ["saver", "appex"] {
                let url = directory.appendingPathComponent("\(moduleName).\(ext)")
                if FileManager.default.fileExists(atPath: url.path) { return url }
            }
        }
        return nil
    }
}

/// Resolves a screensaver module name to its bundle.
public enum ModuleLocator {
    /// The standard directories first, then the pluginkit registry, which also covers
    /// third-party app extensions living inside their app bundle.
    public static func locate(module name: String, catalog: PluginkitCatalog) async -> URL? {
        if let url = SystemPaths.screensaverModuleURL(inStandardDirectories: name) { return url }
        return try? await catalog.find(byName: name)?.path
    }
}
