# PaperSaver

> ⚠️ **Work in Progress** 
> 
> This project is currently under active development and is **not yet ready for production use**. 
> APIs may change without notice, features may be incomplete, and breaking changes are expected.
> Use at your own risk.

[![Swift](https://img.shields.io/badge/Swift-6.2-orange.svg)](https://swift.org)
[![Platform](https://img.shields.io/badge/Platform-macOS%2010.15%2B-blue.svg)](https://developer.apple.com/macos/)
[![SPM Compatible](https://img.shields.io/badge/SPM-Compatible-brightgreen.svg)](https://swift.org/package-manager/)
[![Development Status](https://img.shields.io/badge/Status-Work%20in%20Progress-red.svg)](#)
[![License](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

A Swift package for programmatic control over screensavers and wallpapers on macOS, with special support for per-screen/space configuration introduced in macOS Sonoma.

## Features

> 📝 **Development Status**: Features marked with status indicators

- 🖥️ **Screensaver Management**: Set and configure screensavers programmatically ⚠️ *Partially implemented*
- 🎨 **Wallpaper Control**: Change desktop wallpapers for individual or all screens ⚠️ *Partially implemented*
- 🚀 **macOS Sonoma Support**: Support for per-screen/space configuration system ⚠️ *Partially implemented*
- 🔄 **Pre-Sonoma Compatibility**: Legacy support for older macOS versions ⚠️ *Partially implemented*
- 📦 **Swift Package Manager**: Easy integration into your Swift projects ⚠️ *Partially implemented*
- 🧪 **Type-Safe API**: Leverage Swift's type system for safe configuration ⚠️ *Partially implemented*
- 🔧 **CLI Tool**: Command-line interface for testing and automation ⚠️ *Partially implemented*
## Requirements

- macOS 10.15 (Catalina) or later
- Swift 6.2 or later
- Xcode 14.0 or later (for development)

## Installation

> ⚠️ **Development Version Only**  
> This package is not yet published to a stable release. You can only install the development version.

### Swift Package Manager

Add PaperSaver to your `Package.swift` file:

```swift
dependencies: [
    .package(url: "https://github.com/AerialScreensaver/PaperSaver.git", branch: "main")
]
```

Or add it through Xcode:
1. File → Add Package Dependencies...
2. Enter the repository URL: `https://github.com/AerialScreensaver/PaperSaver.git`
3. Select "Branch" and enter `main`
4. Click "Add Package"


## Usage

### Basic Example

```swift
import PaperSaver

// Initialize the manager
let paperSaver = PaperSaver()

// Set screensaver for main display
try await paperSaver.setScreensaver(module: "Aerial", for: .main)

// Get current configuration
if let screensaver = paperSaver.getActiveScreensaver(for: .main) {
    print("Current screensaver: \(screensaver.name)")
}
```

### Setting Screensaver Idle Time

```swift
// Set screensaver to activate after 5 minutes of inactivity
try paperSaver.setIdleTime(seconds: 300)
```

### Listing Available Screensavers

```swift
let availableScreensavers = paperSaver.listAvailableScreensavers()
for screensaver in availableScreensavers {
    print("\(screensaver.name): \(screensaver.identifier)")
}
```

## macOS Version Compatibility

PaperSaver automatically detects the macOS version and uses the appropriate method for managing screensavers and wallpapers:

- **macOS Sonoma (14.0) and later**: Uses the new per-screen/space configuration system via `com.apple.wallpaper`
- **Pre-Sonoma versions**: Falls back to traditional `com.apple.screensaver` preferences and NSWorkspace APIs

## Development

### Building from Source

```bash
git clone https://github.com/AerialScreensaver/PaperSaver.git
cd PaperSaver
swift build
```

### Running Tests

```bash
swift test
```

### Using the CLI Tool

The project includes a command-line interface for testing and development:

```bash
# Build and run the CLI
swift run papersaver-cli --help

# List available screensavers
swift run papersaver-cli list

# List spaces (macOS Sonoma+)
swift run papersaver-cli list-spaces

# Set a screensaver
swift run papersaver-cli set Aerial
```

### Current Development Focus

- Improving wallpaper management functionality
- Enhanced error handling and validation
- Comprehensive test coverage
- Documentation and examples

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## Contributing & Support

> ⚠️ **Development Project**: Please keep in mind this is a work-in-progress when reporting issues.

### Questions & Support

For questions, suggestions, or feature requests, please [open an issue](https://github.com/AerialScreensaver/PaperSaver/issues) on GitHub.

