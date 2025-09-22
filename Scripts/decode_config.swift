#!/usr/bin/env swift

import Foundation

// Quick script to decode base64 configuration data from plists
if CommandLine.arguments.count < 2 {
    print("Usage: decode_config.swift <base64_string>")
    exit(1)
}

let base64String = CommandLine.arguments[1]

guard let data = Data(base64Encoded: base64String) else {
    print("❌ Invalid base64 string")
    exit(1)
}

do {
    let plist = try PropertyListSerialization.propertyList(from: data, options: [], format: nil)
    print("📄 Decoded configuration:")
    print(plist)
} catch {
    print("❌ Failed to decode: \(error)")
    exit(1)
}