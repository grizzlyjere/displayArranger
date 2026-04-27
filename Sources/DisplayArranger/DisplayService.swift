import AppKit
import CoreGraphics
import Foundation

struct DisplayService {
    func captureCurrentLayout() throws -> DisplayLayout {
        var count: UInt32 = 0
        let countError = CGGetActiveDisplayList(0, nil, &count)
        guard countError == .success else {
            throw DisplayLayoutError.unableToEnumerateDisplays(countError)
        }

        guard count > 0 else {
            throw DisplayLayoutError.noActiveDisplays
        }

        var displayIDs = [CGDirectDisplayID](repeating: 0, count: Int(count))
        let listError = CGGetActiveDisplayList(count, &displayIDs, &count)
        guard listError == .success else {
            throw DisplayLayoutError.unableToEnumerateDisplays(listError)
        }

        let screenNames = displayNamesByID()
        let mainDisplayID = CGMainDisplayID()

        let snapshots = displayIDs.map { displayID -> DisplaySnapshot in
            let bounds = CGDisplayBounds(displayID)
            let origin = bounds.origin
            let size = bounds.size

            return DisplaySnapshot(
                displayID: displayID,
                vendorNumber: CGDisplayVendorNumber(displayID),
                modelNumber: CGDisplayModelNumber(displayID),
                serialNumber: CGDisplaySerialNumber(displayID),
                name: screenNames[displayID] ?? "Display \(displayID)",
                originX: Int(origin.x.rounded()),
                originY: Int(origin.y.rounded()),
                width: Int(size.width.rounded()),
                height: Int(size.height.rounded()),
                isMain: displayID == mainDisplayID,
                isBuiltin: CGDisplayIsBuiltin(displayID) != 0
            )
        }

        return DisplayLayout(version: 1, displays: snapshots)
    }

    func exportCurrentLayoutAsYAML() throws -> String {
        let layout = try captureCurrentLayout()
        return try DisplayLayoutYAMLCodec.encode(layout)
    }

    func listConnectedDisplaysAsJSON() throws -> String {
        let layout = try captureCurrentLayout()
        return try ConnectedDisplaysJSONCodec.encode(layout.displays)
    }

    func listConnectedDisplaySummaries() throws -> [ConnectedDisplaySummary] {
        let layout = try captureCurrentLayout()
        return layout.displays.map {
            ConnectedDisplaySummary(
                displayName: $0.name,
                displayID: $0.displayID,
                serialNumber: $0.serialNumber
            )
        }
    }

    func applyLayout(yaml: String) throws {
        let desiredLayout = try DisplayLayoutYAMLCodec.decode(yaml)
        try validate(layout: desiredLayout)

        let currentDisplays = try captureCurrentLayout().displays
        // Vendor/model/serial is more stable across reconnects than the transient display ID.
        let displaysByIdentifier = Dictionary(uniqueKeysWithValues: currentDisplays.map { ($0.stableIdentifier, $0) })

        var configRef: CGDisplayConfigRef?
        let beginError = CGBeginDisplayConfiguration(&configRef)
        guard beginError == .success, let configRef else {
            throw DisplayLayoutError.unableToBeginConfiguration(beginError)
        }

        // Apply every origin change into a single transaction so macOS reflows the layout once.
        for display in desiredLayout.displays {
            guard let currentDisplay = displaysByIdentifier[display.stableIdentifier] else {
                CGCancelDisplayConfiguration(configRef)
                throw DisplayLayoutError.displayNotFound(display.stableIdentifier)
            }

            let configureError = CGConfigureDisplayOrigin(
                configRef,
                currentDisplay.displayID,
                Int32(display.originX),
                Int32(display.originY)
            )

            guard configureError == .success else {
                CGCancelDisplayConfiguration(configRef)
                throw DisplayLayoutError.unableToApplyOrigin(displayName: display.name, error: configureError)
            }
        }

        let completeError = CGCompleteDisplayConfiguration(configRef, .permanently)
        guard completeError == .success else {
            throw DisplayLayoutError.unableToCommitConfiguration(completeError)
        }
    }

    func noteIfPrimaryDisplayWouldChange(yaml: String) throws -> String? {
        let desiredLayout = try DisplayLayoutYAMLCodec.decode(yaml)
        let currentLayout = try captureCurrentLayout()

        // Public CoreGraphics APIs can reposition displays, but they cannot move the menu-bar display.
        let desiredMain = desiredLayout.displays.first(where: \.isMain)?.stableIdentifier
        let currentMain = currentLayout.displays.first(where: \.isMain)?.stableIdentifier

        guard let desiredMain, let currentMain, desiredMain != currentMain else {
            return nil
        }

        return DisplayLayoutError.unsupportedPrimaryDisplayChange.localizedDescription
    }

    private func validate(layout: DisplayLayout) throws {
        guard layout.version == 1 else {
            throw DisplayLayoutError.invalidValue(field: "version", value: "\(layout.version)")
        }

        var seenIdentifiers = Set<String>()
        for display in layout.displays {
            let inserted = seenIdentifiers.insert(display.stableIdentifier).inserted
            guard inserted else {
                throw DisplayLayoutError.duplicateDisplayIdentity(display.stableIdentifier)
            }
        }
    }

    private func displayNamesByID() -> [CGDirectDisplayID: String] {
        NSScreen.screens.reduce(into: [CGDirectDisplayID: String]()) { partialResult, screen in
            guard let screenNumber = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else {
                return
            }
            partialResult[CGDirectDisplayID(screenNumber.uint32Value)] = screen.localizedName
        }
    }
}

enum ConnectedDisplaysJSONCodec {
    static func encode(_ displays: [DisplaySnapshot]) throws -> String {
        guard !displays.isEmpty else {
            throw DisplayLayoutError.noActiveDisplays
        }

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(displays.map(ConnectedDisplay.init(display:)))

        guard let json = String(data: data, encoding: .utf8) else {
            throw DisplayLayoutError.unableToEncodeJSON
        }

        return json
    }

    private struct ConnectedDisplay: Encodable {
        let displayID: CGDirectDisplayID
        let stableIdentifier: String
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

        init(display: DisplaySnapshot) {
            displayID = display.displayID
            stableIdentifier = display.stableIdentifier
            vendorNumber = display.vendorNumber
            modelNumber = display.modelNumber
            serialNumber = display.serialNumber
            name = display.name
            originX = display.originX
            originY = display.originY
            width = display.width
            height = display.height
            isMain = display.isMain
            isBuiltin = display.isBuiltin
        }

        enum CodingKeys: String, CodingKey {
            case displayID = "display_id"
            case stableIdentifier = "stable_identifier"
            case vendorNumber = "vendor_number"
            case modelNumber = "model_number"
            case serialNumber = "serial_number"
            case name
            case originX = "origin_x"
            case originY = "origin_y"
            case width
            case height
            case isMain = "is_main"
            case isBuiltin = "is_builtin"
        }
    }
}
