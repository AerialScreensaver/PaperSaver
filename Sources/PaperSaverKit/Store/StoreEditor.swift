import Foundation

/// What happens to the slot that is not being written.
public enum OtherSlotPolicy: Sendable, Equatable {
    /// Leave it as it is. A `Linked` choice is materialised into it; if it is still missing
    /// after a desktop write, the system default fills it (an individual section needs both).
    case keep
    /// Replace it with the system default choice.
    case clearToSystemDefault
    /// Replace it with the system default only when it holds the same provider as the choice
    /// being written. This keeps a wallpaper extension out of both slots at once.
    case clearIfSameProvider
    /// Copy the choice being written into it. Not recommended for wallpaper extensions on
    /// macOS 26 and later, where the same extension in both slots conflates the two modes.
    case mirror
}

/// How a screensaver-only write represents the missing desktop choice.
///
/// Measured on macOS 27.2: a store whose sections hold only `Idle` slots is reset by the agent
/// to the "nothing set" placeholder, wiping the screensaver. A `Type = idle` section is kept
/// when another section provides the desktop (the agent writes that shape itself when desktops
/// are per Space), and an `individual` section with the system default in `Desktop` is kept
/// everywhere.
public enum ScreensaverOnlyStrategy: Sendable, Equatable {
    /// `idleSection` when some other section of the store already has a desktop choice,
    /// `materializeSystemDefaultDesktop` otherwise. The default.
    case automatic
    /// Write a `Type = idle` section holding only the `Idle` slot; the desktop then comes from
    /// a lower-precedence section. Rejected by the agent when no section has a desktop.
    case idleSection
    /// Write an `individual` section with the system default wallpaper in `Desktop`.
    case materializeSystemDefaultDesktop
}

/// Produces the system default choice for a slot. Injectable so tests do not depend on the
/// running macOS.
public typealias SystemDefaultProvider = @Sendable (WallpaperSlot) throws -> SlotConfiguration

extension WallpaperStore {
    // MARK: Writing

    /// Returns a copy of the store with `configuration` in `slot` of every section `target`
    /// covers.
    ///
    /// - Parameters:
    ///   - otherSlot: what happens to the slot not being written.
    ///   - strategy: how a screensaver-only section is represented when no desktop choice exists.
    ///   - systemDefault: the choice used to fill or clear a slot.
    ///   - topology: needed for `.display` targets to find the Spaces on that display; without
    ///     it only the per-Space sections already present for that display are updated.
    public func setting(
        _ slot: WallpaperSlot,
        to configuration: SlotConfiguration,
        in target: StoreTarget = .everywhere,
        otherSlot: OtherSlotPolicy = .keep,
        strategy requestedStrategy: ScreensaverOnlyStrategy = .automatic,
        systemDefault: SystemDefaultProvider = SystemDefaults.slot,
        topology: DisplayTopologySnapshot? = nil
    ) throws -> WallpaperStore {
        var store = self
        var strategy = requestedStrategy
        if strategy == .automatic {
            strategy = hasAnyDesktopChoice ? .idleSection : .materializeSystemDefaultDesktop
        }
        func apply(_ section: StoreSection?) throws -> StoreSection {
            try Self.applying(slot, configuration, to: section, otherSlot: otherSlot, strategy: strategy, systemDefault: systemDefault)
        }

        switch target {
        case .everywhere:
            store.allSpacesAndDisplays = try apply(store.allSpacesAndDisplays)
            store.systemDefault = try apply(store.systemDefault)
            for (uuid, entry) in store.spaces {
                var entry = entry
                if entry.default != nil { entry.default = try apply(entry.default) }
                for (displayUUID, section) in entry.displays {
                    entry.displays[displayUUID] = try apply(section)
                }
                store.spaces[uuid] = entry
            }
            for (uuid, section) in store.displays {
                store.displays[uuid] = try apply(section)
            }

        case .space(let uuid):
            var entry = store.spaces[uuid] ?? SpaceEntry()
            entry.default = try apply(entry.default)
            for (displayUUID, section) in entry.displays {
                entry.displays[displayUUID] = try apply(section)
            }
            store.spaces[uuid] = entry

        case .display(let uuid):
            store.displays[uuid] = try apply(store.displays[uuid])
            let spaceUUIDs = topology?.spaceUUIDs(onDisplay: uuid)
                ?? store.spaces.filter { $0.value.displays[uuid] != nil }.map(\.key)
            for spaceUUID in spaceUUIDs {
                var entry = store.spaces[spaceUUID] ?? SpaceEntry()
                entry.displays[uuid] = try apply(entry.displays[uuid])
                store.spaces[spaceUUID] = entry
            }

        case .spaceOnDisplay(let spaceUUID, let displayUUID):
            var entry = store.spaces[spaceUUID] ?? SpaceEntry()
            entry.displays[displayUUID] = try apply(entry.displays[displayUUID])
            store.spaces[spaceUUID] = entry
        }
        return store
    }

    /// Returns a copy of the store with the system default choice in `slot`.
    public func clearing(
        _ slot: WallpaperSlot,
        in target: StoreTarget = .everywhere,
        strategy: ScreensaverOnlyStrategy = .automatic,
        systemDefault: SystemDefaultProvider = SystemDefaults.slot,
        topology: DisplayTopologySnapshot? = nil
    ) throws -> WallpaperStore {
        try setting(slot, to: try systemDefault(slot), in: target, otherSlot: .keep, strategy: strategy,
                    systemDefault: systemDefault, topology: topology)
    }

