import Foundation

/// A typed view of `~/Library/Application Support/com.apple.wallpaper/Store/Index.plist`.
///
/// Every key the library does not model is preserved in an `extra` dictionary so a
/// read-modify-write cycle leaves unfamiliar content untouched.
public struct WallpaperStore: Sendable, Equatable {
    /// The section the agent uses when every display and Space share one choice.
    public var allSpacesAndDisplays: StoreSection?
    /// The fallback section.
    public var systemDefault: StoreSection?
    /// Per-Space sections, keyed by Space UUID (the empty key is used for the first Space).
    public var spaces: [String: SpaceEntry]
    /// Per-display sections, keyed by display UUID.
    public var displays: [String: StoreSection]
    /// Top-level keys the library does not model.
    public var extra: [String: PlistValue]

    public init(
        allSpacesAndDisplays: StoreSection? = nil,
        systemDefault: StoreSection? = nil,
        spaces: [String: SpaceEntry] = [:],
        displays: [String: StoreSection] = [:],
        extra: [String: PlistValue] = [:]
    ) {
        self.allSpacesAndDisplays = allSpacesAndDisplays
        self.systemDefault = systemDefault
        self.spaces = spaces
        self.displays = displays
        self.extra = extra
    }

    /// `true` when the store has no per-Space and no per-display sections, which is what the
    /// agent writes while "Displays have separate Spaces" is off and no Space has its own choice.
    public var isAllSpacesMode: Bool {
        spaces.isEmpty && displays.isEmpty
    }
}

/// A per-Space entry: the Space's own section plus one section per display it appears on.
public struct SpaceEntry: Sendable, Equatable {
    public var `default`: StoreSection?
    public var displays: [String: StoreSection]
    public var extra: [String: PlistValue]

    public init(default: StoreSection? = nil, displays: [String: StoreSection] = [:], extra: [String: PlistValue] = [:]) {
        self.default = `default`
        self.displays = displays
        self.extra = extra
    }
}

/// How a section's slots relate to each other.
public enum SectionType: Sendable, Equatable, Hashable {
    /// Automatic mode: one `Linked` choice serves as wallpaper and screensaver.
    case linked
    /// Separate `Desktop` and `Idle` choices.
    case individual
    /// Only an `Idle` choice; the desktop comes from a lower-precedence section.
    case idle
    /// A value the library has not seen.
    case other(String)

    public init(rawValue: String) {
        switch rawValue {
        case "linked": self = .linked
        case "individual": self = .individual
        case "idle": self = .idle
        default: self = .other(rawValue)
        }
    }

    public var rawValue: String {
        switch self {
        case .linked: return "linked"
        case .individual: return "individual"
        case .idle: return "idle"
        case .other(let raw): return raw
        }
    }
}

/// One `{Type, Desktop, Idle, Linked}` section of the store.
public struct StoreSection: Sendable, Equatable {
    public var type: SectionType
    public var desktop: SlotConfiguration?
    public var idle: SlotConfiguration?
    public var linked: SlotConfiguration?
    /// Section keys the library does not model.
    public var extra: [String: PlistValue]

    public init(
        type: SectionType,
        desktop: SlotConfiguration? = nil,
        idle: SlotConfiguration? = nil,
        linked: SlotConfiguration? = nil,
        extra: [String: PlistValue] = [:]
    ) {
        self.type = type
        self.desktop = desktop
        self.idle = idle
        self.linked = linked
        self.extra = extra
    }

    public subscript(slot: WallpaperSlot) -> SlotConfiguration? {
        get { slot == .desktop ? desktop : idle }
        set { if slot == .desktop { desktop = newValue } else { idle = newValue } }
    }
}

/// How a slot's `EncodedOptionValues` key is written.
public enum SlotOptionValues: Sendable, Equatable {
    /// A binary plist of `{"values": {…}}`.
    case values(OptionValues)
    /// The literal string `"$null"`, as System Settings writes for `.saver` and appex screensavers.
    case null
    /// No key at all.
    case absent
    /// Data the library could not decode, kept byte for byte.
    case raw(Data)

    public var values: OptionValues? {
        if case .values(let values) = self { return values }
        return nil
    }
}

/// How a slot's `Shuffle` key is written.
public enum SlotShuffle: Sendable, Equatable {
    /// The literal string `"$null"` (no shuffle), the usual value.
    case null
    /// No key at all.
    case absent
    /// Any other value, kept as is.
    case raw(PlistValue)
}

/// One slot (`Desktop`, `Idle` or `Linked`) of a section.
public struct SlotConfiguration: Sendable, Equatable {
    public var choices: [WallpaperChoice]
    public var optionValues: SlotOptionValues
    public var shuffle: SlotShuffle
    public var lastSet: Date?
    public var lastUse: Date?
    /// Keys under `Content` the library does not model.
    public var contentExtra: [String: PlistValue]
    /// Keys next to `Content` the library does not model.
    public var extra: [String: PlistValue]

