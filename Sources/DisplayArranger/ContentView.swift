import SwiftUI

struct ContentView: View {
    @State private var yamlText = ""
    @State private var statusMessage = "Capture the current arrangement or paste YAML to apply one."

    private let displayService = DisplayService()

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Display Arranger")
                .font(.largeTitle.weight(.semibold))

            Text("Export the active display layout as YAML, edit it if needed, then apply it back from the app or from Shortcuts.")
                .foregroundStyle(.secondary)

            TextEditor(text: $yamlText)
                .font(.system(.body, design: .monospaced))
                .frame(minHeight: 320)

            HStack {
                Button("Capture Current Layout", action: captureLayout)
                Button("Apply YAML Layout", action: applyLayout)
                Spacer()
            }

            Text(statusMessage)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
        }
        .padding(20)
        .frame(minWidth: 760, minHeight: 520)
        .task {
            if yamlText.isEmpty {
                captureLayout()
            }
        }
    }

    private func captureLayout() {
        do {
            yamlText = try displayService.exportCurrentLayoutAsYAML()
            statusMessage = "Captured the current display arrangement."
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    private func applyLayout() {
        do {
            try displayService.applyLayout(yaml: yamlText)

            if let note = try displayService.noteIfPrimaryDisplayWouldChange(yaml: yamlText) {
                statusMessage = "Applied the display positions. \(note)"
            } else {
                statusMessage = "Applied the display positions."
            }
        } catch {
            statusMessage = error.localizedDescription
        }
    }
}
