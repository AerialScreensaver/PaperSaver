# Changelog

All notable changes to PaperSaver. The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [0.4.0] - Unreleased

### Breaking

- Minimum macOS is 14; the pre-Sonoma code paths and the `@available(macOS 14.0, *)` gates are gone.
- `swift-tools-version` is 6.0 (Xcode 16 or later) and the package builds in Swift 6 language mode. 6.2 required Xcode 26 and could not be consumed from Swift 6.1 (#2).
- `PaperSaver` is a `final class` and `Sendable`, created with `PaperSaver(configuration:)`. `init(screensaverManager:wallpaperManager:)` and the `ScreensaverManaging`/`WallpaperManaging` protocols are gone.
- `setWallpaperExtension` takes `slot: WallpaperSlot` (`.desktop` or `.screensaver`; `.both` is gone), an `otherSlot: OtherSlotPolicy` (default `.clearIfSameProvider`), typed `OptionValues`, a `StoreTarget` and `WriteOptions`, and returns a `WriteOutcome`.
- `getCurrentWallpaperExtension`/`getCurrentScreensaverExtension` take `in: StoreTarget` instead of an `NSScreen` they ignored.
- `getActiveScreensaver(for:)` takes a `DisplayTarget`; `activeScreensaver(in:)` takes a `StoreTarget`. `ScreensaverInfo` gained `provider`, `kind` and `displayUUID`.
- `setScreensaver(module:target:options:)` replaces `setScreensaver(module:for:…)`, `setScreensaverForSpace`, `setScreensaverForSpaceID`, `setScreensaverForDisplay` and `setScreensaverForDisplaySpace`. `enableDebug:` parameters are gone; use `PaperSaverConfiguration.log`.
- Static images: `setWallpaper(imageURL:on:placement:fillColor:)` (NSWorkspace, `@MainActor`) and `setWallpaper(imageURL:target:optionValues:options:)` (store) replace `setWallpaper(imageURL:screen:options:)`, `setWallpaperEverywhere` and the `setWallpaperFor*` family. `WallpaperOptions` and `WallpaperStyle` are replaced by `WallpaperPlacement`; `WallpaperInfo` carries a placement instead of a style.
- `getNativeSpaceTree() -> [String: Any]` is replaced by `displaySpaces() -> [DisplaySpaces]`.
- `getBackupInfo()` is `backupInfo() -> BackupInfo?`; `restoreFromBackup()` is `async` and restarts the agent by default.
- `PlistManager`, `PluginkitManager`, `SpacesManager` and `WindowServerDisplayManager` are gone; use `StoreFile`, `PluginkitCatalog`, `MissionControlSpaces` and `WindowServerDisplays`.
- `PaperSaverError` lost its never-thrown cases and gained `verificationFailed`, `agentRestartFailed` and `pluginkitFailed`. `PluginkitError` is gone.
- `ScreensaverType.providerIdentifier` is `provider: ChoiceProvider?`, and app-extension screensavers now map to `com.apple.wallpaper.choice.screen-saver` (they were wrongly mapped to the macOS 26 default wallpaper). New case `.wallpaperExtension`. `ScreensaverModule.thumbnail` is gone; `bundleIdentifier` is new.
- The `show-output` product, the research scripts under `Scripts/` and the stale planning documents are gone.

### Fixed

- The desktop background colour was nested one level too deep (`values.color.color.color._0…`), so WallpaperAgent logged `Failed to decode option values for wallpaper: Key '_0' not found` on every start and dropped the placement. The shape now matches what System Settings writes.
- Setting a screensaver only, on a Mac with no desktop choice, copied the screensaver into the desktop slot (the same extension in both slots breaks macOS 26 and 27). A screensaver-only write now keeps `Type = idle` sections when another section provides the desktop and otherwise writes the system default wallpaper next to the screensaver; measured on macOS 27.2, the agent rejects a store that holds only screensaver slots.
- `Index.plist.backup` was written once and never refreshed, so every rollback restored the oldest store. Every write now refreshes it, and a failed write rolls back to the exact bytes it replaced.
- Verification waited a fixed three seconds; it now waits for a new `WallpaperAgent` process and for the store file to stop changing, then reads it back. The extension write path never rolled back; it does now.
- The image wallpaper path read `display_uuid`/`space_uuid` keys that the topology never produced, so it always failed with "Display N not found".
- `getActiveScreensaver(for:)` and `getCurrentWallpaper(for:)` compared a display UUID with a numeric display identifier and never matched. Targets are UUIDs throughout now.
- CLI: `--display-uuid` was accepted and ignored; `get --screen` targeted the main screen whatever the value; `restore-backup` did not restart the agent; the version string said 0.1.0.
- `CGSCopyManagedDisplaySpaces` was declared non-optional and force-cast.
- `Process` used the deprecated `launchPath`/`launch()` and the restart was never awaited.
- `ColorSync` answers `CGDisplayGetDisplayIDFromUUID` with the main display for some unknown UUIDs; `DisplayUUID.displayID(for:)` cross-checks the result.

### Added

- Typed store model: `WallpaperStore`, `StoreSection`, `SlotConfiguration`, `WallpaperChoice`, `ChoiceProvider`, `ChoiceConfiguration`, `OptionValues`, `PlistValue` (unknown content round-trips untouched), `StoreSummary`, `readStore()`.
- `clearWallpaperExtension(slot:)` and `OtherSlotPolicy`, so an extension can move between slots without ending up in both. The cleared slot gets `com.apple.NeptuneOneExtension` on macOS 26 and later and the agent's `default` placeholder before that.
- `setWallpaperExtension` refuses a bundle identifier that is not registered on the `com.apple.wallpaper` extension point (`PaperSaverError.wallpaperExtensionNotFound`), and says to use `setScreensaver(module:)` when it names a screensaver extension. The agent would store the string and fail with "no provider found". `PaperSaverConfiguration.validatesWallpaperExtensions` turns the check off; `listWallpaperExtensions()` and `papersaver wallpaper-extension list` show the registry.
- `ScreensaverOnlyStrategy` (`.automatic`, `.idleSection`, `.materializeSystemDefaultDesktop`) and `WallpaperStore.hasAnyDesktopChoice`.
- `OptionValues.Placement` constants for the four store placement ids (`Crop`, `SizeToFit`, `FillScreen`, `Centered`) and `WallpaperPlacement.storePlacement`.
- `StoreTarget` for per-Space and per-display writes, including `--space`/`--space-uuid`/`--display`/`--display-uuid` on every CLI command that takes a target.
- `WriteOptions`/`WriteOutcome`, `PaperSaverConfiguration`, `PaperSaverLog` (unified log by default), `PluginkitCatalog` with a short cache, `DisplayTopology`.
- After a desktop extension write, the library waits for the extension's process and restarts the agent once more if it did not launch (measured: about one restart in three on macOS 27.2 fails to connect the extension and the agent does not retry). `WallpaperAgent.runningExtensionBundleIdentifiers()` exposes the check.
- CLI: `wallpaper-extension clear`, `wallpaper-extension set --strategy`, `get-paper`, `store dump`, `--no-verify`, `--no-rollback`, `set-paper --placement`.
- Fixture-based unit tests built from stores captured on real Macs; live tests gated behind `PAPERSAVER_INTEGRATION` and `PAPERSAVER_MUTATION`.
- GitHub Actions workflow building and testing on macOS 15 and macOS 26.
- This changelog.

## [0.3.1] - 2026-06-29

- Non-destructive single-slot extension writes: preserve the other slot, materialise a Linked choice, else mirror.
- Test suite imports fixed.

## [0.3.0] - 2026-06-29

- `setWallpaperExtension`, `getCurrentWallpaperExtension`, `getCurrentScreensaverExtension` and the `wallpaper-extension` CLI command for third-party wallpaper extensions.

## [0.2.1] - 2026-02-10

- pluginkit-based discovery of app-extension screensavers; setting third-party appex savers.

## [0.2.0] - 2026-02-01

- swift-argument-parser based CLI.

## [0.1.0] - 2025-09-30

- First release: screensaver selection through the wallpaper store on macOS Sonoma and later, Spaces and displays, backup and auto-rollback.
