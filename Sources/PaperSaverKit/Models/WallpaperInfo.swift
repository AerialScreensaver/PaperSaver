import Foundation
import AppKit

/// How a static image is fitted to a display, in the terms `NSWorkspace` understands.
public enum WallpaperPlacement: String, Sendable, Codable, CaseIterable {
    /// Scale to fill the display, cropping what does not fit.
    case fill
    /// Scale to show the whole image, leaving the fill colour visible around it.
    case fit
    /// Scale each axis independently to the display size.
    case stretch
    /// Show the image at its natural size, centred.
    case center

    /// The `NSWorkspace.setDesktopImageURL` options for this placement.
    public var workspaceOptions: [NSWorkspace.DesktopImageOptionKey: Any] {
        switch self {
        case .fill: return [.imageScaling: NSImageScaling.scaleProportionallyUpOrDown.rawValue, .allowClipping: true]
        case .fit: return [.imageScaling: NSImageScaling.scaleProportionallyUpOrDown.rawValue, .allowClipping: false]
        case .stretch: return [.imageScaling: NSImageScaling.scaleAxesIndependently.rawValue, .allowClipping: false]
        case .center: return [.imageScaling: NSImageScaling.scaleNone.rawValue, .allowClipping: false]
        }
    }

    /// The id the wallpaper store records for this placement (measured on macOS 27.2 by
    /// reading back what the agent wrote after `NSWorkspace.setDesktopImageURL`).
    public var storePlacement: OptionValues.Placement {
        switch self {
        case .fill: return .crop
        case .fit: return .sizeToFit
        case .stretch: return .fillScreen
        case .center: return .centered
        }
    }

    /// The placement for a store id, or `nil` for an id the library has not seen.
    public init?(storePlacement: OptionValues.Placement) {
        guard let match = WallpaperPlacement.allCases.first(where: { $0.storePlacement == storePlacement }) else { return nil }
        self = match
    }

    /// The placement `NSWorkspace.desktopImageOptions` describe; `.fill` when unspecified.
    public init(workspaceOptions options: [NSWorkspace.DesktopImageOptionKey: Any]) {
        let scaling = (options[.imageScaling] as? NSNumber).flatMap { NSImageScaling(rawValue: $0.uintValue) } ?? .scaleProportionallyUpOrDown
        let clipping = (options[.allowClipping] as? NSNumber)?.boolValue ?? true
        switch scaling {
        case .scaleAxesIndependently: self = .stretch
        case .scaleNone: self = .center
        default: self = clipping ? .fill : .fit
        }
    }
}

/// A static image wallpaper as `NSWorkspace` reports it.
public struct WallpaperInfo: Sendable, Equatable, Codable {
    public let imageURL: URL
    public let placement: WallpaperPlacement
    /// The display the wallpaper was read from.
    public let displayUUID: String?

    public init(imageURL: URL, placement: WallpaperPlacement = .fill, displayUUID: String? = nil) {
        self.imageURL = imageURL
        self.placement = placement
        self.displayUUID = displayUUID
    }

    public var imagePath: String { imageURL.path }
    public var imageName: String { imageURL.lastPathComponent }
}