    public init(
        choices: [WallpaperChoice],
        optionValues: SlotOptionValues = .values(.empty),
        shuffle: SlotShuffle = .null,
        lastSet: Date? = nil,
        lastUse: Date? = nil,
        contentExtra: [String: PlistValue] = [:],
        extra: [String: PlistValue] = [:]
    ) {
        self.choices = choices
        self.optionValues = optionValues
        self.shuffle = shuffle
        self.lastSet = lastSet
        self.lastUse = lastUse
        self.contentExtra = contentExtra
        self.extra = extra
    }

    /// A slot holding one choice, stamped now.
    public init(choice: WallpaperChoice, optionValues: SlotOptionValues = .values(.empty), shuffle: SlotShuffle = .null, date: Date = Date()) {
        self.init(choices: [choice], optionValues: optionValues, shuffle: shuffle, lastSet: date, lastUse: date)
    }

    /// The provider of the first choice.
    public var provider: ChoiceProvider? { choices.first?.provider }

    /// The first choice's decoded configuration.
    public var configuration: ChoiceConfiguration? { choices.first?.decodedConfiguration }
}

/// One entry of a slot's `Choices` array.
public struct WallpaperChoice: Sendable, Equatable {
    public var provider: ChoiceProvider
    public var configuration: Data
    public var files: [PlistValue]
    /// Choice keys the library does not model.
    public var extra: [String: PlistValue]

    public init(provider: ChoiceProvider, configuration: Data = Data(), files: [PlistValue] = [], extra: [String: PlistValue] = [:]) {
        self.provider = provider
        self.configuration = configuration
        self.files = files
        self.extra = extra
    }

    public init(provider: ChoiceProvider, configuration: ChoiceConfiguration) throws {
        self.init(provider: provider, configuration: try configuration.encoded())
    }

    public var decodedConfiguration: ChoiceConfiguration {
        ChoiceConfiguration(decoding: configuration)
    }
}

// MARK: - Codec

/// Converts between the store's property-list dictionary and `WallpaperStore`.
///
/// These are the only two functions in the library that handle `[String: Any]` store content.
enum StoreCodec {
    private static let topLevelKeys: Set<String> = ["AllSpacesAndDisplays", "SystemDefault", "Spaces", "Displays"]
    private static let sectionKeys: Set<String> = ["Type", "Desktop", "Idle", "Linked"]
    private static let spaceEntryKeys: Set<String> = ["Default", "Displays"]
    private static let slotKeys: Set<String> = ["Content", "LastSet", "LastUse"]
    private static let contentKeys: Set<String> = ["Choices", "EncodedOptionValues", "Shuffle"]
    private static let choiceKeys: Set<String> = ["Provider", "Configuration", "Files"]

    static func decode(_ plist: [String: Any]) throws -> WallpaperStore {
        var store = WallpaperStore()
        var extra: [String: Any] = [:]
        for (key, value) in plist {
            switch key {
            case "AllSpacesAndDisplays":
                if let dict = value as? [String: Any] { store.allSpacesAndDisplays = section(dict) } else { extra[key] = value }
            case "SystemDefault":
                if let dict = value as? [String: Any] { store.systemDefault = section(dict) } else { extra[key] = value }
            case "Spaces":
                guard let dict = value as? [String: Any] else { extra[key] = value; continue }
                for (uuid, entryValue) in dict {
                    guard let entry = entryValue as? [String: Any] else { continue }
                    store.spaces[uuid] = spaceEntry(entry)
                }
            case "Displays":
                guard let dict = value as? [String: Any] else { extra[key] = value; continue }
                for (uuid, sectionValue) in dict {
                    guard let sectionDict = sectionValue as? [String: Any] else { continue }
                    store.displays[uuid] = section(sectionDict)
                }
            default:
                extra[key] = value
            }
        }
        store.extra = extra.plistValues
        return store
    }

    static func encode(_ store: WallpaperStore) -> [String: Any] {
        var plist = store.extra.anyValues
        if let section = store.allSpacesAndDisplays { plist["AllSpacesAndDisplays"] = encode(section) }
        if let section = store.systemDefault { plist["SystemDefault"] = encode(section) }
        plist["Spaces"] = store.spaces.mapValues(encode(entry:))
        plist["Displays"] = store.displays.mapValues(encode(_:))
        return plist
    }

    // MARK: Sections

    static func section(_ dict: [String: Any]) -> StoreSection {
        var section = StoreSection(type: SectionType(rawValue: dict["Type"] as? String ?? ""))
        var extra: [String: Any] = [:]
        for (key, value) in dict {
            switch key {
            case "Type":
                continue
            case "Desktop", "Idle", "Linked":
                guard let slotDict = value as? [String: Any], let slot = slot(slotDict) else {
                    extra[key] = value
                    continue
                }
                if key == "Desktop" { section.desktop = slot } else if key == "Idle" { section.idle = slot } else { section.linked = slot }
            default:
                extra[key] = value
            }
        }
        section.extra = extra.plistValues
        return section
    }

