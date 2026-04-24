import CoreGraphics
import Foundation

struct DisplayLayout: Sendable, Equatable {
    let version: Int
    let displays: [DisplaySnapshot]
}

struct DisplaySnapshot: Sendable, Equatable, Identifiable {
    let displayID: CGDirectDisplayID
    let vendorNumber: UInt32
    let modelNumber: UInt32
    let serialNumber: UInt32
    let name: String
    let originX: Int
    let originY: Int
    let width: Int
    let height: Int
    let isMain: Bool
    let isBuiltin: Bool

    var id: String { stableIdentifier }

    var stableIdentifier: String {
        if vendorNumber != 0 || modelNumber != 0 || serialNumber != 0 {
            return "\(vendorNumber)-\(modelNumber)-\(serialNumber)"
        }
        return "display-id-\(displayID)"
    }
}

enum DisplayLayoutError: LocalizedError {
    case noActiveDisplays
    case unableToEnumerateDisplays(CGError)
    case unableToBeginConfiguration(CGError)
    case unableToApplyOrigin(displayName: String, error: CGError)
    case unableToCommitConfiguration(CGError)
    case malformedYAML(String)
    case missingRequiredField(String)
    case invalidValue(field: String, value: String)
    case duplicateDisplayIdentity(String)
    case displayNotFound(String)
    case unsupportedPrimaryDisplayChange

    var errorDescription: String? {
        switch self {
        case .noActiveDisplays:
            return "No active displays were detected."
        case .unableToEnumerateDisplays(let error):
            return "CoreGraphics could not enumerate the active displays (\(error.rawValue))."
        case .unableToBeginConfiguration(let error):
            return "CoreGraphics could not start a display configuration (\(error.rawValue))."
        case .unableToApplyOrigin(let displayName, let error):
            return "CoreGraphics could not move \(displayName) (\(error.rawValue))."
        case .unableToCommitConfiguration(let error):
            return "CoreGraphics could not commit the display configuration (\(error.rawValue))."
        case .malformedYAML(let message):
            return "The layout YAML is malformed: \(message)"
        case .missingRequiredField(let field):
            return "The layout YAML is missing the required field '\(field)'."
        case .invalidValue(let field, let value):
            return "The value '\(value)' is invalid for '\(field)'."
        case .duplicateDisplayIdentity(let identity):
            return "The layout YAML contains the same display more than once (\(identity))."
        case .displayNotFound(let identity):
            return "A display in the layout YAML is not currently connected: \(identity)"
        case .unsupportedPrimaryDisplayChange:
            return "This app can reposition displays with public APIs, but macOS does not expose a public API for changing the primary display."
        }
    }
}