    /// The section-level rule every target reduces to.
    static func applying(
        _ slot: WallpaperSlot,
        _ configuration: SlotConfiguration,
        to section: StoreSection?,
        otherSlot: OtherSlotPolicy,
        strategy: ScreensaverOnlyStrategy,
        systemDefault: SystemDefaultProvider
    ) throws -> StoreSection {
        var section = section ?? StoreSection(type: .individual)

        // Automatic mode: the Linked choice served both roles. Keep it for the slot we are not
        // writing unless it is the agent's "nothing set" placeholder. Leaving `Linked` in place
        // would make the agent ignore the Desktop/Idle choices.
        if let linked = section.linked {
            if section[slot.other] == nil, let provider = linked.provider, !provider.isPlaceholder {
                section[slot.other] = linked
            }
            section.linked = nil
        }

        section[slot] = configuration

        switch otherSlot {
        case .keep:
            break
        case .mirror:
            section[slot.other] = configuration
        case .clearToSystemDefault:
            section[slot.other] = try systemDefault(slot.other)
        case .clearIfSameProvider:
            if let provider = section[slot.other]?.provider, provider == configuration.provider {
                section[slot.other] = try systemDefault(slot.other)
            }
        }

        if section[slot.other] != nil {
            section.type = .individual
        } else if slot == .screensaver {
            switch strategy {
            case .idleSection:
                section.type = .idle
            case .materializeSystemDefaultDesktop, .automatic:
                // `.automatic` is resolved in `setting(_:to:in:…)`; alone, a section cannot
                // know whether another section has a desktop, so it takes the safe branch.
                section.desktop = try systemDefault(.desktop)
                section.type = .individual
            }
        } else {
            // An individual section needs both slots or the agent resets it.
            section.idle = try systemDefault(.screensaver)
            section.type = .individual
        }
        return section
    }

    /// `true` when any section holds a desktop choice, or a `Linked` choice that is not the
    /// agent's placeholder.
    public var hasAnyDesktopChoice: Bool {
        allSections.contains { section in
            section.desktop != nil || (section.linked?.provider.map { !$0.isPlaceholder } ?? false)
        }
    }

    // MARK: Reading

    /// The sections consulted for `target`, most specific first.
    func sections(for target: StoreTarget) -> [StoreSection] {
        var sections: [StoreSection?] = [allSpacesAndDisplays]
        switch target {
        case .everywhere:
            break
        case .space(let uuid):
            sections.append(spaces[uuid]?.default)
        case .display(let uuid):
            sections.append(displays[uuid])
        case .spaceOnDisplay(let spaceUUID, let displayUUID):
            sections.append(spaces[spaceUUID]?.displays[displayUUID])
            sections.append(spaces[spaceUUID]?.default)
            sections.append(displays[displayUUID])
        }
        sections.append(systemDefault)
        return sections.compactMap { $0 }
    }

    /// The choice in `slot` for `target`: `AllSpacesAndDisplays` first, then the sections
    /// specific to the target, then `SystemDefault`. A `Linked` choice answers for both slots.
    public func slot(_ slot: WallpaperSlot, in target: StoreTarget = .everywhere) -> SlotConfiguration? {
        for section in sections(for: target) {
            if let configuration = section[slot] ?? section.linked { return configuration }
        }
        return nil
    }

    /// The provider in `slot` for `target`.
    public func provider(of slot: WallpaperSlot, in target: StoreTarget = .everywhere) -> ChoiceProvider? {
        self.slot(slot, in: target)?.provider
    }

    /// The name of the screensaver selected for `target`, as `screensaverName(of:)` derives it.
    public func screensaverName(in target: StoreTarget = .everywhere) -> String? {
        slot(.screensaver, in: target).flatMap(Self.screensaverName(of:))
    }

    /// The screensaver names found in every section of the store.
    public func screensaverNames() -> Set<String> {
        var names = Set<String>()
        for section in allSections {
            if let name = (section.idle ?? section.linked).flatMap(Self.screensaverName(of:)) {
                names.insert(name)
            }
        }
        return names
    }

    /// Every section in the store, in no particular order.
    public var allSections: [StoreSection] {
        var all: [StoreSection] = [allSpacesAndDisplays, systemDefault].compactMap { $0 }
        for entry in spaces.values {
            if let section = entry.default { all.append(section) }
            all.append(contentsOf: entry.displays.values)
        }
        all.append(contentsOf: displays.values)
        return all
    }

    /// The name a screensaver choice is known by: the module's file name without extension
    /// for a `.saver` or app-extension screensaver, the bundle identifier for a wallpaper
    /// extension, `nil` for the system placeholder and for Apple's own wallpapers.
    public static func screensaverName(of configuration: SlotConfiguration) -> String? {
        guard let provider = configuration.provider, !provider.isPlaceholder else { return nil }
        if case .screenSaver(let moduleURL) = configuration.configuration {
            return moduleURL.deletingPathExtension().lastPathComponent
        }
        if provider.isThirdPartyExtension { return provider.rawValue }
        return nil
    }
}
