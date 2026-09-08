import SwiftUI

struct AppsTorrentConnectionCard: View {
    let connection: UpdateSourceConnection
    let onSignIn: () -> Void
    let onSignOut: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "person.crop.circle.fill")
                .font(.title2)
                .symbolRenderingMode(.hierarchical)
                .frame(width: 34, height: 34)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 7) {
                    Text(connection.name)
                        .font(.headline)

                    statusLabel
                }

                Text(statusDescription)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 12)

            switch connection.state {
            case .connected:
                Button("Sign Out") {
                    onSignOut()
                }
                .controlSize(.small)
            case .signInRequired:
                Button("Sign In") {
                    onSignIn()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(connection.name), \(accessibilityStatus)")
    }

    @ViewBuilder
    private var statusLabel: some View {
        switch connection.state {
        case .connected:
            Label("Connected", systemImage: "checkmark.circle.fill")
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
        case .signInRequired:
            Label("Sign in required", systemImage: "exclamationmark.circle.fill")
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
        }
    }

    private var statusDescription: String {
        switch connection.state {
        case .connected:
            return "Ready to check releases and download updates."
        case .signInRequired:
            return "Sign in to AppsTorrent before checking for updates."
        }
    }

    private var accessibilityStatus: String {
        switch connection.state {
        case .connected:
            return "Connected"
        case .signInRequired:
            return "Sign in required"
        }
    }
}
