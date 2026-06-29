import Foundation
import AppKit

// MARK: - Load private framework

guard dlopen("/System/Library/PrivateFrameworks/Wallpaper.framework/Wallpaper", RTLD_NOW) != nil else {
    fatalError("Failed to load Wallpaper.framework: \(String(cString: dlerror()))")
}

// MARK: - Private API Bindings

@_silgen_name("$s9Wallpaper23setLegacyDesktopPicture_5space7displayySDys11AnyHashableVypG_S2StKF")
func _setLegacyDesktopPicture(_ config: [AnyHashable: Any], space: String, display: String) throws

// Version with audit token
@_silgen_name("$s9Wallpaper23setLegacyDesktopPicture_5space7display17onBehalfOfProcessySDys11AnyHashableVypG_S2SSo13audit_token_taSgtKF")
func _setLegacyDesktopPictureOnBehalf(_ config: [AnyHashable: Any], space: String, display: String, onBehalfOfProcess: audit_token_t?) throws

func getMainDisplayUUID() -> String {
    let mainID = CGMainDisplayID()
    guard let uuidRef = ColorSync.CGDisplayCreateUUIDFromDisplayID(mainID) else {
        fatalError("Could not get UUID for main display")
    }
    return CFUUIDCreateString(nil, uuidRef.takeUnretainedValue())! as String
}

// MARK: - Test

guard let screen = NSScreen.main else { fatalError("No main screen") }
let displayUUID = getMainDisplayUUID()

print("Display: \(displayUUID)")
print("Current: \(NSWorkspace.shared.desktopImageURL(for: screen)?.path ?? "nil")")

// Step 1: Does NSWorkspace still work?
print("\n=== Test 1: NSWorkspace.setDesktopImageURL ===")
let testURL = URL(fileURLWithPath: "/Users/Shared/test.jpg")
do {
    try NSWorkspace.shared.setDesktopImageURL(testURL, for: screen, options: [:])
    Thread.sleep(forTimeInterval: 1.5)
    print("After NSWorkspace: \(NSWorkspace.shared.desktopImageURL(for: screen)?.path ?? "nil")")
} catch {
    print("NSWorkspace ERROR: \(error)")
}

// Reset to Sonoma
let sonomaURL = URL(fileURLWithPath: "/System/Library/Desktop Pictures/Sonoma.heic")
do {
    try NSWorkspace.shared.setDesktopImageURL(sonomaURL, for: screen, options: [:])
    Thread.sleep(forTimeInterval: 1.5)
    print("Reset to: \(NSWorkspace.shared.desktopImageURL(for: screen)?.path ?? "nil")")
} catch {
    print("Reset ERROR: \(error)")
}

// Step 2: Try private API without audit token
print("\n=== Test 2: Private API (no audit token) ===")
do {
    try _setLegacyDesktopPicture(["ImageFilePath": "/Users/Shared/test.jpg"], space: "", display: displayUUID)
    Thread.sleep(forTimeInterval: 1.5)
    print("After private API: \(NSWorkspace.shared.desktopImageURL(for: screen)?.path ?? "nil")")
} catch {
    print("Private API ERROR: \(error)")
}

// Reset again
try? NSWorkspace.shared.setDesktopImageURL(sonomaURL, for: screen, options: [:])
Thread.sleep(forTimeInterval: 1.5)

// Step 3: Try private API WITH audit token (our own process token)
print("\n=== Test 3: Private API (with audit token) ===")
var token = audit_token_t()
// Get our own audit token via mach_task_self
var size = mach_msg_type_number_t(MemoryLayout<audit_token_t>.size / MemoryLayout<natural_t>.size)
task_info(mach_task_self_, task_flavor_t(TASK_AUDIT_TOKEN), withUnsafeMutablePointer(to: &token) {
    $0.withMemoryRebound(to: Int32.self, capacity: Int(size)) { ptr in
        ptr
    }
}, &size)

do {
    try _setLegacyDesktopPictureOnBehalf(
        ["ImageFilePath": "/Users/Shared/test.jpg"],
        space: "", display: displayUUID, onBehalfOfProcess: token
    )
    Thread.sleep(forTimeInterval: 1.5)
    print("After private+token: \(NSWorkspace.shared.desktopImageURL(for: screen)?.path ?? "nil")")
} catch {
    print("Private+token ERROR: \(error)")
}

print("\nDone.")
