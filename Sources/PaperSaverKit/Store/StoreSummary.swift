import Foundation

/// A readable, encodable description of a store, for diagnostics and the CLI.
public struct StoreSummary: Codable, Sendable, Equatable {
    public struct Slot: Codable, Sendable, Equatable {
        public let provider: String
        public let configuration: String
        public let optionValues: String
        public let shuffle: String
    }

    public struct Section: Codable, Sendable, Equatable {
        /// Where the section sits: `AllSpacesAndDisplays`, `SystemDefault`,
        /// `Spaces[<uuid>].Default`, `Spaces[<uuid>].Displays[<uuid>]` or `Displays[<uuid>]`.
        public let path: String
        public let type: String
        public let desktop: Slot?
        public let idle: Slot?
        public let linked: Slot?
    }

    public let sections: [Section]

    public init(_ store: WallpaperStore) {
        var sections: [Section] = []
        func add(_ path: String, _ section: StoreSection?) {
            guard let section else { return }
            sections.append(Section(path: path, type: section.type.rawValue,
                                    desktop: section.desktop.map(Slot.init), idle: section.idle.map(Slot.init),
                                    linked: section.linked.map(Slot.init)))
        }
        add("AllSpacesAndDisplays", store.allSpacesAndDisplays)
        add("SystemDefault", store.systemDefault)
        for uuid in store.spaces.keys.sorted() {
            let entry = store.spaces[uuid]!
            let label = uuid.isEmpty ? "\"\"" : uuid
            add("Spaces[\(label)].Default", entry.default)
            for displayUUID in entry.displays.keys.sorted() {
                add("Spaces[\(label)].Displays[\(displayUUID)]", entry.displays[displayUUID])
            }
        }
        for uuid in store.displays.keys.sorted() {
            add("Displays[\(uuid)]", store.displays[uuid])
        }
        self.sections = sections
    }
}

extension StoreSummary.Slot {
    init(_ slot: SlotConfiguration) {
        provider = slot.provider?.rawValue ?? "(no choice)"
        switch slot.configuration {
        case .screenSaver(let url)?: configuration = "screensaver \(url.path)"
        case .imageFile(let url)?: configuration = "image \(url.path)"
        case .photosCollection(let id)?: configuration = "photos collection \(id)"
        case .empty?: configuration = "empty"
        case .opaque(let data)?: configuration = "opaque \(data.count) bytes"
        case nil: configuration = "none"
        }
        switch slot.optionValues {
        case .values(let values):
            var keys: [String] = []
            if values.placement != nil { keys.append("placement") }
            if values.backgroundColor != nil { keys.append("color") }
            if values.appearance != nil { keys.append("appearance") }
            if values.shuffleFrequency != nil { keys.append("shuffleFrequency") }
            if values.shuffleRandomly != nil { keys.append("shuffleRandomly") }
            keys.append(contentsOf: values.other.keys.sorted().map { "\($0) (raw)" })
            optionValues = keys.isEmpty ? "{}" : keys.joined(separator: ", ")
        case .null: optionValues = "$null"
        case .absent: optionValues = "absent"
        case .raw(let data): optionValues = "undecodable \(data.count) bytes"
        }
        switch slot.shuffle {
        case .null: shuffle = "$null"
        case .absent: shuffle = "absent"
        case .raw: shuffle = "custom"
        }
    }
}
