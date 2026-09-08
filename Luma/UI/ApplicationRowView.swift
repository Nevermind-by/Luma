import AppKit
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
        HStack(spacing: 12) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: application.bundleURL.path))
                .resizable()
                .frame(width: 40, height: 40)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(application.name)
                        .font(.headline)

                    if application.installationSource == .appStore {
                        Text("App Store")
                            .font(.caption2.weight(.medium))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(.quaternary, in: Capsule())
                    }
                }

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
            Button("Check") {
                onCheck()
            }
            .controlSize(.small)
            .disabled(!isUpdateCheckEnabled)
            .help(isUpdateCheckEnabled ? "Check AppsTorrent for an update" : "Sign in to AppsTorrent first")

        case .checking:
            ProgressView()
                .controlSize(.small)

        case .upToDate:
            Label("Up to date", systemImage: "checkmark.circle.fill")
                .font(.caption)
                .foregroundStyle(.secondary)

        case .updateAvailable(let candidate):
            VStack(alignment: .trailing, spacing: 6) {
                VStack(alignment: .trailing, spacing: 2) {
                    Label("Update available", systemImage: "arrow.down.circle.fill")
                        .font(.caption)
                    HStack(spacing: 5) {
                        Text(candidate.version.rawValue)
                            .font(.caption2)
                            .foregroundStyle(.secondary)

                        if let variant = candidate.distributionVariant {
                            Text(distributionVariantLabel(variant))
                                .font(.caption2.weight(.medium))
                        }
                    }
                }

                downloadAction
            }

        case .unavailable:
            HStack(spacing: 8) {
                Text("Unavailable")
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
            Button("Update") {
                onDownload()
            }
            .controlSize(.small)

        case .downloading(let progress):
            if let fraction = progress.fractionCompleted {
                HStack(spacing: 6) {
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
                .frame(maxWidth: 220, alignment: .trailing)
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
