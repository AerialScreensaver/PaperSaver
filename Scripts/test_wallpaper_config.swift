#!/usr/bin/env swift

import Foundation

// Simple test script for wallpaper configuration testing
class WallpaperConfigTester {
    static let scriptsDir = "/Users/guillaume/dev/PaperSaver/scripts"
    static let captureScript = "\(scriptsDir)/capture_baseline.swift"
    static let compareScript = "\(scriptsDir)/compare_configs.swift"
    static let paperSaverBinary = "/Users/guillaume/dev/PaperSaver/.build/debug/papersaver"
    
    static func main() {
        let args = CommandLine.arguments
        let scriptName = URL(fileURLWithPath: args[0]).lastPathComponent
        
        if args.count < 2 {
            print("Usage: \(scriptName) <command>")
            print("")
            print("Commands:")
            print("  capture-current <label>    - Capture current wallpaper config")
            print("  test-our-config            - Test our wallpaper setting and capture result")
            print("  compare <baseline> <test>  - Compare two configurations")
            print("")
            exit(1)
        }
        
        let command = args[1]
        
        switch command {
        case "capture-current":
            let label = args.count > 2 ? args[2] : "manual-capture"
            captureCurrentConfig(label: label)
            
        case "test-our-config":
            testOurConfiguration()
            
        case "compare":
            if args.count < 4 {
                print("Usage: \(scriptName) compare <baseline.plist> <test.plist>")
                exit(1)
            }
            compareConfigurations(baseline: args[2], test: args[3])
            
        default:
            print("❌ Unknown command: \(command)")
            exit(1)
        }
    }
    
    static func captureCurrentConfig(label: String) {
        print("📸 Capturing current configuration as '\(label)'...")
        
        let task = Process()
        task.launchPath = captureScript
        task.arguments = [label]
        
        task.launch()
        task.waitUntilExit()
        
        if task.terminationStatus == 0 {
            print("✅ Capture completed successfully")
        } else {
            print("❌ Capture failed")
            exit(1)
        }
    }
    
    static func testOurConfiguration() {
        print("🧪 Testing our wallpaper configuration...")
        
        // First capture current state
        print("1. Capturing baseline...")
        captureCurrentConfig(label: "before-our-test")
        
        // Test our wallpaper setting
        print("2. Setting wallpaper with our code...")
        let task = Process()
        task.launchPath = paperSaverBinary
        task.arguments = ["set-paper", "/Users/Shared/test.jpg", "--display", "1", "--space", "4"]
        
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = pipe
        
        task.launch()
        task.waitUntilExit()
        
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: data, encoding: .utf8) ?? ""
        
        if task.terminationStatus == 0 {
            print("✅ Our wallpaper setting succeeded")
        } else {
            print("❌ Our wallpaper setting failed:")
            print(output)
        }
        
        // Capture state after our change
        print("3. Capturing state after our change...")
        captureCurrentConfig(label: "after-our-test")
        
        // Wait a bit then capture again (to see if WallpaperAgent reverts)
        print("4. Waiting 5 seconds then capturing again (to check for reversion)...")
        sleep(5)
        captureCurrentConfig(label: "after-wait")
    }
    
    static func compareConfigurations(baseline: String, test: String) {
        print("🔍 Comparing configurations...")
        
        let task = Process()
        task.launchPath = compareScript
        task.arguments = [baseline, test]
        
        task.launch()
        task.waitUntilExit()
        
        if task.terminationStatus != 0 {
            print("❌ Comparison failed")
            exit(1)
        }
    }
}

WallpaperConfigTester.main()