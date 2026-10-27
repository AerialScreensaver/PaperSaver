import Foundation

/// The decoded `EncodedOptionValues` of a store slot: the per-choice settings System Settings
/// shows next to a wallpaper (placement, background colour, appearance, shuffle…).
///
/// This type is the only place that knows the key paths the agent expects. Keys it has no
/// accessor for are kept in `other` and written back unchanged.
public struct OptionValues: Sendable, Equatable {
    /// How an image is placed on the display (`values.placement.picker._0.id`).
    public var placement: Placement?
    /// The colour shown behind an image that does not fill the display
    /// (`values.color.color._0.color.{components, colorSpace}`).
    public var backgroundColor: BackgroundColor?
    /// Light, dark or automatic appearance (`values.appearance.picker._0.id`).
    public var appearance: String?
    /// How often a shuffled choice advances (`values.shuffleFrequency.picker._0.id`).
    public var shuffleFrequency: String?
    /// Whether a shuffled choice is randomised (`values.shuffleRandomly.toggle._0.isOn`).
    public var shuffleRandomly: Bool?
    /// Every other entry under `values`, untouched.
    public var other: [String: PlistValue]

    public init(
        placement: Placement? = nil,
        backgroundColor: BackgroundColor? = nil,
        appearance: String? = nil,
        shuffleFrequency: String? = nil,
        shuffleRandomly: Bool? = nil,
        other: [String: PlistValue] = [:]
    ) {
        self.placement = placement
        self.backgroundColor = backgroundColor
        self.appearance = appearance
        self.shuffleFrequency = shuffleFrequency
        self.shuffleRandomly = shuffleRandomly
        self.other = other
    }

    /// No option values at all: `{"values": {}}`. What the system records for screensaver
    /// slots and for its default wallpaper.
    public static let empty = OptionValues()

    /// The option values System Settings records for an image wallpaper: a placement and a
    /// background colour. WallpaperAgent rejects an image or extension Desktop choice that
    /// lacks either.
    public static func image(placement: Placement = .crop, backgroundColor: BackgroundColor = .opaqueBlack) -> OptionValues {
        OptionValues(placement: placement, backgroundColor: backgroundColor)
    }

    /// An image placement, as the `id` of the placement picker.
    public struct Placement: RawRepresentable, Hashable, Sendable, Codable {
        public let rawValue: String
        public init(rawValue: String) { self.rawValue = rawValue }
        /// Fill the display, cropping the image (`WallpaperPlacement.fill`).
        public static let crop = Placement(rawValue: "Crop")
        /// Show the whole image (`WallpaperPlacement.fit`).
        public static let sizeToFit = Placement(rawValue: "SizeToFit")
        /// Stretch each axis to the display (`WallpaperPlacement.stretch`).
        public static let fillScreen = Placement(rawValue: "FillScreen")
        /// Natural size, centred (`WallpaperPlacement.center`).
        public static let centered = Placement(rawValue: "Centered")
    }

    /// A background colour in a named Core Graphics colour space.
    public struct BackgroundColor: Sendable, Equatable {
        public var components: [Double]
        public var colorSpaceName: String

        public init(components: [Double], colorSpaceName: String = "kCGColorSpaceGenericRGB") {
            self.components = components
            self.colorSpaceName = colorSpaceName
        }

        public static let opaqueBlack = BackgroundColor(components: [0, 0, 0, 1])
    }

    // MARK: Decoding

    /// Decodes an `EncodedOptionValues` payload (a binary plist of `{"values": {…}}`).
    public init(decoding data: Data) throws {
        guard let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              let values = plist["values"] as? [String: Any] else {
            throw PaperSaverError.invalidConfiguration("EncodedOptionValues is not a {\"values\": …} property list")
        }
        self.init(values: values)
    }

