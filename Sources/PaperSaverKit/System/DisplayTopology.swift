import Foundation

/// One Mission Control Space as the window server reports it.
public struct SpaceSummary: Sendable, Equatable, Codable {
    /// 1-based position of the Space on its display.
    public var number: Int
    public var id: Int64
    public var managedID: Int64
    public var uuid: String
    public var isCurrent: Bool

    public init(number: Int, id: Int64, managedID: Int64, uuid: String, isCurrent: Bool) {
        self.number = number
        self.id = id
        self.managedID = managedID
        self.uuid = uuid
        self.isCurrent = isCurrent
    }
}

/// One display and its Spaces, as the window server reports them.
public struct DisplaySpaces: Sendable, Equatable, Codable {
    /// The display UUID the wallpaper store keys per-display sections by.
    public var uuid: String
    public var name: String
    /// 1-based position of the display in `NSScreen.screens`, or 0 when it is not connected.
    public var displayNumber: Int
    public var spaces: [SpaceSummary]
    public var currentSpaceUUID: String?

    public init(uuid: String, name: String, displayNumber: Int, spaces: [SpaceSummary], currentSpaceUUID: String?) {
        self.uuid = uuid
        self.name = name
        self.displayNumber = displayNumber
        self.spaces = spaces
        self.currentSpaceUUID = currentSpaceUUID
    }
}

/// The displays and Spaces at one moment, used to resolve numbers to UUIDs and to find
/// which per-Space sections a per-display write must touch.
public struct DisplayTopologySnapshot: Sendable, Equatable {
    public var displays: [DisplaySpaces]

    public init(displays: [DisplaySpaces]) {
        self.displays = displays
    }

    public func display(number: Int) -> DisplaySpaces? {
        displays.first { $0.displayNumber == number }
    }

    public func display(uuid: String) -> DisplaySpaces? {
        displays.first { $0.uuid == uuid }
    }

    public func spaceUUID(displayNumber: Int, spaceNumber: Int) -> String? {
        display(number: displayNumber)?.spaces.first { $0.number == spaceNumber }?.uuid
    }

    /// The UUIDs of the Spaces that appear on a display.
    public func spaceUUIDs(onDisplay uuid: String) -> [String] {
        display(uuid: uuid)?.spaces.map(\.uuid) ?? []
    }

    /// The UUIDs of the displays a Space appears on.
    public func displayUUIDs(ofSpace spaceUUID: String) -> [String] {
        displays.filter { $0.spaces.contains { $0.uuid == spaceUUID } }.map(\.uuid)
    }
}

// MARK: - Live topology

import CoreGraphics
import ColorSync

@_silgen_name("CGSMainConnectionID")
private func CGSMainConnectionID() -> Int32

@_silgen_name("CGSCopyManagedDisplaySpaces")
private func CGSCopyManagedDisplaySpaces(_ connection: Int32) -> Unmanaged<CFArray>?

/// Display UUIDs, as the wallpaper store and the window server use them.
public enum DisplayUUID {
    /// The UUID of a connected display.
    public static func uuid(for displayID: CGDirectDisplayID) -> String? {
        guard let cfUUID = CGDisplayCreateUUIDFromDisplayID(displayID)?.takeRetainedValue() else { return nil }
        return CFUUIDCreateString(nil, cfUUID) as String?
    }

    /// The display identifier for a UUID, or `nil` when that display is not connected.
    public static func displayID(for uuid: String) -> CGDirectDisplayID? {
        guard let cfUUID = CFUUIDCreateFromString(nil, uuid as CFString) else { return nil }
        let id = CGDisplayGetDisplayIDFromUUID(cfUUID)
        // ColorSync answers with the main display for some unknown UUIDs; only trust an
        // identifier whose own UUID is the one asked for.
        guard id != 0, self.uuid(for: id)?.caseInsensitiveCompare(uuid) == .orderedSame else { return nil }
        return id
    }

