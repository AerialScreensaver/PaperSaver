import Foundation
import XCTest
@testable import PaperSaverKit

/// Loads the captured stores under `Fixtures/`.
enum Fixtures {
    static let storeNames = [
        "store-linked-default",
        "store-mixed-allspaces-extension",
        "store-idle-only-allspaces",
        "store-photos-collection",
        "store-extension-both-slots",
        "store-agent-perspace-image",
    ]

    static func url(_ name: String, extension ext: String) throws -> URL {
        try XCTUnwrap(Bundle.module.url(forResource: name, withExtension: ext, subdirectory: "Fixtures"),
                      "missing fixture \(name).\(ext)")
    }

    static func data(_ name: String, extension ext: String) throws -> Data {
        try Data(contentsOf: url(name, extension: ext))
    }

    static func plist(_ name: String) throws -> [String: Any] {
        let data = try data(name, extension: "plist")
        return try XCTUnwrap(PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any])
    }

    static func store(_ name: String) throws -> WallpaperStore {
        try StoreCodec.decode(plist(name))
    }

    static let aerialBundleID = "com.glouel.Aerial-App.Aerial4WallpaperExtension"
}

extension SlotConfiguration {
    /// A third-party extension choice, as Aerial writes it.
    static func extensionChoice(_ bundleID: String = "com.example.Test.WallpaperExtension", slot: WallpaperSlot) -> SlotConfiguration {
        SlotConfiguration(
            choice: WallpaperChoice(provider: ChoiceProvider(rawValue: bundleID), configuration: Data("token".utf8)),
            optionValues: .values(slot == .desktop ? .image() : .empty),
            date: Date(timeIntervalSince1970: 1_800_000_000))
    }
}

/// A fixed system default so the editor tests do not depend on the running macOS.
let fixedNeptune: SystemDefaultProvider = { _ in SystemDefaults.neptuneOne(date: Date(timeIntervalSince1970: 1_800_000_000)) }
