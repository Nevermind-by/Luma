import SwiftUI

struct AppsTorrentConnectionCard: View {
    let connection: UpdateSourceConnection
    let onSignIn: () -> Void
    let onSignOut: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "point.3.connected.trianglepath.dotted")
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
            case .checking:
                ProgressView()
                    .controlSize(.small)
                    .accessibilityLabel("Checking connection")
            case .connected:
                Button("Sign Out") {
                    onSignOut()
                }
                .controlSize(.small)
            case .signInRequired, .sessionExpired:
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
        case .checking:
            Text("Checking")
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
        case .connected:
            Label("Connected", systemImage: "checkmark.circle.fill")
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
        case .signInRequired:
            Label("Sign in required", systemImage: "exclamationmark.circle.fill")
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
        case .sessionExpired:
            Label("Session expired", systemImage: "clock.badge.exclamationmark")
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
        }
    }

    private var statusDescription: String {
        switch connection.state {
        case .checking:
            return "Checking the saved AppsTorrent browser session."
        case .connected:
            return "Ready to check releases and download updates."
        case .signInRequired:
            return "Sign in to AppsTorrent before checking for updates."
        case .sessionExpired:
            return "Your AppsTorrent session is no longer available. Sign in again."
        }
    }

    private var accessibilityStatus: String {
        switch connection.state {
        case .checking:
            return "Checking"
        case .connected:
            return "Connected"
        case .signInRequired:
            return "Sign in required"
        case .sessionExpired:
            return "Session expired"
        }
    }
}
