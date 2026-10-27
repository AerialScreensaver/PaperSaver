# PaperSaver

A Swift package that selects the screensaver and the desktop wallpaper on macOS, including
app-extension screensavers and third-party wallpaper extensions that the public APIs cannot
select.

[![Swift](https://img.shields.io/badge/Swift-6.0%2B-orange.svg)](https://swift.org)
[![Platform](https://img.shields.io/badge/macOS-14%2B-blue.svg)](https://developer.apple.com/macos/)
[![License](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

PaperSaver rewrites the wallpaper store System Settings reads
(`~/Library/Application Support/com.apple.wallpaper/Store/Index.plist`), restarts
`WallpaperAgent`, which reads the store only when it starts, waits for the agent to settle,
reads the store back and rolls the write back if the agent did not keep it. Static image
wallpapers go through `NSWorkspace`, which applies them at once without a restart.

The store is not a documented interface. Apple can change it in any macOS release, and
PaperSaver's verify-and-roll-back step is the safety net, not a guarantee. Keep a backup of
the store before scripting against it (PaperSaver writes `Index.plist.backup` before every
change).

## Requirements

- macOS 14 (Sonoma) or later. Measured on macOS 26 and 27; 14 and 15 untested.
- Swift 6.0 or later (Xcode 16 or later) for the library. CI builds and tests with the latest
  Xcode only.

## Installation

```swift
dependencies: [
    .package(url: "https://github.com/AerialScreensaver/PaperSaver.git", from: "0.4.0")
]
```

In Xcode: File → Add Package Dependencies…, enter the repository URL and choose
"Up to Next Major Version" from 0.4.0. Link the `PaperSaverKit` product.

## Library

```swift
import PaperSaverKit

let paperSaver = PaperSaver()
```

### Select a screensaver by name

A screensaver is named after its bundle's file name without extension, as System Settings
lists it when the bundle has no display name. `.saver` plug-ins and app-extension screensavers
(the format Apple's own screensavers use) both work; the extension must be registered with
`pluginkit` first.

```swift
// Is the sample's extension already selected somewhere?
let active = paperSaver.getActiveScreensavers()          // ["AppexSaverMinimalExtension"]
if !active.contains("AppexSaverMinimalExtension") {
    // Writes the store, restarts WallpaperAgent, verifies.
    try await paperSaver.setScreensaverEverywhere(module: "AppexSaverMinimalExtension")
}

// Per display or per Space:
try await paperSaver.setScreensaver(module: "Flurry", target: .display(uuid: displayUUID))
let info = paperSaver.activeScreensaver(in: .everywhere)  // ScreensaverInfo: name, kind, modulePath…
```

Selecting a screensaver leaves the desktop wallpaper alone. When a section has no desktop
choice, PaperSaver writes a `Type = idle` section holding only the screensaver if another
section of the store provides the desktop (the agent writes that shape itself when desktops
are per Space), and otherwise an `individual` section with the system default wallpaper next
to the screensaver, because the agent resets a store that holds only screensaver slots.
`PaperSaverConfiguration.screensaverOnlyStrategy` forces either shape.

### Put a wallpaper extension in a slot

A wallpaper extension (an app extension on the `com.apple.wallpaper` extension point, such as
[Aerial](https://github.com/AerialScreensaver/Aerial) 4.1) is identified by its bundle
identifier and can serve as the desktop wallpaper, the screensaver, or both.
Screensaver extensions (`com.apple.screensaver`, like Apple's Flurry) are a different kind:
select them by name with `setScreensaver(module:)`. `setWallpaperExtension` checks the bundle
identifier against the pluginkit registry first and throws `wallpaperExtensionNotFound`, with
a pointer to `setScreensaver` when the identifier is a screensaver extension, because the
agent would otherwise store any string and fail to render it.

```swift
let aerial = "com.glouel.Aerial-App.Aerial4WallpaperExtension"

// Desktop wallpaper. The screensaver is left as it is.
try await paperSaver.setWallpaperExtension(bundleID: aerial, configuration: Data("aerial".utf8), slot: .desktop)

// Screensaver. The wallpaper is left as it is.
try await paperSaver.setWallpaperExtension(bundleID: aerial, slot: .screensaver)

// Both, in one store write and one agent restart.
try await paperSaver.setWallpaperExtension(bundleID: aerial, configuration: Data("aerial".utf8), slots: [.desktop, .screensaver])

// Remove the extension from a slot.
try await paperSaver.clearWallpaperExtension(slot: .screensaver)

paperSaver.getCurrentWallpaperExtension()     // "com.glouel.Aerial-App.Aerial4WallpaperExtension" or nil
paperSaver.getCurrentScreensaverExtension()   // nil
```

Writing one slot never touches the other. `otherSlot:` opts into something else:
`.clearIfSameProvider` (remove the same extension from the other slot),
`.clearToSystemDefault` or `.mirror`. The desktop slot needs a placement and
a background colour or the agent rejects the choice; `setWallpaperExtension` supplies both
unless you pass `optionValues:`.

### Set a static image

```swift
// Applies at once through NSWorkspace; no agent restart.
try await MainActor.run {
    try paperSaver.setWallpaper(imageURL: url, on: .all, placement: .fill)
}
let current = await MainActor.run { paperSaver.getCurrentWallpaper(for: .main) }
```

`setWallpaper(imageURL:target:)` writes an image into the store instead, for Spaces that are
not on screen.

### Advanced

- `WriteOptions` controls each write: `restartAgent`, `verify`, `rollbackOnFailure`, the
  respawn, quiet and settle timeouts, and the extension launch check (`extensionLaunchTimeout`,
  `extensionRelaunchAttempts`). `.noRestart` writes the file and stops.
- `StoreTarget` addresses the whole store (`.everywhere`), a Space, a display, or a Space on a
  display. `displaySpaces()` lists the connected displays with their Spaces and UUIDs.
- `readStore()` returns the store as typed values (`WallpaperStore`, `StoreSection`,
  `SlotConfiguration`, `OptionValues`); unknown content round-trips untouched.
  `StoreSummary` turns it into something printable or encodable.
- `PaperSaverConfiguration` sets the store URL (for tests), the log destination
  (`PaperSaverLog.os`, `.silent` or `.standardError`), the pluginkit cache lifetime, the
  screensaver-only strategy and the system default choice.
- `PluginkitCatalog` lists, registers and unregisters app extensions; `DisplayTopology`,
  `MissionControlSpaces` and `WindowServerDisplays` expose the system data the facade uses.
- `backupInfo()` and `restoreFromBackup()` use the `Index.plist.backup` file written before
  every change.
- `repairLegacyOptionValues()` fixes stores written by PaperSaver 0.3.1 and earlier, whose
  desktop background colour WallpaperAgent cannot decode ("Failed to decode option values for
  wallpaper"). It returns `nil` without writing when there is nothing to repair, so an app
  can call it once at launch.

## Command line

```sh
swift build -c release --product papersaver
.build/release/papersaver --help
```

| Command | What it does |
|---|---|
| `list [--json] [--verbose]` | Installed screensavers (pluginkit extensions and `.saver` plug-ins). |
| `get [targeting] [--json]` | The selected screensaver. |
| `set-saver NAME [targeting] [--no-restart] [--no-verify]` | Select a screensaver by name. |
| `get-paper [--display N \| --display-uuid U] [--json]` | The static image NSWorkspace reports for a display. |
| `set-paper IMAGE [--display N \| --display-uuid U] [--placement fill\|fit\|stretch\|center]` | Static image through NSWorkspace; `--space-uuid S` writes the store instead. |
| `wallpaper-extension get [--json]` | The extension in each slot. |
| `wallpaper-extension list [--json] [--verbose]` | The registered wallpaper extensions (bundle identifiers to pass to `set`). |
| `wallpaper-extension set BUNDLE_ID --slot desktop\|screensaver\|both [--other keep\|clear\|clear-if-same\|mirror] [--config TOKEN] [--strategy automatic\|idle-section\|materialize-desktop]` | Put an extension in a slot. |
| `wallpaper-extension clear --slot desktop\|screensaver` | Put the system default back. |
| `list-displays [--json]`, `list-spaces [--json]`, `get-space [--json]` | Displays, Spaces and the Space on screen. |
| `idle-time get\|set SECONDS` | The delay before the screensaver starts. |
| `store dump [--json]` | Every store section with its providers and option keys. |
| `repair-options [--dry-run] [--no-restart]` | Repair the background colour PaperSaver 0.3.1 and earlier wrote one level too deep. |
| `restore-backup [--force] [--no-restart]` | Put back the store as it was before the last write. |

Targeting flags: `--display N` or `--display-uuid U`, `--space N` or `--space-uuid S`, as
`list-displays` and `list-spaces` print them. Without them a command addresses every display
and Space.

## Store format notes

What PaperSaver reads and writes, as observed on macOS 14 through 27:

- Top-level sections `AllSpacesAndDisplays` and `SystemDefault`, plus per-Space sections under
  `Spaces[<space UUID>]` (`Default` and `Displays[<display UUID>]`) and per-display sections
  under `Displays[<display UUID>]`. Reads consult `AllSpacesAndDisplays`, then the sections
  specific to the target, then `SystemDefault`.
- A section has a `Type`: `linked` (automatic mode, one `Linked` choice for both roles),
  `individual` (`Desktop` and `Idle`), or `idle` (only `Idle`; the desktop comes from a
  lower-precedence section).
- A slot is `{Content: {Choices: [{Provider, Configuration, Files}], EncodedOptionValues,
  Shuffle}, LastSet, LastUse}`. `Provider` is `com.apple.wallpaper.choice.image`,
  `com.apple.wallpaper.choice.screen-saver`, `com.apple.wallpaper.extension.photos`, a
  wallpaper extension's bundle identifier, or `com.apple.NeptuneOneExtension` for the macOS 26
  default. `Configuration` is a binary plist (`{module: {relative: file:///….appex}}` for a
  screensaver, `{type: imageFile, url: {relative: …}}` for an image) or an opaque token.
- `EncodedOptionValues` is a binary plist of `{"values": {…}}`: `placement.picker._0.id`
  (`Crop` = fill, `SizeToFit` = fit, `FillScreen` = stretch, `Centered` = center),
  `color.color._0.color.{components, colorSpace}`, `appearance.picker._0.id`,
  `shuffleFrequency.picker._0.id`, `shuffleRandomly.toggle._0.isOn`. Screensaver choices carry
  the string `"$null"` instead. `Shuffle` is the string `"$null"`.
- The agent silently resets a section it cannot decode, so an image or extension desktop
  choice must carry both a placement and a colour, `Linked` must go when a section becomes
  `individual`, and an `individual` section must hold both slots. Measured on macOS 27.2: a
  store whose sections hold only `Idle` slots is reset to the `default` placeholder (the
  screensaver is lost); `Type = idle` on top of an `individual` `SystemDefault` is kept, and
  the agent then creates per-Space sections; an `individual` section with the `default`
  placeholder in `Desktop` is kept.
- The placeholder the agent writes when nothing is set is provider `default`, empty
  configuration, and the string `"$null"` for both `EncodedOptionValues` and `Shuffle`.
- `NSWorkspace.setDesktopImageURL` for one display switches the store to per-Space mode: the
  agent creates `Spaces[…]` and `Displays[…]` sections for every Space, puts the image in the
  current Space's sections with a placement and a colour, and sets `AllSpacesAndDisplays` to
  `Type = idle` with the placeholder.
- `WallpaperAgent` rewrites the store on every start; verification waits for the file to stay
  unchanged, then re-reads it.

## Limitations

- Clearing a slot writes the macOS 26 default (`com.apple.NeptuneOneExtension`). The default
  choice of macOS 14 and 15 has not been captured, so there PaperSaver writes the agent's
  `default` placeholder instead, which macOS 27 accepts and macOS 14 and 15 have not been
  tested with.
- Store verification only sees the store. On macOS 27.2 about one agent restart in three
  failed to connect the wallpaper extension it had to launch (ExtensionKit error 2 while the
  previous instance was being torn down) and the agent did not retry. After a desktop
  extension write PaperSaver therefore waits for the extension's process and restarts the
  agent once more when it does not appear; `WriteOutcome.appliedButExtensionNotRunning`
  reports the case where that was not enough. Keep one registration per extension: with two
  (a build in DerivedData and a copy in /Applications) the registry elects either one on
  each launch.
- Per-Space image wallpapers through the store are best effort; `NSWorkspace` is the supported
  path for static images.
- The private XPC interface of `WallpaperAgent` accepts calls from third-party processes but
  ignores them without Apple's entitlements, so PaperSaver does not use it.
- Restarting the agent redraws the desktop once.

## Development

```sh
swift build
swift test                                   # unit tests on captured store fixtures; nothing touches your Mac
PAPERSAVER_INTEGRATION=1 swift test --filter LiveReadOnlyTests   # reads the real store, pluginkit, displays
PAPERSAVER_MUTATION=1 swift test --filter LiveMutationTests      # rewrites your store and restarts the agent, then restores
```

On a Mac where `swift` on `PATH` is a swiftly or open-source toolchain, build with Xcode's:
`xcrun swift build`.

The fixtures under `Tests/PaperSaverTests/Fixtures` are stores System Settings and
WallpaperAgent wrote on real Macs (user names scrubbed); see the README there.

## License

MIT. See [LICENSE](LICENSE).
