#!/usr/bin/env swift

import Foundation

// This file is just for testing documentation tooltips in Xcode
// Open this file in Xcode and Option+Click on any PaperSaver functions
// to see the documentation comments in Quick Help

func testDocumentation() {
    let paperSaver = PaperSaver()

    // Option+Click on these function calls to see documentation:

    let screensavers = paperSaver.listAvailableScreensavers()
    let current = paperSaver.getActiveScreensaver()
    let active = paperSaver.getActiveScreensavers()

    Task {
        // These should show parameter and throws documentation:
        try await paperSaver.setScreensaver(module: "Aerial")
        try await paperSaver.setScreensaverEverywhere(module: "Aerial")

        if #available(macOS 14.0, *) {
            // These should show availability and advanced parameter docs:
            try await paperSaver.setScreensaverForSpace(module: "Aerial", spaceUUID: "test")
            try await paperSaver.setScreensaverForDisplay(module: "Aerial", displayNumber: 1)
        }
    }

    // Idle time functions:
    let idleTime = paperSaver.getIdleTime()
    try? paperSaver.setIdleTime(seconds: 300)

    // Space and display management:
    if #available(macOS 14.0, *) {
        let activeSpace = paperSaver.getActiveSpace()
        let displays = paperSaver.listDisplays()
        let spaceTree = paperSaver.getNativeSpaceTree()

        // Backup functions:
        let backupInfo = paperSaver.getBackupInfo()
        try? paperSaver.restoreFromBackup()
    }

    // Testing model struct documentation - Option+Click on these types and properties:

    // ScreensaverInfo and its properties
    let screensaverInfo: ScreensaverInfo? = paperSaver.getActiveScreensaver()
    if let info = screensaverInfo {
        print("Name: \(info.name)")           // Option+Click on 'name'
        print("ID: \(info.identifier)")       // Option+Click on 'identifier'
        print("Path: \(info.modulePath ?? "None")")  // Option+Click on 'modulePath'
        print("Screen: \(info.screen?.displayID ?? 0)") // Option+Click on 'screen'
    }

    // ScreensaverModule and ScreensaverType
    let modules = paperSaver.listAvailableScreensavers()
    if let module = modules.first {
        print("Module name: \(module.name)")     // Option+Click on 'name'
        print("Type: \(module.type)")           // Option+Click on 'type'
        print("System: \(module.isSystem)")     // Option+Click on 'isSystem'
        print("Display: \(module.type.displayName)") // Option+Click on 'displayName'
    }

    // SpaceInfo and DisplayInfo
    if #available(macOS 14.0, *) {
        let activeSpace = paperSaver.getActiveSpace()
        if let space = activeSpace {
            print("Space UUID: \(space.uuid)")        // Option+Click on 'uuid'
            print("Current: \(space.isCurrent)")      // Option+Click on 'isCurrent'
            print("Count: \(space.displayCount)")     // Option+Click on 'displayCount'
        }

        let displays = paperSaver.listDisplays()
        if let display = displays.first {
            print("Display name: \(display.friendlyName)")  // Option+Click on 'friendlyName'
            print("Connected: \(display.isConnected)")      // Option+Click on 'isConnected'
            print("Main: \(display.isMain)")               // Option+Click on 'isMain'
        }
    }

    // WallpaperInfo and WallpaperOptions
    let wallpaperInfo = paperSaver.getCurrentWallpaper()
    if let wallpaper = wallpaperInfo {
        print("Image: \(wallpaper.imageName)")      // Option+Click on 'imageName'
        print("Style: \(wallpaper.style)")          // Option+Click on 'style'
        print("Path: \(wallpaper.imagePath)")       // Option+Click on 'imagePath'
    }

    // WallpaperOptions static properties
    let defaultOptions = WallpaperOptions.default   // Option+Click on 'default'
    let fillOptions = WallpaperOptions.fill         // Option+Click on 'fill'
    let fitOptions = WallpaperOptions.fit           // Option+Click on 'fit'

    print("Documentation test file created. Open in Xcode and Option+Click on function calls and properties.")
}