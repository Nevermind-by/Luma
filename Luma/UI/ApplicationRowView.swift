import SwiftUI

struct ApplicationRowView: View {
    let application: InstalledApplication
    let updateState: ApplicationUpdateState
    let downloadState: ApplicationDownloadState
    let isUpdateCheckEnabled: Bool
    let onCheck: () -> Void
    let onDownload: () -> Void
    let onShowDownloadedFile: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            ApplicationIconView(applicationURL: application.bundleURL, size: 48)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(application.name)
                        .font(.headline)
                        .lineLimit(1)

                    if application.installationSource == .appStore {
                        Text("App Store")
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(.quaternary, in: Capsule())
                    }
                }

                HStack(spacing: 6) {
                    Text("Version \(application.version.rawValue)")
                    Text("•")
                    Text(application.id.bundleIdentifier)
                        .lineLimit(1)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .truncationMode(.middle)
            }
            .frame(minWidth: 180, alignment: .leading)

            Spacer(minLength: 12)

            updateStatusView
                .frame(minWidth: 150, alignment: .trailing)
        }
        .padding(.vertical, 8)
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private var updateStatusView: some View {
        switch updateState {
        case .notChecked:
            Button {
                onCheck()
            } label: {
                Label("Check", systemImage: "arrow.triangle.2.circlepath")
            }
            .controlSize(.small)
            .disabled(!isUpdateCheckEnabled)
            .help(isUpdateCheckEnabled ? "Check AppsTorrent for an update" : "Sign in to AppsTorrent first")

        case .checking:
            HStack(spacing: 8) {
                ProgressView()
                    .controlSize(.small)
                Text("Checking…")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

        case .upToDate:
            Label("Up to date", systemImage: "checkmark.circle.fill")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)

        case .updateAvailable(let candidate):
            VStack(alignment: .trailing, spacing: 7) {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.down.circle.fill")
                    Text("Update available")
                        .font(.subheadline.weight(.semibold))
                }
                .foregroundStyle(.tint)

                HStack(spacing: 6) {
                    Text(candidate.version.rawValue)
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)

                    if let variant = candidate.distributionVariant,
                       variant != .unknown {
                        Text(distributionVariantLabel(variant))
                            .font(.caption2.weight(.medium))
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(.tint.opacity(0.10), in: Capsule())
                    }
                }

                downloadAction
            }

        case .unavailable:
            HStack(spacing: 8) {
                Label("Unavailable", systemImage: "questionmark.circle")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Button("Retry") {
                    onCheck()
                }
                .controlSize(.small)
                .disabled(!isUpdateCheckEnabled)
            }

        case .failed:
            HStack(spacing: 8) {
                Label("Check failed", systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)

                Button("Retry") {
                    onCheck()
                }
                .controlSize(.small)
                .disabled(!isUpdateCheckEnabled)
            }
        }
    }

    @ViewBuilder
    private var downloadAction: some View {
        switch downloadState {
        case .notStarted:
            Button {
                onDownload()
            } label: {
                Label("Update", systemImage: "arrow.down.circle")
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)

        case .downloading(let progress):
            if let fraction = progress.fractionCompleted {
                HStack(spacing: 8) {
                    ProgressView(value: fraction)
                        .frame(width: 90)
                    Text("\(Int(fraction * 100))%")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            } else {
                ProgressView()
                    .controlSize(.small)
            }

        case .completed:
            Button("Show in Finder") {
                onShowDownloadedFile()
            }
            .controlSize(.small)

        case .failed(let message):
            Text(message)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.trailing)
                .frame(maxWidth: 240, alignment: .trailing)
        }
    }

    private func distributionVariantLabel(_ variant: AppsTorrentDistributionVariant) -> String {
        switch variant {
        case .mas:
            return "Mac App Store"
        case .standard:
            return "Standard"
        case .unknown:
            return ""
        }
    }
}
