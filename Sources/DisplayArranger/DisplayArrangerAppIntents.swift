import AppIntents
import Foundation

struct ExportDisplayLayoutIntent: AppIntent {
    static var title: LocalizedStringResource { "Export Display Layout" }
    static var description: IntentDescription {
        IntentDescription("Capture the current display arrangement and return it as YAML.")
    }
    static var isDiscoverable: Bool { true }
    static var openAppWhenRun: Bool { false }

    func perform() async throws -> some IntentResult & ReturnsValue<String> & ProvidesDialog {
        let service = DisplayService()
        let yaml = try service.exportCurrentLayoutAsYAML()
        return .result(
            value: yaml,
            dialog: IntentDialog("Exported the current display layout as YAML.")
        )
    }
}

struct ListConnectedDisplaysIntent: AppIntent {
    static var title: LocalizedStringResource { "List Connected Displays" }
    static var description: IntentDescription {
        IntentDescription("Return the connected displays as JSON.")
    }
    static var isDiscoverable: Bool { true }
    static var openAppWhenRun: Bool { false }

    func perform() async throws -> some IntentResult & ReturnsValue<String> & ProvidesDialog {
        let service = DisplayService()
        let json = try service.listConnectedDisplaysAsJSON()
        return .result(
            value: json,
            dialog: IntentDialog("Returned the connected displays as JSON.")
        )
    }
}

struct ListConnectedDisplayDictionariesIntent: AppIntent {
    static var title: LocalizedStringResource { "List Connected Displays as Dictionary" }
    static var description: IntentDescription {
        IntentDescription("Return connected display details as structured dictionary objects.")
    }
    static var isDiscoverable: Bool { true }
    static var openAppWhenRun: Bool { false }

    @Parameter(title: "Value Field", default: .displayName)
    var valueField: ConnectedDisplayDictionaryValueField

    func perform() async throws -> some IntentResult & ReturnsValue<[ConnectedDisplayDictionary]> & ProvidesDialog {
        let service = DisplayService()
        let displays = try service.listConnectedDisplaySummaries().enumerated().map { index, summary in
            ConnectedDisplayDictionary(
                displayNumber: index + 1,
                summary: summary,
                valueField: valueField
            )
        }
        return .result(
            value: displays,
            dialog: IntentDialog("Returned the connected displays as dictionary objects.")
        )
    }
}

enum ConnectedDisplayDictionaryValueField: String, AppEnum {
    case displayName
    case serialNumber

    static var typeDisplayRepresentation: TypeDisplayRepresentation {
        TypeDisplayRepresentation(name: "Dictionary Value Field")
    }

    static var caseDisplayRepresentations: [ConnectedDisplayDictionaryValueField: DisplayRepresentation] {
        [
            .displayName: "Display Name",
            .serialNumber: "Serial Number"
        ]
    }

    func value(for summary: ConnectedDisplaySummary) -> String {
        switch self {
        case .displayName:
            return summary.displayName
        case .serialNumber:
            return "\(summary.serialNumber)"
        }
    }
}

struct ConnectedDisplayDictionary: AppEntity {
    static var typeDisplayRepresentation: TypeDisplayRepresentation {
        TypeDisplayRepresentation(name: "Connected Display Dictionary Entry")
    }
    static let defaultQuery = ConnectedDisplayDictionaryQuery()

    let id: String

    @Property(title: "Key")
    var key: String

    @Property(title: "Value")
    var value: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(
            title: "\(key)",
            subtitle: "\(value)"
        )
    }

    init(
        displayNumber: Int,
        summary: ConnectedDisplaySummary,
        valueField: ConnectedDisplayDictionaryValueField
    ) {
        let entryKey = "Display \(displayNumber)"
        id = "\(entryKey)-\(valueField.rawValue)"
        key = entryKey
        value = valueField.value(for: summary)
    }
}

struct ConnectedDisplayDictionaryQuery: EntityQuery {
    func entities(for identifiers: [ConnectedDisplayDictionary.ID]) async throws -> [ConnectedDisplayDictionary] {
        let displays = try dictionaryEntries(for: [.displayName, .serialNumber])
        let displaysByID = Dictionary(uniqueKeysWithValues: displays.map { ($0.id, $0) })
        return identifiers.compactMap { displaysByID[$0] }
    }

    func suggestedEntities() async throws -> [ConnectedDisplayDictionary] {
        try dictionaryEntries(for: [.displayName])
    }

    private func dictionaryEntries(
        for valueFields: [ConnectedDisplayDictionaryValueField]
    ) throws -> [ConnectedDisplayDictionary] {
        let summaries = try DisplayService().listConnectedDisplaySummaries()
        return summaries.enumerated().flatMap { index, summary in
            valueFields.map { valueField in
                ConnectedDisplayDictionary(
                    displayNumber: index + 1,
                    summary: summary,
                    valueField: valueField
                )
            }
        }
    }
}

struct ApplyDisplayLayoutIntent: AppIntent {
    static var title: LocalizedStringResource { "Apply Display Layout" }
    static var description: IntentDescription {
        IntentDescription("Arrange the connected displays based on a YAML layout.")
    }
    static var isDiscoverable: Bool { true }
    static var openAppWhenRun: Bool { false }

    @Parameter(title: "Layout YAML")
    var layoutYAML: String

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let service = DisplayService()
        try service.applyLayout(yaml: layoutYAML)

        if let note = try service.noteIfPrimaryDisplayWouldChange(yaml: layoutYAML) {
            return .result(dialog: IntentDialog("Display positions were updated. \(note)"))
        }

        return .result(dialog: IntentDialog("Display positions were updated."))
    }
}

struct DisplayArrangerShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        return [
            AppShortcut(
                intent: ExportDisplayLayoutIntent(),
                phrases: [
                    "Export display layout in \(.applicationName)",
                    "Get display arrangement from \(.applicationName)"
                ],
                shortTitle: "Export Layout",
                systemImageName: "square.and.arrow.up"
            ),
            AppShortcut(
                intent: ApplyDisplayLayoutIntent(),
                phrases: [
                    "Apply display layout in \(.applicationName)",
                    "Arrange monitors with \(.applicationName)"
                ],
                shortTitle: "Apply Layout",
                systemImageName: "rectangle.3.group"
            ),
            AppShortcut(
                intent: ListConnectedDisplaysIntent(),
                phrases: [
                    "List connected displays in \(.applicationName)",
                    "Get connected displays from \(.applicationName)"
                ],
                shortTitle: "List Displays",
                systemImageName: "display.2"
            ),
            AppShortcut(
                intent: ListConnectedDisplayDictionariesIntent(),
                phrases: [
                    "List connected display dictionaries in \(.applicationName)",
                    "Get connected display dictionary objects from \(.applicationName)"
                ],
                shortTitle: "List Display Dictionaries",
                systemImageName: "list.bullet.rectangle"
            )
        ]
    }

    static var shortcutTileColor: ShortcutTileColor { .blue }
}
