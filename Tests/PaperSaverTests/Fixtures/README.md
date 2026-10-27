# Test fixtures

Stores written by System Settings and WallpaperAgent on macOS 26/27, captured from real
Macs (user names replaced by `user`, per-space and per-display sections trimmed to three
entries). They pin the exact shapes the library must read and write.

| File | Provenance | What it shows |
|---|---|---|
| `store-mixed-allspaces-extension.plist` | macOS 27, 4 displays, 21 spaces | `AllSpacesAndDisplays` written by PaperSaver 0.3.1 (extension in both slots, the mis-nested colour), `SystemDefault` written by System Settings (image Desktop with the correct colour shape, `screen-saver` appex Idle with the `"$null"` option-values string), per-space and per-display sections |
| `store-idle-only-allspaces.plist` | macOS 27, 7 displays, 10 spaces | `AllSpacesAndDisplays` with `Type = idle` and only an Idle slot; `SystemDefault` individual |
| `store-photos-collection.plist` | macOS 27 | Photos collection Desktop (`shuffleFrequency`), Idle slot carrying `appearance`, `color`, `placement`, `shuffleRandomly` option values |
| `store-extension-both-slots.plist` | macOS 27.2 | The same wallpaper extension in both slots, no per-space sections; written by PaperSaver 0.3.1, so both Desktop slots carry the mis-nested colour |
| `store-linked-default.plist` | synthesized from the agent's reset output (macOS 27.2) | Automatic mode: `Type = linked` with the agent's `default` placeholder (`EncodedOptionValues` is the string `$null`) |
| `store-agent-perspace-image.plist` | macOS 27.2, written by WallpaperAgent after `NSWorkspace.setDesktopImageURL` on one display | `AllSpacesAndDisplays` with `Type = idle` holding the placeholder, per-Space and per-display sections created by the agent, one `individual` section with the image (correct colour shape) and a placeholder Idle |
| `optionvalues-image-system.bplist` | from the first store | Raw `EncodedOptionValues` bytes System Settings wrote for an image Desktop |
| `pluginkit-output.txt` | macOS 27.2 | `pluginkit -m -v -p com.apple.screensaver` output |
