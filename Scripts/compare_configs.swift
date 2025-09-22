#!/usr/bin/env swift

import Foundation

// Configuration comparison script to analyze differences between working and generated configs
class ConfigComparator {
    static func main() {
        let args = CommandLine.arguments
        let scriptName = URL(fileURLWithPath: args[0]).lastPathComponent
        
        if args.count < 3 {
            print("Usage: \(scriptName) <baseline.plist> <test.plist>")
            print("Example: \(scriptName) baseline-system-ui-2024-01-01.plist current-config.plist")
            exit(1)
        }
        
        let baselinePath = args[1]
        let testPath = args[2]
        
        compareConfigs(baseline: baselinePath, test: testPath)
    }
    
    static func compareConfigs(baseline: String, test: String) {
        do {
            let baselineData = try Data(contentsOf: URL(fileURLWithPath: baseline))
            let testData = try Data(contentsOf: URL(fileURLWithPath: test))
            
            let baselinePlist = try PropertyListSerialization.propertyList(from: baselineData, options: [], format: nil) as? [String: Any]
            let testPlist = try PropertyListSerialization.propertyList(from: testData, options: [], format: nil) as? [String: Any]
            
            print("📊 Configuration Comparison")
            print("Baseline: \(baseline)")
            print("Test: \(test)")
            print("")
            
            guard let baseline = baselinePlist, let test = testPlist else {
                print("❌ Failed to parse plist files")
                exit(1)
            }
            
            // Compare top-level structure
            compareTopLevel(baseline: baseline, test: test)
            
            // Compare Displays section
            compareDisplays(baseline: baseline, test: test)
            
            // Compare Spaces section
            compareSpaces(baseline: baseline, test: test)
            
        } catch {
            print("❌ Error comparing configs: \(error)")
            exit(1)
        }
    }
    
    static func compareTopLevel(baseline: [String: Any], test: [String: Any]) {
        print("🔍 Top-level Keys:")
        let baselineKeys = Set(baseline.keys)
        let testKeys = Set(test.keys)
        
        let common = baselineKeys.intersection(testKeys)
        let onlyBaseline = baselineKeys.subtracting(testKeys)
        let onlyTest = testKeys.subtracting(baselineKeys)
        
        if !common.isEmpty {
            print("  Common: \(common.sorted())")
        }
        if !onlyBaseline.isEmpty {
            print("  ❌ Only in baseline: \(onlyBaseline.sorted())")
        }
        if !onlyTest.isEmpty {
            print("  ❌ Only in test: \(onlyTest.sorted())")
        }
        print("")
    }
    
    static func compareDisplays(baseline: [String: Any], test: [String: Any]) {
        print("🖥️ Displays Section:")
        
        let baselineDisplays = baseline["Displays"] as? [String: Any] ?? [:]
        let testDisplays = test["Displays"] as? [String: Any] ?? [:]
        
        print("  Baseline displays: \(baselineDisplays.count)")
        print("  Test displays: \(testDisplays.count)")
        
        let baselineUUIDs = Set(baselineDisplays.keys)
        let testUUIDs = Set(testDisplays.keys)
        
        for uuid in baselineUUIDs.union(testUUIDs) {
            let inBaseline = baselineUUIDs.contains(uuid)
            let inTest = testUUIDs.contains(uuid)
            
            if inBaseline && inTest {
                print("  ✅ Display \(uuid): in both")
                // Compare the display configs
                if let baselineConfig = baselineDisplays[uuid] as? [String: Any],
                   let testConfig = testDisplays[uuid] as? [String: Any] {
                    compareDisplayConfig(uuid: uuid, baseline: baselineConfig, test: testConfig)
                }
            } else if inBaseline {
                print("  ❌ Display \(uuid): only in baseline")
            } else {
                print("  ❌ Display \(uuid): only in test")
            }
        }
        print("")
    }
    
