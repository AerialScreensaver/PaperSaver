#!/usr/bin/env swift

import Foundation
import PaperSaver

let paperSaver = PaperSaver()

// Test setting wallpaper for space 4 (UUID: DC708303-97F9-451F-9CF0-E98DBF9A4741)
Task {
    do {
        let imageURL = URL(fileURLWithPath: "/Users/Shared/andreas-sloothsch-w-BSFRpfTWk-unsplash.jpg")
        
        print("Testing wallpaper functionality...")
        print("Setting wallpaper for space 4: \(imageURL.path)")
        
        try await paperSaver.setWallpaperForSpace(
            imageURL: imageURL,
            spaceUUID: "DC708303-97F9-451F-9CF0-E98DBF9A4741",
            screen: nil,
            options: .fill
        )
        
        print("✅ Successfully set wallpaper for space 4")
        
        // Test space 5 too
        let imageURL2 = URL(fileURLWithPath: "/Users/guillaume/Documents/johnny-mcclung-uYTKzVp8loQ-unsplash.jpg")
        
        try await paperSaver.setWallpaperForSpace(
            imageURL: imageURL2,
            spaceUUID: "6CE21993-87A6-4708-80D3-F803E0C6B050",
            screen: nil,
            options: .fill
        )
        
        print("✅ Successfully set wallpaper for space 5")
        
        print("Wallpaper test completed successfully!")
        
    } catch {
        print("❌ Error: \(error)")
    }
}

RunLoop.main.run()