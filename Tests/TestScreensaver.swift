import Foundation
import PaperSaverKit

@main
struct TestScreensaver {
    static func main() async {
        let manager = ScreensaverManager()
        
        print("Testing PaperSaver Screensaver Management...")
        print("============================================")
        
        print("\n1. Listing available screensavers:")
        let screensavers = manager.listAvailableScreensavers()
        for saver in screensavers {
            print("  - \(saver.name) (\(saver.isSystem ? "System" : "User"))")
        }
        
        print("\n2. Getting current screensaver:")
        if let current = manager.getActiveScreensaver(for: nil) {
            print("  Current screensaver: \(current.name)")
        } else {
            print("  No screensaver currently set")
        }
        
        print("\n3. Getting idle time:")
        let idleTime = manager.getIdleTime()
        print("  Idle time: \(idleTime) seconds")
        
        print("\n4. Testing screensaver setting:")
        do {
            print("  Setting screensaver to 'Fliqlo'...")
            try await manager.setScreensaver(module: "Fliqlo", screen: nil)
            print("  ✅ Successfully set screensaver!")
            
            if let newCurrent = manager.getActiveScreensaver(for: nil) {
                print("  Verified: Current screensaver is now \(newCurrent.name)")
            }
        } catch {
            print("  ❌ Failed to set screensaver: \(error)")
        }
        
        print("\n5. Testing idle time setting:")
        do {
            print("  Setting idle time to 300 seconds (5 minutes)...")
            try manager.setIdleTime(seconds: 300)
            print("  ✅ Successfully set idle time!")
            
            let newIdleTime = manager.getIdleTime()
            print("  Verified: Idle time is now \(newIdleTime) seconds")
        } catch {
            print("  ❌ Failed to set idle time: \(error)")
        }
        
        print("\nTest complete!")
    }
}