    /// Builds option values from the dictionary under `values`. Entries that do not have the
    /// expected shape are kept verbatim in `other`.
    public init(values: [String: Any]) {
        self.init()
        for (key, raw) in values {
            let dict = raw as? [String: Any]
            switch key {
            case "placement":
                if let id = Self.pickerID(dict) { placement = Placement(rawValue: id); continue }
            case "color":
                if let color = Self.backgroundColor(dict) { backgroundColor = color; continue }
            case "appearance":
                if let id = Self.pickerID(dict) { appearance = id; continue }
            case "shuffleFrequency":
                if let id = Self.pickerID(dict) { shuffleFrequency = id; continue }
            case "shuffleRandomly":
                if let isOn = Self.toggle(dict) { shuffleRandomly = isOn; continue }
            default:
                break
            }
            if let wrapped = PlistValue(any: raw) { other[key] = wrapped }
        }
    }

    // MARK: Legacy repair

    /// These values with the background colour PaperSaver 0.3.1 and earlier wrote one level
    /// too deep (`values.color.color.color._0.color`) moved to the path the agent reads, or
    /// `nil` when there is nothing to repair.
    ///
    /// The decoder keeps that shape verbatim in `other["color"]`; WallpaperAgent fails to
    /// decode the whole slot's option values because of it ("Key '_0' not found", Cocoa error
    /// 4865) and treats the slot as having none.
    public func repairingLegacyBackgroundColor() -> OptionValues? {
        guard backgroundColor == nil,
              let legacy = other["color"]?.anyValue as? [String: Any],
              let color = Self.backgroundColor(legacy["color"] as? [String: Any]) else {
            return nil
        }
        var repaired = self
        repaired.backgroundColor = color
        repaired.other["color"] = nil
        return repaired
    }

    private static func pickerID(_ dict: [String: Any]?) -> String? {
        (((dict?["picker"] as? [String: Any])?["_0"] as? [String: Any])?["id"]) as? String
    }

    private static func toggle(_ dict: [String: Any]?) -> Bool? {
        (((dict?["toggle"] as? [String: Any])?["_0"] as? [String: Any])?["isOn"]) as? Bool
    }

    private static func backgroundColor(_ dict: [String: Any]?) -> BackgroundColor? {
        guard let inner = ((dict?["color"] as? [String: Any])?["_0"] as? [String: Any])?["color"] as? [String: Any],
              let numbers = inner["components"] as? [NSNumber],
              let spaceData = inner["colorSpace"] as? Data,
              let spaceName = try? PropertyListSerialization.propertyList(from: spaceData, format: nil) as? String else {
            return nil
        }
        return BackgroundColor(components: numbers.map(\.doubleValue), colorSpaceName: spaceName)
    }

    // MARK: Encoding

    /// The dictionary stored under `values`.
    public func valuesDictionary() throws -> [String: Any] {
        var values = other.anyValues
        if let placement {
            values["placement"] = ["picker": ["_0": ["id": placement.rawValue]]]
        }
        if let backgroundColor {
            let colorSpace = try PropertyListSerialization.data(
                fromPropertyList: backgroundColor.colorSpaceName, format: .binary, options: 0)
            values["color"] = ["color": ["_0": ["color": [
                "components": backgroundColor.components,
                "colorSpace": colorSpace
            ]]]]
        }
        if let appearance {
            values["appearance"] = ["picker": ["_0": ["id": appearance]]]
        }
        if let shuffleFrequency {
            values["shuffleFrequency"] = ["picker": ["_0": ["id": shuffleFrequency]]]
        }
        if let shuffleRandomly {
            values["shuffleRandomly"] = ["toggle": ["_0": ["isOn": shuffleRandomly]]]
        }
        return values
    }

    /// The payload as the store expects it: a binary plist of `{"values": {…}}`.
    public func encoded() throws -> Data {
        try PropertyListSerialization.data(fromPropertyList: ["values": valuesDictionary()], format: .binary, options: 0)
    }
}