    static func compareDisplayConfig(uuid: String, baseline: [String: Any], test: [String: Any]) {
        let baselineKeys = Set(baseline.keys)
        let testKeys = Set(test.keys)
        
        let onlyBaseline = baselineKeys.subtracting(testKeys)
        let onlyTest = testKeys.subtracting(baselineKeys)
        
        if !onlyBaseline.isEmpty {
            print("    ❌ Keys only in baseline: \(onlyBaseline.sorted())")
        }
        if !onlyTest.isEmpty {
            print("    ❌ Keys only in test: \(onlyTest.sorted())")
        }
        
        // Compare Desktop configuration if present
        if let baselineDesktop = baseline["Desktop"] as? [String: Any],
           let testDesktop = test["Desktop"] as? [String: Any] {
            compareDesktopConfig(displayUUID: uuid, baseline: baselineDesktop, test: testDesktop)
        }
    }
    
    static func compareDesktopConfig(displayUUID: String, baseline: [String: Any], test: [String: Any]) {
        print("    📄 Desktop config for \(displayUUID):")
        
        // Compare Content section
        if let baselineContent = baseline["Content"] as? [String: Any],
           let testContent = test["Content"] as? [String: Any] {
            
            // Compare Choices
            if let baselineChoices = baselineContent["Choices"] as? [[String: Any]],
               let testChoices = testContent["Choices"] as? [[String: Any]] {
                print("      Choices count - Baseline: \(baselineChoices.count), Test: \(testChoices.count)")
                
                if let baselineChoice = baselineChoices.first,
                   let testChoice = testChoices.first {
                    compareChoice(baseline: baselineChoice, test: testChoice)
                }
            }
            
            // Compare EncodedOptionValues
            let hasBaselineOptions = baselineContent["EncodedOptionValues"] != nil
            let hasTestOptions = testContent["EncodedOptionValues"] != nil
            print("      EncodedOptionValues - Baseline: \(hasBaselineOptions), Test: \(hasTestOptions)")
        }
    }
    
    static func compareChoice(baseline: [String: Any], test: [String: Any]) {
        print("        Choice comparison:")
        print("          Provider - Baseline: \(baseline["Provider"] ?? "nil"), Test: \(test["Provider"] ?? "nil")")
        
        // Compare Configuration data
        let hasBaselineConfig = baseline["Configuration"] != nil
        let hasTestConfig = test["Configuration"] != nil
        print("          Configuration data - Baseline: \(hasBaselineConfig), Test: \(hasTestConfig)")
        
        if let baselineConfig = baseline["Configuration"] as? Data,
           let testConfig = test["Configuration"] as? Data {
            print("          Configuration size - Baseline: \(baselineConfig.count) bytes, Test: \(testConfig.count) bytes")
            
            // Try to decode and compare the configuration
            do {
                let baselinePlist = try PropertyListSerialization.propertyList(from: baselineConfig, options: [], format: nil)
                let testPlist = try PropertyListSerialization.propertyList(from: testConfig, options: [], format: nil)
                print("          Configuration decoded successfully for both")
                print("          Baseline config: \(baselinePlist)")
                print("          Test config: \(testPlist)")
            } catch {
                print("          ❌ Failed to decode configuration data: \(error)")
            }
        }
    }
    
    static func compareSpaces(baseline: [String: Any], test: [String: Any]) {
        print("🚀 Spaces Section:")
        
        let baselineSpaces = baseline["Spaces"] as? [String: Any] ?? [:]
        let testSpaces = test["Spaces"] as? [String: Any] ?? [:]
        
        print("  Baseline spaces: \(baselineSpaces.count)")
        print("  Test spaces: \(testSpaces.count)")
        
        let baselineUUIDs = Set(baselineSpaces.keys)
        let testUUIDs = Set(testSpaces.keys)
        
        for uuid in baselineUUIDs.union(testUUIDs) {
            let inBaseline = baselineUUIDs.contains(uuid)
            let inTest = testUUIDs.contains(uuid)
            
            if inBaseline && inTest {
                print("  ✅ Space \(uuid): in both")
            } else if inBaseline {
                print("  ❌ Space \(uuid): only in baseline")
            } else {
                print("  ❌ Space \(uuid): only in test")
            }
        }
        print("")
    }
}

ConfigComparator.main()