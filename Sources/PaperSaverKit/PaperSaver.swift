import Foundation
import AppKit

/// Settings for a `PaperSaver` instance.
public struct PaperSaverConfiguration: Sendable {
    /// The store to read and write. Defaults to the current user's.
    public var storeURL: URL = SystemPaths.wallpaperStoreURL
    /// How writes restart the agent and verify the result.
    public var writeOptions: WriteOptions = .default
    public var log: PaperSaverLog = .os
    /// How long a pluginkit listing is reused.
    public var pluginkitCacheTTL: Duration = .seconds(5)
    /// How a screensaver-only write represents the missing desktop choice.
    public var screensaverOnlyStrategy: ScreensaverOnlyStrategy = .automatic
    /// Refuse `setWallpaperExtension` for a bundle identifier that is not registered on the
    /// `com.apple.wallpaper` extension point. The agent stores any provider string without
    /// complaint and then fails to render it ("no provider found"), so the check runs first.
    public var validatesWallpaperExtensions = true
    /// The choice written to clear a slot. Injectable for tests and for callers with their own
    /// idea of a default.
    public var systemDefault: SystemDefaultProvider = SystemDefaults.slot

    public init() {}
}

/// A display, for reads and for `NSWorkspace` writes.
public enum DisplayTarget: Sendable, Equatable {
    /// Every connected display; for reads, the store's shared sections.
    case all
    case main
    case uuid(String)
    case displayID(CGDirectDisplayID)

    @MainActor
    public init(screen: NSScreen) {
        if let identifier = ScreenIdentifier(from: screen) {
            self = .displayID(identifier.displayID)
        } else {
            self = .main
        }
    }

    /// The display UUID, or `nil` for `.all` and for a display that is not connected.
    public var uuid: String? {
        switch self {
        case .all: return nil
        case .main: return DisplayUUID.main
        case .uuid(let uuid): return uuid
        case .displayID(let id): return DisplayUUID.uuid(for: id)
        }
    }

    var storeTarget: StoreTarget {
        uuid.map { .display(uuid: $0) } ?? .everywhere
    }
}

/// The library's entry point.
///
/// Reads are synchronous and only touch the store file. Writes rewrite the store, restart
/// `WallpaperAgent` (which reads the store only at launch), wait for it to settle, read the
/// store back and roll back when the agent did not keep the change.
public final class PaperSaver: Sendable {
    public let configuration: PaperSaverConfiguration
    let file: StoreFile
    let agent: any WallpaperAgentControlling
    let catalog: PluginkitCatalog
    let wallpaperCatalog: PluginkitCatalog

    public convenience init(configuration: PaperSaverConfiguration = PaperSaverConfiguration()) {
        self.init(configuration: configuration, agent: WallpaperAgent())
    }

    init(configuration: PaperSaverConfiguration, agent: any WallpaperAgentControlling) {
        self.configuration = configuration
        self.file = StoreFile(url: configuration.storeURL)
        self.agent = agent
        self.catalog = PluginkitCatalog(ttl: configuration.pluginkitCacheTTL)
        self.wallpaperCatalog = PluginkitCatalog(extensionPoint: PluginkitCatalog.wallpaperExtensionPoint, ttl: configuration.pluginkitCacheTTL)
    }

    private var log: PaperSaverLog { configuration.log }
    private var writer: StoreWriter { StoreWriter(file: file, agent: agent, log: log) }

    // MARK: - Discovery

    /// Every screensaver installed on the Mac: app extensions registered with pluginkit and
    /// `.saver` plug-ins in the standard directories.
    public func listAvailableScreensavers() async -> [ScreensaverModule] {
        var modules: [ScreensaverModule] = []
        if let extensions = try? await catalog.extensions() {
            for ext in extensions where !ext.bundleIdentifier.contains("legacyScreenSaver") {
                modules.append(ScreensaverModule(
                    name: ext.displayName, identifier: ext.path.lastPathComponent, path: ext.path,
                    type: .appExtension, isSystem: ext.isSystem, bundleIdentifier: ext.bundleIdentifier))
            }
        }
        modules.append(contentsOf: Self.traditionalScreensavers())
        return modules
    }

