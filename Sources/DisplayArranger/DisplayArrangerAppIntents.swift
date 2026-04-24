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
            )
        ]
    }

    static var shortcutTileColor: ShortcutTileColor { .blue }
}
