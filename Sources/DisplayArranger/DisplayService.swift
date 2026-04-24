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