    static func encode(_ section: StoreSection) -> [String: Any] {
        var dict = section.extra.anyValues
        dict["Type"] = section.type.rawValue
        if let slot = section.desktop { dict["Desktop"] = encode(slot) }
        if let slot = section.idle { dict["Idle"] = encode(slot) }
        if let slot = section.linked { dict["Linked"] = encode(slot) }
        return dict
    }

    static func spaceEntry(_ dict: [String: Any]) -> SpaceEntry {
        var entry = SpaceEntry()
        var extra: [String: Any] = [:]
        for (key, value) in dict {
            switch key {
            case "Default":
                if let sectionDict = value as? [String: Any] { entry.default = section(sectionDict) } else { extra[key] = value }
            case "Displays":
                guard let displays = value as? [String: Any] else { extra[key] = value; continue }
                for (uuid, sectionValue) in displays {
                    guard let sectionDict = sectionValue as? [String: Any] else { continue }
                    entry.displays[uuid] = section(sectionDict)
                }
            default:
                extra[key] = value
            }
        }
        entry.extra = extra.plistValues
        return entry
    }

    static func encode(entry: SpaceEntry) -> [String: Any] {
        var dict = entry.extra.anyValues
        if let section = entry.default { dict["Default"] = encode(section) }
        dict["Displays"] = entry.displays.mapValues(encode(_:))
        return dict
    }

    // MARK: Slots

    static func slot(_ dict: [String: Any]) -> SlotConfiguration? {
        guard let content = dict["Content"] as? [String: Any] else { return nil }
        var choices: [WallpaperChoice] = []
        for choiceValue in content["Choices"] as? [Any] ?? [] {
            guard let choiceDict = choiceValue as? [String: Any],
                  let provider = choiceDict["Provider"] as? String else { continue }
            var choice = WallpaperChoice(
                provider: ChoiceProvider(rawValue: provider),
                configuration: choiceDict["Configuration"] as? Data ?? Data(),
                files: (choiceDict["Files"] as? [Any] ?? []).compactMap { PlistValue(any: $0) })
            choice.extra = choiceDict.filter { !choiceKeys.contains($0.key) }.plistValues
            choices.append(choice)
        }

        let optionValues: SlotOptionValues
        switch content["EncodedOptionValues"] {
        case let data as Data:
            if let decoded = try? OptionValues(decoding: data) { optionValues = .values(decoded) } else { optionValues = .raw(data) }
        case let string as String where string == "$null":
            optionValues = .null
        default:
            optionValues = .absent
        }

        let shuffle: SlotShuffle
        switch content["Shuffle"] {
        case nil: shuffle = .absent
        case let string as String where string == "$null": shuffle = .null
        case let value?: shuffle = PlistValue(any: value).map(SlotShuffle.raw) ?? .absent
        }

        var contentExtra = content.filter { !contentKeys.contains($0.key) }
        if let value = content["EncodedOptionValues"], !(value is Data), (value as? String) != "$null" {
            contentExtra["EncodedOptionValues"] = value
        }

        return SlotConfiguration(
            choices: choices,
            optionValues: optionValues,
            shuffle: shuffle,
            lastSet: dict["LastSet"] as? Date,
            lastUse: dict["LastUse"] as? Date,
            contentExtra: contentExtra.plistValues,
            extra: dict.filter { !slotKeys.contains($0.key) }.plistValues)
    }

    static func encode(_ slot: SlotConfiguration) -> [String: Any] {
        var content = slot.contentExtra.anyValues
        content["Choices"] = slot.choices.map { choice -> [String: Any] in
            var dict = choice.extra.anyValues
            dict["Provider"] = choice.provider.rawValue
            dict["Configuration"] = choice.configuration
            dict["Files"] = choice.files.map(\.anyValue)
            return dict
        }
        switch slot.optionValues {
        case .values(let values):
            // Encoding only fails for a colour-space name that is not a property list, which
            // `String` always is.
            content["EncodedOptionValues"] = (try? values.encoded()) ?? Data()
        case .null:
            content["EncodedOptionValues"] = "$null"
        case .absent:
            break
        case .raw(let data):
            content["EncodedOptionValues"] = data
        }
        switch slot.shuffle {
        case .null: content["Shuffle"] = "$null"
        case .absent: break
        case .raw(let value): content["Shuffle"] = value.anyValue
        }

        var dict = slot.extra.anyValues
        dict["Content"] = content
        if let date = slot.lastSet { dict["LastSet"] = date }
        if let date = slot.lastUse { dict["LastUse"] = date }
        return dict
    }
}
