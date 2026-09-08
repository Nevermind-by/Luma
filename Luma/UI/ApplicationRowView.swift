import AppKit
import SwiftUI

struct ApplicationRowView: View {
    let application: InstalledApplication
    let updateState: ApplicationUpdateState

    var body: some View {
        HStack(spacing: 12) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: application.bundleURL.path))
                .resizable()
                .frame(width: 40, height: 40)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

            VStack(alignment: .leading, spacing: 3) {
                Text(application.name)
                    .font(.headline)

                Text("Version \(application.version.rawValue)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            updateStatusView
        }
        .padding(.vertical, 6)
    }

    @ViewBuilder
    private var updateStatusView: some View {
        switch updateState {
        case .notChecked:
            Text("Not checked")
                .font(.caption)
                .foregroundStyle(.secondary)

        case .checking:
            ProgressView()
                .controlSize(.small)

        case .upToDate:
            Label("Up to date", systemImage: "checkmark.circle.fill")
                .font(.caption)
                .foregroundStyle(.secondary)

        case .updateAvailable(let candidate):
            VStack(alignment: .trailing, spacing: 2) {
                Label("Update available", systemImage: "arrow.down.circle.fill")
                    .font(.caption)
                Text(candidate.version.rawValue)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

        case .unavailable:
            Text("Unavailable")
                .font(.caption)
                .foregroundStyle(.secondary)

        case .failed:
            Label("Check failed", systemImage: "exclamationmark.triangle.fill")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}
