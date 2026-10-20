import XCTest
@testable import PaperSaverKit

final class StoreEditorTests: XCTestCase {

    private let ext = "com.example.Test.WallpaperExtension"
    private var desktopChoice: SlotConfiguration { .extensionChoice(ext, slot: .desktop) }
    private var saverChoice: SlotConfiguration { .extensionChoice(ext, slot: .screensaver) }

    // MARK: Screensaver-only

    /// Measured 2026-10-20: the agent resets a store whose sections hold only Idle slots, so the
    /// automatic strategy materialises the system default desktop when no section has one.
    func testAutomaticStrategyMaterializesWhenNoDesktopExists() throws {
        let store = try Fixtures.store("store-linked-default")
        let out = try store.setting(.screensaver, to: saverChoice, otherSlot: .keep, systemDefault: fixedNeptune)
        for section in [out.allSpacesAndDisplays, out.systemDefault].compactMap({ $0 }) {
            XCTAssertEqual(section.type, .individual)
            XCTAssertEqual(section.desktop?.provider, .neptuneOne)
            XCTAssertEqual(section.idle?.provider?.rawValue, ext)
            XCTAssertNil(section.linked)
        }
    }

    /// Measured 2026-10-20: `Type = idle` is kept when a lower-precedence section has the desktop.
    func testAutomaticStrategyKeepsIdleSectionsWhenDesktopsArePerSpace() throws {
        let store = try Fixtures.store("store-idle-only-allspaces")
        let out = try store.setting(.screensaver, to: saverChoice, otherSlot: .keep, systemDefault: fixedNeptune)
        XCTAssertEqual(out.allSpacesAndDisplays?.type, .idle)
        XCTAssertNil(out.allSpacesAndDisplays?.desktop)
        XCTAssertEqual(out.systemDefault?.desktop?.provider, .image)

        let agentStore = try Fixtures.store("store-agent-perspace-image")
        let out2 = try agentStore.setting(.screensaver, to: saverChoice, otherSlot: .keep, systemDefault: fixedNeptune)
        XCTAssertEqual(out2.allSpacesAndDisplays?.type, .idle)
        XCTAssertEqual(out2.allSpacesAndDisplays?.idle?.provider?.rawValue, ext)
        XCTAssertEqual(out2.systemDefault?.type, .idle, "a linked placeholder section becomes idle too")
    }

    func testScreensaverOnlyFromPlaceholderWritesIdleSection() throws {
        let store = try Fixtures.store("store-linked-default")
        let out = try store.setting(.screensaver, to: saverChoice, otherSlot: .keep, strategy: .idleSection, systemDefault: fixedNeptune)
        for section in [out.allSpacesAndDisplays, out.systemDefault].compactMap({ $0 }) {
            XCTAssertEqual(section.type, .idle)
            XCTAssertNil(section.desktop, "the placeholder is not materialised and nothing is mirrored")
            XCTAssertNil(section.linked)
            XCTAssertEqual(section.idle?.provider?.rawValue, ext)
        }
    }

    func testScreensaverOnlyCanMaterializeTheSystemDefaultDesktop() throws {
        let store = try Fixtures.store("store-linked-default")
        let out = try store.setting(.screensaver, to: saverChoice, strategy: .materializeSystemDefaultDesktop, systemDefault: fixedNeptune)
        let section = try XCTUnwrap(out.allSpacesAndDisplays)
        XCTAssertEqual(section.type, .individual)
        XCTAssertEqual(section.desktop?.provider, .neptuneOne)
        XCTAssertEqual(section.idle?.provider?.rawValue, ext)
    }

    func testScreensaverOnlyMaterializesARealLinkedWallpaper() throws {
        let linked = SlotConfiguration(choice: WallpaperChoice(provider: ChoiceProvider(rawValue: "com.apple.wallpaper.choice.dynamic")))
        let store = WallpaperStore(allSpacesAndDisplays: StoreSection(type: .linked, linked: linked))
        let out = try store.setting(.screensaver, to: saverChoice, systemDefault: fixedNeptune)
        let section = try XCTUnwrap(out.allSpacesAndDisplays)
        XCTAssertEqual(section.type, .individual)
        XCTAssertNil(section.linked)
        XCTAssertEqual(section.desktop?.provider?.rawValue, "com.apple.wallpaper.choice.dynamic")
        XCTAssertEqual(section.idle?.provider?.rawValue, ext)
    }

    func testScreensaverOnlyPreservesAnExistingDesktop() throws {
        let store = try Fixtures.store("store-mixed-allspaces-extension")
        let out = try store.setting(.screensaver, to: saverChoice, otherSlot: .keep, systemDefault: fixedNeptune)
        XCTAssertEqual(out.systemDefault?.desktop?.provider, .image)
        XCTAssertEqual(out.systemDefault?.idle?.provider?.rawValue, ext)
        XCTAssertEqual(out.systemDefault?.type, .individual)
    }