    static func traditionalScreensavers() -> [ScreensaverModule] {
        var modules: [ScreensaverModule] = []
        for directory in SystemPaths.screensaverModulesDirectories() {
            guard let enumerator = FileManager.default.enumerator(
                at: directory, includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles, .skipsPackageDescendants]) else { continue }
            for case let url as URL in enumerator where url.pathExtension.lowercased() == "saver" {
                if url.path.contains("Default Collections") { continue }
                modules.append(ScreensaverModule(
                    name: url.deletingPathExtension().lastPathComponent, identifier: url.lastPathComponent,
                    path: url, type: .traditional, isSystem: url.path.hasPrefix("/System/")))
            }
        }
        return modules
    }

    // MARK: - Reading the store

    /// The whole store, typed.
    public func readStore() throws -> WallpaperStore {
        try file.read()
    }

    /// The names of the screensavers selected anywhere in the store, sorted. A name is the
    /// module's file name without extension, or a wallpaper extension's bundle identifier.
    public func getActiveScreensavers() -> [String] {
        ((try? file.read())?.screensaverNames() ?? []).sorted()
    }

    /// The screensaver selected for `target`.
    public func activeScreensaver(in target: StoreTarget = .everywhere) -> ScreensaverInfo? {
        guard let slot = (try? file.read())?.slot(.screensaver, in: target) else { return nil }
        var displayUUID: String?
        if case .display(let uuid) = target { displayUUID = uuid }
        return ScreensaverInfo(slot: slot, displayUUID: displayUUID)
    }

    /// The screensaver selected for a display, or for the store's shared sections with `.all`.
    public func getActiveScreensaver(for display: DisplayTarget = .all) -> ScreensaverInfo? {
        activeScreensaver(in: display.storeTarget)
    }

    /// The choice in `slot` for `target`.
    public func currentWallpaperChoice(slot: WallpaperSlot, in target: StoreTarget = .everywhere) -> SlotConfiguration? {
        (try? file.read())?.slot(slot, in: target)
    }

    /// The bundle identifier of the wallpaper extension set as the desktop wallpaper, or `nil`
    /// when the desktop is not a third-party extension.
    public func getCurrentWallpaperExtension(in target: StoreTarget = .everywhere) -> String? {
        extensionProvider(slot: .desktop, in: target)
    }

    /// The bundle identifier of the wallpaper extension set as the screensaver, or `nil`.
    public func getCurrentScreensaverExtension(in target: StoreTarget = .everywhere) -> String? {
        extensionProvider(slot: .screensaver, in: target)
    }

    private func extensionProvider(slot: WallpaperSlot, in target: StoreTarget) -> String? {
        guard let provider = (try? file.read())?.provider(of: slot, in: target), provider.isThirdPartyExtension else { return nil }
        return provider.rawValue
    }

    // MARK: - Screensavers

    /// Selects a `.saver` or app-extension screensaver by name (its bundle's file name without
    /// extension) for `target`, leaving the desktop wallpaper alone.
    @discardableResult
    public func setScreensaver(module: String, target: StoreTarget = .everywhere, options: WriteOptions? = nil) async throws -> WriteOutcome {
        guard let moduleURL = await ModuleLocator.locate(module: module, catalog: catalog) else {
            throw PaperSaverError.screensaverNotFound(module)
        }
        let choice = SlotConfiguration(
            choice: try WallpaperChoice(provider: .screenSaver, configuration: .screenSaver(moduleURL: moduleURL)),
            optionValues: .null, shuffle: .null)
        let strategy = configuration.screensaverOnlyStrategy
        let systemDefault = configuration.systemDefault
        let topology = Self.topology(for: target)
        let modulePath = moduleURL.path
        return try await writer.apply(
            expectation: "screensaver \(module) in \(target)",
            options: options ?? configuration.writeOptions,
            edit: { try $0.setting(.screensaver, to: choice, in: target, otherSlot: .keep, strategy: strategy,
                                   systemDefault: systemDefault, topology: topology) },
            verify: { store in
                if case .screenSaver(let url)? = store.slot(.screensaver, in: target)?.configuration { return url.path == modulePath }
                return false
            })
    }

    /// Selects a screensaver by name for every display and Space.
    public func setScreensaverEverywhere(module: String, skipRestart: Bool = false) async throws {
        try await setScreensaver(module: module, target: .everywhere, options: skipRestart ? .noRestart : nil)
    }

    // MARK: - Wallpaper extensions

    /// Puts a wallpaper extension (an app extension on the `com.apple.wallpaper` extension
    /// point) in `slot`, identified by its bundle identifier.
    ///
    /// - Parameters:
    ///   - configuration: the opaque token the extension expects in its choice configuration.
    ///   - otherSlot: what happens to the other slot. The default, `.keep`, never touches it:
    ///     setting the screensaver leaves the wallpaper alone and vice versa. The clear
    ///     policies are explicit opt-ins.
    ///   - optionValues: the desktop slot needs a placement and a background colour or the agent
    ///     rejects the choice; the default supplies both. The screensaver slot defaults to none.
    ///
    /// A desktop write also waits for the extension's process after the restart and restarts
    /// the agent once more if it did not appear (`WriteOptions.extensionLaunchTimeout`,
    /// `extensionRelaunchAttempts`); the outcome says whether it is running.
    @discardableResult
    public func setWallpaperExtension(
        bundleID: String,
        configuration token: Data = Data(),
        slot: WallpaperSlot,
        otherSlot: OtherSlotPolicy = .keep,
        optionValues: OptionValues? = nil,
        target: StoreTarget = .everywhere,
        options: WriteOptions? = nil
    ) async throws -> WriteOutcome {
        try await validateWallpaperExtension(bundleID)
        let provider = ChoiceProvider(rawValue: bundleID)
        let choice = Self.extensionChoice(provider: provider, token: token, slot: slot, optionValues: optionValues)
        let strategy = configuration.screensaverOnlyStrategy
        let systemDefault = configuration.systemDefault
        let topology = Self.topology(for: target)
        return try await writer.apply(
            expectation: "\(bundleID) as \(slot) in \(target)",
            options: options ?? configuration.writeOptions,
            expectedExtension: slot == .desktop ? bundleID : nil,
            edit: { try $0.setting(slot, to: choice, in: target, otherSlot: otherSlot, strategy: strategy,
                                   systemDefault: systemDefault, topology: topology) },
            verify: { store in
                guard store.provider(of: slot, in: target) == provider else { return false }
                let other = store.provider(of: slot.other, in: target)
                switch otherSlot {
                case .keep: return true
                case .mirror: return other == provider
                case .clearIfSameProvider, .clearToSystemDefault: return other != provider
                }
            })
    }

    /// Puts a wallpaper extension in several slots with one store write and one agent restart,
    /// typically `[.desktop, .screensaver]`.
    ///
    /// Each slot gets the option values it needs: a placement and a background colour for the
    /// desktop, none for the screensaver. (`otherSlot: .mirror` would copy the desktop's
    /// placement into the screensaver slot, which an extension may read as "not a screensaver".)
    @discardableResult
    public func setWallpaperExtension(
        bundleID: String,
        configuration token: Data = Data(),
        slots: Set<WallpaperSlot>,
        target: StoreTarget = .everywhere,
        options: WriteOptions? = nil
    ) async throws -> WriteOutcome {
        guard !slots.isEmpty else {
            throw PaperSaverError.invalidConfiguration("no slot to write")
        }
        try await validateWallpaperExtension(bundleID)
        let provider = ChoiceProvider(rawValue: bundleID)
        let ordered = WallpaperSlot.allCases.filter(slots.contains)
        let choices = ordered.map { ($0, Self.extensionChoice(provider: provider, token: token, slot: $0, optionValues: nil)) }
        let strategy = configuration.screensaverOnlyStrategy
        let systemDefault = configuration.systemDefault
        let topology = Self.topology(for: target)
        return try await writer.apply(
            expectation: "\(bundleID) as \(ordered.map(\.rawValue).joined(separator: " + ")) in \(target)",
            options: options ?? configuration.writeOptions,
            expectedExtension: slots.contains(.desktop) ? bundleID : nil,
            edit: { store in
                var store = store
                for (slot, choice) in choices {
                    store = try store.setting(slot, to: choice, in: target, otherSlot: .keep, strategy: strategy,
                                              systemDefault: systemDefault, topology: topology)
                }
                return store
            },
            verify: { store in ordered.allSatisfy { store.provider(of: $0, in: target) == provider } })
    }

    /// Throws when `bundleID` is empty or, with validation on, not a registered wallpaper extension.
    private func validateWallpaperExtension(_ bundleID: String) async throws {
        guard !bundleID.isEmpty else {
            throw PaperSaverError.invalidConfiguration("the extension bundle identifier is empty")
        }
        guard configuration.validatesWallpaperExtensions else { return }
        let wallpaper = (try? await wallpaperCatalog.extensions()) ?? []
        let screensavers = (try? await catalog.extensions()) ?? []
        if let error = Self.wallpaperExtensionError(bundleID: bundleID, wallpaperExtensions: wallpaper, screensaverExtensions: screensavers) {
            throw error
        }
    }

    /// The slot value for a wallpaper extension: the desktop defaults to a placement plus a
    /// background colour (the agent rejects a desktop choice without them), the screensaver to
    /// no option values.
    static func extensionChoice(provider: ChoiceProvider, token: Data, slot: WallpaperSlot, optionValues: OptionValues?) -> SlotConfiguration {
        SlotConfiguration(
            choice: WallpaperChoice(provider: provider, configuration: token),
            optionValues: .values(optionValues ?? (slot == .desktop ? .image() : .empty)), shuffle: .null)
    }

    /// Replaces the choice in `slot` with the system default, which removes a wallpaper
    /// extension from that slot.
    @discardableResult
    public func clearWallpaperExtension(slot: WallpaperSlot, target: StoreTarget = .everywhere, options: WriteOptions? = nil) async throws -> WriteOutcome {
        let strategy = configuration.screensaverOnlyStrategy
        let systemDefault = configuration.systemDefault
        let expected = try systemDefault(slot).provider
        let topology = Self.topology(for: target)
        return try await writer.apply(
            expectation: "system default as \(slot) in \(target)",
            options: options ?? configuration.writeOptions,
            edit: { try $0.clearing(slot, in: target, strategy: strategy, systemDefault: systemDefault, topology: topology) },
            verify: { $0.provider(of: slot, in: target) == expected })
    }

    /// Moves the background colour PaperSaver 0.3.1 and earlier wrote one level too deep to
    /// the path WallpaperAgent reads, in every slot of every section.
    ///
    /// With the old shape the agent cannot decode the slot's option values ("Failed to decode
    /// option values for wallpaper", Cocoa error 4865) and treats the desktop as having no
    /// placement. Choices are not changed. Returns `nil` without writing or restarting the
    /// agent when the store has nothing to repair.
    @discardableResult
    public func repairLegacyOptionValues(options: WriteOptions? = nil) async throws -> WriteOutcome? {
        let current = try file.read()
        let count = current.repairingLegacyOptionValues().repairedSlots
        guard count > 0 else { return nil }
        let desktop = current.provider(of: .desktop)
        let screensaver = current.provider(of: .screensaver)
        return try await writer.apply(
            expectation: "\(count) legacy background colour(s) repaired",
            options: options ?? configuration.writeOptions,
            expectedExtension: desktop.flatMap { $0.isThirdPartyExtension ? $0.rawValue : nil },
            edit: { $0.repairingLegacyOptionValues().store },
            verify: { store in
                store.repairingLegacyOptionValues().repairedSlots == 0
                    && store.provider(of: .desktop) == desktop
                    && store.provider(of: .screensaver) == screensaver
            })
    }

    /// The wallpaper extensions registered with pluginkit (`com.apple.wallpaper` extension point),
    /// Apple's included.
    public func listWallpaperExtensions() async throws -> [PluginkitExtension] {
        try await wallpaperCatalog.extensions()
    }

    /// Why `bundleID` cannot be written as a wallpaper extension, or `nil` when it can.
    ///
    /// The identifier must belong to a registered wallpaper extension. When it names a
    /// screensaver extension instead (by bundle identifier or by file name), the error says to
    /// use `setScreensaver(module:)`.
    public static func wallpaperExtensionError(
        bundleID: String,
        wallpaperExtensions: [PluginkitExtension],
        screensaverExtensions: [PluginkitExtension]
    ) -> PaperSaverError? {
        if wallpaperExtensions.contains(where: { $0.bundleIdentifier == bundleID }) { return nil }
        if let saver = screensaverExtensions.first(where: { $0.bundleIdentifier == bundleID || $0.displayName == bundleID }) {
            return .wallpaperExtensionNotFound(
                bundleID: bundleID,
                hint: "\(saver.bundleIdentifier) is a screensaver extension (com.apple.screensaver); select it with setScreensaver(module: \"\(saver.displayName)\") or `papersaver set-saver \(saver.displayName)`")
        }
        if let byName = wallpaperExtensions.first(where: { $0.displayName == bundleID }) {
            return .wallpaperExtensionNotFound(bundleID: bundleID, hint: "Did you mean the bundle identifier \(byName.bundleIdentifier)?")
        }
        return .wallpaperExtensionNotFound(bundleID: bundleID, hint: nil)
    }

    // MARK: - Static images

    /// Sets a static image as the desktop wallpaper through `NSWorkspace`, which applies it at
    /// once without restarting the agent.
    @MainActor
    public func setWallpaper(imageURL: URL, on display: DisplayTarget = .all, placement: WallpaperPlacement = .fill, fillColor: NSColor? = nil) throws {
        guard FileManager.default.fileExists(atPath: imageURL.path) else {
            throw PaperSaverError.fileNotFound(imageURL)
        }
        var options = placement.workspaceOptions
        if let fillColor { options[.fillColor] = fillColor }
        for screen in try Self.screens(for: display) {
            try NSWorkspace.shared.setDesktopImageURL(imageURL, for: screen, options: options)
        }
    }

    /// The static image on a display, as `NSWorkspace` reports it. `nil` when the display is
    /// not connected or its wallpaper is not an image file.
    @MainActor
    public func getCurrentWallpaper(for display: DisplayTarget = .main) -> WallpaperInfo? {
        guard let screen = try? Self.screens(for: display).first,
              let url = NSWorkspace.shared.desktopImageURL(for: screen) else { return nil }
        let options = NSWorkspace.shared.desktopImageOptions(for: screen) ?? [:]
        return WallpaperInfo(imageURL: url, placement: WallpaperPlacement(workspaceOptions: options),
                             displayUUID: ScreenIdentifier(from: screen)?.uuid)
    }

    /// Writes a static image into the store for `target`. Use this only for Spaces that are not
    /// on screen; `setWallpaper(imageURL:on:placement:fillColor:)` is the supported path.
    @discardableResult
    public func setWallpaper(imageURL: URL, target: StoreTarget, optionValues: OptionValues = .image(), options: WriteOptions? = nil) async throws -> WriteOutcome {
        guard FileManager.default.fileExists(atPath: imageURL.path) else {
            throw PaperSaverError.fileNotFound(imageURL)
        }
        let choice = SlotConfiguration(
            choice: try WallpaperChoice(provider: .image, configuration: .imageFile(imageURL)),
            optionValues: .values(optionValues), shuffle: .null)
        let systemDefault = configuration.systemDefault
        let topology = Self.topology(for: target)
        let imagePath = imageURL.path
        return try await writer.apply(
            expectation: "image \(imageURL.lastPathComponent) in \(target)",
            options: options ?? configuration.writeOptions,
            edit: { try $0.setting(.desktop, to: choice, in: target, otherSlot: .keep, systemDefault: systemDefault, topology: topology) },
            verify: { store in
                if case .imageFile(let url)? = store.slot(.desktop, in: target)?.configuration { return url.path == imagePath }
                return false
            })
    }

    @MainActor
    static func screens(for display: DisplayTarget) throws -> [NSScreen] {
        switch display {
        case .all:
            return NSScreen.screens
        case .main:
            guard let main = NSScreen.main else { throw PaperSaverError.displayNotFound("main") }
            return [main]
        case .uuid(let uuid):
            guard let id = DisplayUUID.displayID(for: uuid),
                  let screen = NSScreen.screens.first(where: { ScreenIdentifier(from: $0)?.displayID == id }) else {
                throw PaperSaverError.displayNotFound(uuid)
            }
            return [screen]
        case .displayID(let id):
            guard let screen = NSScreen.screens.first(where: { ScreenIdentifier(from: $0)?.displayID == id }) else {
                throw PaperSaverError.displayNotFound(String(id))
            }
            return [screen]
        }
    }

    // MARK: - Idle time

    /// Seconds of inactivity before the screensaver starts; 0 means never.
    public func getIdleTime() -> Int {
        IdleTime.seconds()
    }

    public func setIdleTime(seconds: Int) throws {
        try IdleTime.set(seconds: seconds)
    }

    // MARK: - Display sleep

    /// Minutes before the display turns off on the current power source; 0 means never,
    /// `nil` means unknown. Read-only: changing it needs root.
    public func getDisplaySleep() async -> Int? {
        await DisplaySleep.minutes()
    }

    // MARK: - Displays and Spaces

    /// The connected displays and their Spaces.
    public func displaySpaces() -> [DisplaySpaces] {
        DisplayTopology.snapshot().displays
    }

    /// Every display the window server remembers, connected ones first.
    @MainActor
    public func listDisplays() -> [DisplayInfo] {
        let configs = WindowServerDisplays.displays()
        var uuids = WindowServerDisplays.knownDisplayUUIDs()
        for id in DisplayTopology.connectedDisplayIDs() {
            if let uuid = DisplayUUID.uuid(for: id) { uuids.insert(uuid) }
        }
        let screens = NSScreen.screens
        var displays: [DisplayInfo] = []
        for uuid in uuids {
            let config = configs.first { $0.uuid == uuid }
            let displayID = DisplayUUID.displayID(for: uuid)
            let screen = displayID.flatMap { id in screens.first { ScreenIdentifier(from: $0)?.displayID == id } }
            displays.append(DisplayInfo(
                uuid: uuid, displayID: displayID, frame: screen?.frame,
                isMain: screen != nil && screen == NSScreen.main, isConnected: displayID != nil,
                resolution: config?.resolution, refreshRate: config?.refreshRate, scale: config?.scale,
                configVersion: config?.configVersion, displayName: screen?.localizedName))
        }
        return displays.sorted {
            if $0.isConnected != $1.isConnected { return $0.isConnected }
            return $0.uuid < $1.uuid
        }
    }

    /// The Spaces known to the store and to Mission Control.
    public func listSpaces(includeHistorical: Bool = false) -> [SpaceInfo] {
        let store = try? file.read()
        let missionControl = MissionControlSpaces.spaces()
        let topology = DisplayTopology.snapshot()
        let current = Set(topology.displays.compactMap(\.currentSpaceUUID))
        var spaces: [SpaceInfo] = []

        for (uuid, entry) in store?.spaces ?? [:] {
            let mcSpace = missionControl.first { $0.uuid == uuid }
            let isHistorical = mcSpace?.isHistorical ?? (mcSpace == nil && !uuid.isEmpty && topology.displayUUIDs(ofSpace: uuid).isEmpty)
            if isHistorical && !includeHistorical { continue }
            var displayUUIDs = entry.displays.keys.sorted()
            if displayUUIDs.isEmpty { displayUUIDs = topology.displayUUIDs(ofSpace: uuid) }
            spaces.append(SpaceInfo(
                uuid: uuid, displayUUIDs: displayUUIDs, spaceID: mcSpace?.spaceID,
                displayIdentifier: mcSpace?.displayIdentifier,
                isCurrent: current.contains(uuid) || (mcSpace?.isCurrent ?? false), isHistorical: isHistorical))
        }
        for mcSpace in missionControl where !spaces.contains(where: { $0.uuid == mcSpace.uuid }) {
            if mcSpace.isHistorical && !includeHistorical { continue }
            spaces.append(SpaceInfo(
                uuid: mcSpace.uuid, displayUUIDs: topology.displayUUIDs(ofSpace: mcSpace.uuid),
                spaceID: mcSpace.spaceID, displayIdentifier: mcSpace.displayIdentifier,
                isCurrent: current.contains(mcSpace.uuid) || mcSpace.isCurrent, isHistorical: mcSpace.isHistorical))
        }
        return spaces.sorted { a, b in
            if (a.displayIdentifier == "Main") != (b.displayIdentifier == "Main") { return a.displayIdentifier == "Main" }
            if let x = a.spaceID, let y = b.spaceID, x != y { return x < y }
            return a.uuid < b.uuid
        }
    }

    /// The Space on screen, preferring the main display's.
    public func getActiveSpace() -> SpaceInfo? {
        let spaces = listSpaces()
        return spaces.first { $0.isCurrent } ?? spaces.first { $0.uuid.isEmpty }
    }

    public func getSpaceByID(_ spaceID: Int) -> SpaceInfo? {
        listSpaces(includeHistorical: true).first { $0.spaceID == spaceID }
    }

    static func topology(for target: StoreTarget) -> DisplayTopologySnapshot? {
        if case .display = target { return DisplayTopology.snapshot() }
        return nil
    }

    // MARK: - Backup

    /// The `.backup` file next to the store, refreshed by every write.
    public func backupInfo() -> BackupInfo? {
        file.backupInfo()
    }

    /// Copies the backup over the store and, by default, restarts the agent so it applies.
    public func restoreFromBackup(restartAgent: Bool = true) async throws {
        try file.restoreFromBackupFile()
        log.info("restored \(file.backupURL.lastPathComponent)")
        if restartAgent {
            try await agent.restart()
        }
    }
}

/// Library identity.
public enum PaperSaverKitInfo {
    public static let version = "0.4.3"
}