    /// Whether a string has the shape of a display UUID key.
    public static func isValid(_ key: String) -> Bool {
        UUID(uuidString: key) != nil
    }

    /// The UUID of the main display.
    public static var main: String? {
        uuid(for: CGMainDisplayID())
    }
}

/// The connected displays and their Spaces, from the window server.
public enum DisplayTopology {
    /// Connected displays, main first, then left to right and top to bottom.
    public static func connectedDisplayIDs() -> [CGDirectDisplayID] {
        var count: UInt32 = 0
        guard CGGetActiveDisplayList(0, nil, &count) == .success, count > 0 else { return [] }
        var ids = [CGDirectDisplayID](repeating: 0, count: Int(count))
        guard CGGetActiveDisplayList(count, &ids, &count) == .success else { return [] }
        let main = CGMainDisplayID()
        return ids.prefix(Int(count)).sorted { a, b in
            if a == main { return true }
            if b == main { return false }
            let ba = CGDisplayBounds(a), bb = CGDisplayBounds(b)
            return ba.origin.x != bb.origin.x ? ba.origin.x < bb.origin.x : ba.origin.y < bb.origin.y
        }
    }

    public static func snapshot() -> DisplayTopologySnapshot {
        let ordered = connectedDisplayIDs()
        let numbers = Dictionary(uniqueKeysWithValues: ordered.enumerated().compactMap { index, id in
            DisplayUUID.uuid(for: id).map { ($0, index + 1) }
        })

        let managed = CGSCopyManagedDisplaySpaces(CGSMainConnectionID())?.takeRetainedValue() as? [[String: Any]] ?? []
        let sorted = managed.sorted { a, b in
            let ia = ((a["Spaces"] as? [[String: Any]])?.first?["id64"] as? NSNumber)?.int64Value ?? .max
            let ib = ((b["Spaces"] as? [[String: Any]])?.first?["id64"] as? NSNumber)?.int64Value ?? .max
            return ia < ib
        }

        var displays: [DisplaySpaces] = []
        var spaceNumber = 1
        for display in sorted {
            guard var uuid = display["Display Identifier"] as? String else { continue }
            // With "Displays have separate Spaces" off, the window server reports "Main".
            if uuid == "Main", let main = DisplayUUID.main { uuid = main }
            let currentID = ((display["Current Space"] as? [String: Any])?["id64"] as? NSNumber)?.int64Value
            var spaces: [SpaceSummary] = []
            for space in display["Spaces"] as? [[String: Any]] ?? [] {
                guard let id = (space["id64"] as? NSNumber)?.int64Value,
                      let spaceUUID = space["uuid"] as? String else { continue }
                spaces.append(SpaceSummary(
                    number: spaceNumber, id: id,
                    managedID: (space["ManagedSpaceID"] as? NSNumber)?.int64Value ?? 0,
                    uuid: spaceUUID, isCurrent: id == currentID))
                spaceNumber += 1
            }
            displays.append(DisplaySpaces(
                uuid: uuid, name: displayName(uuid: uuid), displayNumber: numbers[uuid] ?? 0,
                spaces: spaces, currentSpaceUUID: spaces.first { $0.isCurrent }?.uuid))
        }
        return DisplayTopologySnapshot(displays: displays)
    }

    /// A name for a display without AppKit: its vendor/model numbers, or a UUID prefix.
    static func displayName(uuid: String) -> String {
        guard let id = DisplayUUID.displayID(for: uuid) else { return "Display \(uuid.prefix(8))… (disconnected)" }
        let size = CGDisplayBounds(id).size
        let kind = CGDisplayIsBuiltin(id) != 0 ? "Built-in display" : "Display \(CGDisplayVendorNumber(id))-\(CGDisplayModelNumber(id))"
        return "\(kind) \(Int(size.width))×\(Int(size.height))" + (id == CGMainDisplayID() ? " (Main)" : "")
    }
}