    // MARK: Other-slot policies

    func testClearIfSameProviderLeavesExactlyOneSlotForTheExtension() throws {
        let store = try Fixtures.store("store-extension-both-slots")
        let aerial = Fixtures.aerialBundleID
        let desktop = try store.setting(.desktop, to: .extensionChoice(aerial, slot: .desktop), otherSlot: .clearIfSameProvider, systemDefault: fixedNeptune)
        XCTAssertEqual(desktop.allSpacesAndDisplays?.desktop?.provider?.rawValue, aerial)
        XCTAssertEqual(desktop.allSpacesAndDisplays?.idle?.provider, .neptuneOne)
        XCTAssertEqual(desktop.allSpacesAndDisplays?.type, .individual)

        let saver = try store.setting(.screensaver, to: .extensionChoice(aerial, slot: .screensaver), otherSlot: .clearIfSameProvider, systemDefault: fixedNeptune)
        XCTAssertEqual(saver.allSpacesAndDisplays?.idle?.provider?.rawValue, aerial)
        XCTAssertEqual(saver.allSpacesAndDisplays?.desktop?.provider, .neptuneOne)
        XCTAssertEqual(saver.systemDefault?.desktop?.provider, .neptuneOne)
    }

    func testClearIfSameProviderKeepsADifferentProvider() throws {
        let store = try Fixtures.store("store-mixed-allspaces-extension")
        let out = try store.setting(.desktop, to: desktopChoice, otherSlot: .clearIfSameProvider, systemDefault: fixedNeptune)
        XCTAssertEqual(out.systemDefault?.idle?.provider, .screenSaver, "a different screensaver is left alone")
    }

    func testKeepFillsAMissingIdleWithTheSystemDefaultOnDesktopWrite() throws {
        let store = try Fixtures.store("store-linked-default")
        let out = try store.setting(.desktop, to: desktopChoice, otherSlot: .keep, systemDefault: fixedNeptune)
        let section = try XCTUnwrap(out.allSpacesAndDisplays)
        XCTAssertEqual(section.type, .individual)
        XCTAssertEqual(section.desktop?.provider?.rawValue, ext)
        XCTAssertEqual(section.idle?.provider, .neptuneOne, "an individual section needs both slots")
    }

    func testKeepPreservesAnExistingIdle() throws {
        let store = try Fixtures.store("store-mixed-allspaces-extension")
        let out = try store.setting(.desktop, to: desktopChoice, otherSlot: .keep, systemDefault: fixedNeptune)
        XCTAssertEqual(out.systemDefault?.idle, store.systemDefault?.idle)
    }

    func testMirrorCopiesTheChoice() throws {
        let store = try Fixtures.store("store-linked-default")
        let out = try store.setting(.desktop, to: desktopChoice, otherSlot: .mirror, systemDefault: fixedNeptune)
        XCTAssertEqual(out.allSpacesAndDisplays?.idle, desktopChoice)
    }

    func testClearToSystemDefaultAlwaysClears() throws {
        let store = try Fixtures.store("store-mixed-allspaces-extension")
        let out = try store.setting(.desktop, to: desktopChoice, otherSlot: .clearToSystemDefault, systemDefault: fixedNeptune)
        XCTAssertEqual(out.systemDefault?.idle?.provider, .neptuneOne)
    }

    func testClearingWritesTheSystemDefault() throws {
        let store = try Fixtures.store("store-extension-both-slots")
        let out = try store.clearing(.screensaver, systemDefault: fixedNeptune)
        XCTAssertEqual(out.allSpacesAndDisplays?.idle?.provider, .neptuneOne)
        XCTAssertEqual(out.allSpacesAndDisplays?.desktop?.provider?.rawValue, Fixtures.aerialBundleID)
    }

    func testDesktopWriteOnAnIdleOnlySectionBecomesIndividual() throws {
        let store = try Fixtures.store("store-idle-only-allspaces")
        let out = try store.setting(.desktop, to: desktopChoice, otherSlot: .keep, systemDefault: fixedNeptune)
        let section = try XCTUnwrap(out.allSpacesAndDisplays)
        XCTAssertEqual(section.type, .individual)
        XCTAssertEqual(section.idle?.provider?.rawValue, Fixtures.aerialBundleID)
    }

    // MARK: Targets

