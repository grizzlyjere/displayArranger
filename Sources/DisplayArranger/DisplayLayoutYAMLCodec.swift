import CoreGraphics
import Foundation

enum DisplayLayoutYAMLCodec {
    static func encode(_ layout: DisplayLayout) throws -> String {
        guard !layout.displays.isEmpty else {
            throw DisplayLayoutError.noActiveDisplays
        }

        var lines = ["version: \(layout.version)", "displays:"]

        for display in layout.displays {
            lines.append("  - display_id: \(display.displayID)")
            lines.append("    vendor_number: \(display.vendorNumber)")
            lines.append("    model_number: \(display.modelNumber)")
            lines.append("    serial_number: \(display.serialNumber)")
            lines.append("    name: \"\(escape(display.name))\"")
            lines.append("    origin_x: \(display.originX)")
            lines.append("    origin_y: \(display.originY)")
            lines.append("    width: \(display.width)")
            lines.append("    height: \(display.height)")
            lines.append("    is_main: \(display.isMain)")
            lines.append("    is_builtin: \(display.isBuiltin)")
        }

        return lines.joined(separator: "\n")
    }

    static func decode(_ yaml: String) throws -> DisplayLayout {
        let lines = yaml
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && !$0.hasPrefix("#") }

        guard !lines.isEmpty else {
            throw DisplayLayoutError.malformedYAML("The input is empty.")
        }

        var version: Int?
        var items: [[String: String]] = []
        var currentItem: [String: String]?

        // This parser intentionally handles only the fixed schema emitted by this app.
        for line in lines {
            if line == "displays:" {
                continue
            }

            if line.hasPrefix("version:") {
                let rawValue = String(line.dropFirst("version:".count)).trimmingCharacters(in: .whitespaces)
                guard let parsedVersion = Int(rawValue) else {
                    throw DisplayLayoutError.invalidValue(field: "version", value: rawValue)
                }
                version = parsedVersion
                continue
            }

            if line.hasPrefix("- ") {
                if let currentItem {
                    items.append(currentItem)
                }

                currentItem = [:]
                let remainder = String(line.dropFirst(2)).trimmingCharacters(in: .whitespaces)
                if !remainder.isEmpty {
                    let (key, value) = try parseKeyValue(remainder)
                    currentItem?[key] = value
                }
                continue
            }

            let (key, value) = try parseKeyValue(line)
            if currentItem == nil {
                throw DisplayLayoutError.malformedYAML("Display entries must be listed under 'displays:'.")
            }
            currentItem?[key] = value
        }

        if let currentItem {
            items.append(currentItem)
        }

        guard let version else {
            throw DisplayLayoutError.missingRequiredField("version")
        }

        let displays = try items.enumerated().map { index, item in
            try decodeDisplay(item, index: index)
        }

        guard !displays.isEmpty else {
            throw DisplayLayoutError.malformedYAML("At least one display entry is required.")
        }

        return DisplayLayout(version: version, displays: displays)
    }

    private static func decodeDisplay(_ item: [String: String], index: Int) throws -> DisplaySnapshot {
        let name = try parseString(item, key: "name")

        return DisplaySnapshot(
            displayID: CGDirectDisplayID(try parseInteger(item, key: "display_id")),
            vendorNumber: UInt32(try parseInteger(item, key: "vendor_number")),
            modelNumber: UInt32(try parseInteger(item, key: "model_number")),
            serialNumber: UInt32(try parseInteger(item, key: "serial_number")),
            name: name,
            originX: try parseInteger(item, key: "origin_x"),
            originY: try parseInteger(item, key: "origin_y"),
            width: try parseInteger(item, key: "width"),
            height: try parseInteger(item, key: "height"),
            isMain: try parseBoolean(item, key: "is_main"),
            isBuiltin: try parseBoolean(item, key: "is_builtin")
        )
    }

    private static func parseKeyValue(_ line: String) throws -> (String, String) {
        guard let separatorIndex = line.firstIndex(of: ":") else {
            throw DisplayLayoutError.malformedYAML("Expected 'key: value', found '\(line)'.")
        }

        let key = String(line[..<separatorIndex]).trimmingCharacters(in: .whitespaces)
        let rawValue = String(line[line.index(after: separatorIndex)...]).trimmingCharacters(in: .whitespaces)
        guard !key.isEmpty else {
            throw DisplayLayoutError.malformedYAML("Encountered a field with an empty key.")
        }

        return (key, rawValue)
    }

    private static func parseInteger(_ item: [String: String], key: String) throws -> Int {
        guard let rawValue = item[key] else {
            throw DisplayLayoutError.missingRequiredField(key)
        }

        guard let value = Int(rawValue) else {
            throw DisplayLayoutError.invalidValue(field: key, value: rawValue)
        }

        return value
    }

    private static func parseBoolean(_ item: [String: String], key: String) throws -> Bool {
        guard let rawValue = item[key]?.lowercased() else {
            throw DisplayLayoutError.missingRequiredField(key)
        }

        switch rawValue {
        case "true":
            return true
        case "false":
            return false
        default:
            throw DisplayLayoutError.invalidValue(field: key, value: rawValue)
        }
    }

    private static func parseString(_ item: [String: String], key: String) throws -> String {
        guard let rawValue = item[key] else {
            throw DisplayLayoutError.missingRequiredField(key)
        }

        if rawValue.hasPrefix("\""), rawValue.hasSuffix("\"") {
            let start = rawValue.index(after: rawValue.startIndex)
            let end = rawValue.index(before: rawValue.endIndex)
            return unescape(String(rawValue[start..<end]))
        }

        return rawValue
    }

    private static func escape(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }

    private static func unescape(_ value: String) -> String {
        var result = ""
        var isEscaping = false

        for character in value {
            if isEscaping {
                result.append(character)
                isEscaping = false
                continue
            }

            if character == "\\" {
                isEscaping = true
            } else {
                result.append(character)
            }
        }

        if isEscaping {
            result.append("\\")
        }

        return result
    }
}
