import Foundation

public enum PaperSaverError: LocalizedError {
    case unsupportedOperation(String)
    case fileNotFound(URL)
    case permissionDenied(String)
    case invalidConfiguration(String)
    case plistReadError(String)
    case plistWriteError(String)
    case screensaverNotFound(String)
    case spaceNotFound
    case displayNotFound(Int)
    case spaceNotFoundOnDisplay(displayNumber: Int, spaceNumber: Int)
    case sonomaRequired
    case invalidScreenIdentifier
    case systemVersionDetectionFailed
    case unknownError(Error)
    
    public var errorDescription: String? {
        switch self {
        case .unsupportedOperation(let operation):
            return "Unsupported operation: \(operation)"
        case .fileNotFound(let url):
            return "File not found: \(url.path)"
        case .permissionDenied(let reason):
            return "Permission denied: \(reason)"
        case .invalidConfiguration(let details):
            return "Invalid configuration: \(details)"
        case .plistReadError(let path):
            return "Failed to read plist: \(path)"
        case .plistWriteError(let path):
            return "Failed to write plist: \(path)"
        case .screensaverNotFound(let name):
            return "Screensaver not found: \(name)"
        case .spaceNotFound:
            return "Space not found"
        case .displayNotFound(let displayNumber):
            return "Display \(displayNumber) not found"
        case .spaceNotFoundOnDisplay(let displayNumber, let spaceNumber):
            return "Space \(spaceNumber) not found on Display \(displayNumber)"
        case .sonomaRequired:
            return "This feature requires macOS 14.0 (Sonoma) or later"
        case .invalidScreenIdentifier:
            return "Invalid screen identifier provided"
        case .systemVersionDetectionFailed:
            return "Failed to detect macOS version"
        case .unknownError(let error):
            return "Unknown error: \(error.localizedDescription)"
        }
    }
}