    func testEverywhereTouchesEverySection() throws {
        let store = try Fixtures.store("store-idle-only-allspaces")
        let out = try store.setting(.screensaver, to: saverChoice, otherSlot: .keep, systemDefault: fixedNeptune)
        XCTAssertFalse(out.allSections.isEmpty)
        for section in out.allSections {
            XCTAssertEqual(section.idle?.provider?.rawValue, ext)
        }
        XCTAssertEqual(out.allSpacesAndDisplays?.type, .idle)
        XCTAssertEqual(out.systemDefault?.desktop?.provider, .image, "desktops are untouched")
        XCTAssertEqual(out.spaces.count, store.spaces.count)
        XCTAssertEqual(out.displays.count, store.displays.count)
    }

    func testSpaceTargetTouchesOnlyThatSpace() throws {
        let store = try Fixtures.store("store-mixed-allspaces-extension")
        let uuid = try XCTUnwrap(store.spaces.keys.sorted().last)
        let out = try store.setting(.screensaver, to: saverChoice, in: .space(uuid: uuid), systemDefault: fixedNeptune)
        XCTAssertEqual(out.spaces[uuid]?.default?.idle?.provider?.rawValue, ext)
        for section in out.spaces[uuid]?.displays.values ?? [:].values {
            XCTAssertEqual(section.idle?.provider?.rawValue, ext)
        }
        XCTAssertEqual(out.allSpacesAndDisplays, store.allSpacesAndDisplays)
        XCTAssertEqual(out.systemDefault, store.systemDefault)
        for other in store.spaces.keys where other != uuid {
            XCTAssertEqual(out.spaces[other], store.spaces[other])
        }
    }

    func testDisplayTargetUsesTopologyToFindSpaces() throws {
        let store = try Fixtures.store("store-idle-only-allspaces")
        let displayUUID = try XCTUnwrap(store.displays.keys.sorted().first)
        let spaceUUIDs = Array(store.spaces.keys.sorted().prefix(2))
        let topology = DisplayTopologySnapshot(displays: [
            DisplaySpaces(uuid: displayUUID, name: "Built-in", displayNumber: 1,
                          spaces: spaceUUIDs.enumerated().map { SpaceSummary(number: $0.offset + 1, id: 0, managedID: 0, uuid: $0.element, isCurrent: $0.offset == 0) },
                          currentSpaceUUID: spaceUUIDs.first)
        ])
        let out = try store.setting(.desktop, to: desktopChoice, in: .display(uuid: displayUUID), systemDefault: fixedNeptune, topology: topology)
        XCTAssertEqual(out.displays[displayUUID]?.desktop?.provider?.rawValue, ext)
        for spaceUUID in spaceUUIDs {
            XCTAssertEqual(out.spaces[spaceUUID]?.displays[displayUUID]?.desktop?.provider?.rawValue, ext)
        }
        XCTAssertEqual(out.allSpacesAndDisplays, store.allSpacesAndDisplays)
    }

    func testSpaceOnDisplayTargetCreatesTheSection() throws {
        let store = try Fixtures.store("store-linked-default")
        let out = try store.setting(.desktop, to: desktopChoice, in: .spaceOnDisplay(spaceUUID: "S", displayUUID: "D"), systemDefault: fixedNeptune)
        XCTAssertEqual(out.spaces["S"]?.displays["D"]?.desktop?.provider?.rawValue, ext)
        XCTAssertEqual(out.spaces["S"]?.displays["D"]?.idle?.provider, .neptuneOne)
        XCTAssertEqual(out.allSpacesAndDisplays, store.allSpacesAndDisplays)
    }

    // MARK: Reading

    func testReaderPrecedence() throws {
        let store = try Fixtures.store("store-idle-only-allspaces")
        XCTAssertEqual(store.provider(of: .screensaver)?.rawValue, Fixtures.aerialBundleID)
        XCTAssertEqual(store.provider(of: .desktop), .image, "AllSpacesAndDisplays has no Desktop, so SystemDefault answers")
        let displayUUID = try XCTUnwrap(store.displays.keys.sorted().first)
        XCTAssertEqual(store.provider(of: .desktop, in: .display(uuid: displayUUID)), .image)

        let linked = try Fixtures.store("store-linked-default")
        XCTAssertEqual(linked.provider(of: .desktop), .placeholder, "a Linked choice answers for both slots")
        XCTAssertNil(linked.screensaverName())
    }

    func testScreensaverNames() throws {
        let store = try Fixtures.store("store-mixed-allspaces-extension")
        let names = store.screensaverNames()
        XCTAssertTrue(names.contains("AerialScreenSaverExtension"), "module file stem for a screen-saver choice")
        XCTAssertTrue(names.contains(Fixtures.aerialBundleID), "bundle identifier for a wallpaper extension")
        XCTAssertEqual(store.screensaverName(), Fixtures.aerialBundleID)
        XCTAssertEqual(store.screensaverName(in: .space(uuid: "")), Fixtures.aerialBundleID, "AllSpacesAndDisplays wins")
    }
}
