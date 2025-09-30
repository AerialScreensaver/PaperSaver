import Foundation
import PaperSaverKit

@main
struct ShowOutput {
    static func main() {
        print("getActiveScreensavers() output:")
        print(String(repeating: "=", count: 40))

        let paperSaver = PaperSaver()
        let screensavers = paperSaver.getActiveScreensavers()

        print("Found \(screensavers.count) unique screensaver(s) across all spaces on connected displays:")
        print()

        if screensavers.isEmpty {
            print("  (No screensavers found)")
        } else {
            for (index, screensaverName) in screensavers.enumerated() {
                print("  [\(index)] \(screensaverName)")
            }
        }

        print()
        print(String(repeating: "=", count: 40))
    }
}