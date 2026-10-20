import Foundation

/// The decoded `Configuration` payload of a wallpaper-store choice.
///
/// The payload is a binary property list whose shape depends on the provider. Payloads the
/// library does not model, including the opaque tokens third-party extensions store, are
/// carried as `.opaque`.
public enum ChoiceConfiguration: Sendable, Equatable {
    /// A `.saver` plug-in or app-extension screensaver, by bundle URL.
    case screenSaver(moduleURL: URL)
    /// A single image file.
    case imageFile(URL)
    /// A Photos library collection.
    case photosCollection(identifier: String)
    /// Empty data, as the system writes for its default wallpaper.
    case empty
    /// Any other payload, kept byte for byte.
    case opaque(Data)

    /// Decodes a `Configuration` payload. Never fails: unknown shapes decode as `.opaque`.
    public init(decoding data: Data) {
        guard !data.isEmpty else {
            self = .empty
            return
        }
        guard let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] else {
            self = .opaque(data)
            return
        }
        if let module = plist["module"] as? [String: Any],
           let relative = module["relative"] as? String,
           let url = URL(string: relative) {
            self = .screenSaver(moduleURL: url)
            return
        }
        if let type = plist["type"] as? String {
            if type == "imageFile",
               let urlDict = plist["url"] as? [String: Any],
               let relative = urlDict["relative"] as? String,
               let url = URL(string: relative) {
                self = .imageFile(url)
                return
            }
            if type == "collection", let identifier = plist["identifier"] as? String {
                self = .photosCollection(identifier: identifier)
                return
            }
        }
        self = .opaque(data)
    }

    /// The payload as the bytes the store expects.
    public func encoded() throws -> Data {
        let plist: [String: Any]
        switch self {
        case .screenSaver(let moduleURL):
            plist = ["module": ["relative": moduleURL.absoluteString]]
        case .imageFile(let url):
            plist = ["type": "imageFile", "url": ["relative": url.absoluteString]]
        case .photosCollection(let identifier):
            plist = ["type": "collection", "identifier": identifier]
        case .empty:
            return Data()
        case .opaque(let data):
            return data
        }
        return try PropertyListSerialization.data(fromPropertyList: plist, format: .binary, options: 0)
    }
}
