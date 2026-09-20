import AppKit
import SwiftUI

struct DownloadSettingsView: View {
    @State private var directoryURL = DownloadDestinationStore().savedDirectory()
    private let store = DownloadDestinationStore()

    var body: some View {
        Form {
            Section("Updates") {
                LabeledContent("Download location") {
                    VStack(alignment: .trailing, spacing: 4) {
                        Text(directoryURL?.path ?? String(localized: "Downloads"))
                            .font(.callout.monospaced())
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                            .truncationMode(.middle)

                        Button("Change…") {
                            chooseDirectory()
                        }
                    }
                }

                Text("Luma uses your Downloads folder by default. A custom folder is remembered for future updates.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 520)
        .padding(.bottom, 12)
        .onAppear {
            directoryURL = store.savedDirectory()
        }
    }

    private func chooseDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        panel.prompt = String(localized: "Choose")
        panel.message = String(localized: "Choose where Luma should save future updates.")

        guard panel.runModal() == .OK, let url = panel.url else {
            return
        }

        store.save(directory: url)
        directoryURL = url
    }
}
