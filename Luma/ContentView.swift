import SwiftUI

struct ContentView: View {
    private enum SidebarSelection: Hashable {
        case all
        case updates
        case upToDate
        case attention
    }

    @StateObject private var viewModel = ApplicationLibraryViewModel()
    @State private var isAppsTorrentBrowserPresented = false
    @State private var searchText = ""
    @State private var selection: SidebarSelection = .all

    private var filteredApplications: [InstalledApplication] {
        var applications = viewModel.applications

        switch selection {
        case .all:
            break
        case .updates:
            applications = applications.filter {
                if case .updateAvailable = viewModel.updateStates[$0.id] {
                    return true
                }
                return false
            }
        case .upToDate:
            applications = applications.filter {
                viewModel.updateStates[$0.id] == .upToDate
            }
        case .attention:
            applications = applications.filter {
                switch viewModel.updateStates[$0.id] {
                case .unavailable, .failed:
                    return true
                default:
                    return false
                }
            }
        }

        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return applications }

        return applications.filter {
            $0.name.localizedCaseInsensitiveContains(query)
                || $0.id.bundleIdentifier.localizedCaseInsensitiveContains(query)
        }
    }

    private var updateCount: Int {
        viewModel.applications.reduce(into: 0) { count, application in
            if case .updateAvailable = viewModel.updateStates[application.id] {
                count += 1
            }
        }
    }

    private var upToDateCount: Int {
        viewModel.applications.reduce(into: 0) { count, application in
            if viewModel.updateStates[application.id] == .upToDate {
                count += 1
            }
        }
    }

    private var attentionCount: Int {
        viewModel.applications.reduce(into: 0) { count, application in
            switch viewModel.updateStates[application.id] {
            case .unavailable, .failed:
                count += 1
            default:
                break
            }
        }
    }

    var body: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            applicationLibrary
        }
        .navigationSplitViewColumnWidth(min: 210, ideal: 230, max: 270)
        .frame(minWidth: 920, minHeight: 620)
        .toolbar {
            ToolbarItem {
                SettingsLink()
            }
        }
        .sheet(isPresented: $isAppsTorrentBrowserPresented) {
            AppsTorrentBrowserView(
                url: URL(string: "https://appstorrent.ru")!,
                session: AppsTorrentBrowserSession.shared
            ) {
                viewModel.markAppsTorrentLoginCompleted()
            }
        }
        .task {
            await viewModel.load()
        }
    }

    private var sidebar: some View {
        List(selection: $selection) {
            Section("Library") {
                sidebarRow("All Applications", systemImage: "square.grid.2x2", count: viewModel.applications.count, selection: .all)
                sidebarRow("Updates", systemImage: "arrow.down.circle", count: updateCount, selection: .updates)
                sidebarRow("Up to Date", systemImage: "checkmark.circle", count: upToDateCount, selection: .upToDate)
                sidebarRow("Attention", systemImage: "exclamationmark.triangle", count: attentionCount, selection: .attention)
            }

            Section("Sources") {
                Button {
                    isAppsTorrentBrowserPresented = true
                } label: {
                    HStack(spacing: 10) {
                        Circle()
                            .fill(sourceIndicatorColor)
                            .frame(width: 8, height: 8)

                        VStack(alignment: .leading, spacing: 1) {
                            Text("AppsTorrent")
                                .font(.body)
                            Text(sourceStatusText)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Spacer(minLength: 4)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .contextMenu {
                    switch viewModel.appsTorrentConnection.state {
                    case .connected:
                        Button("Sign Out") {
                            Task { await viewModel.logoutAppsTorrent() }
                        }
                    case .checking:
                        EmptyView()
                    case .signInRequired, .sessionExpired:
                        Button("Sign In") {
                            isAppsTorrentBrowserPresented = true
                        }
                    }
                }
            }

            Section {
                HStack(spacing: 10) {
                    LumaBrandMark(size: 30)
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Luma")
                            .font(.headline)
                        Text("App Updates")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 6)
            }
        }
        .listStyle(.sidebar)
    }

    private func sidebarRow(
        _ title: String,
        systemImage: String,
        count: Int,
        selection: SidebarSelection
    ) -> some View {
        HStack(spacing: 9) {
            Label(title, systemImage: systemImage)
            Spacer(minLength: 4)
            if count > 0 {
                Text(count, format: .number)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .contentTransition(.numericText())
            }
        }
        .tag(selection)
    }

    private var applicationLibrary: some View {
        VStack(spacing: 0) {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(selectionTitle)
                        .font(.largeTitle.weight(.semibold))
                    Text(selectionSubtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 16)

                if viewModel.isScanning {
                    ProgressView()
                        .controlSize(.small)
                }

                Button {
                    Task { await viewModel.load() }
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .disabled(viewModel.isScanning || viewModel.isCheckingUpdates)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 18)

            Divider()

            if filteredApplications.isEmpty {
                ContentUnavailableView(
                    emptyStateTitle,
                    systemImage: emptyStateSymbol,
                    description: Text(emptyStateDescription)
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(filteredApplications) { application in
                    ApplicationRowView(
                        application: application,
                        updateState: viewModel.updateStates[application.id] ?? .notChecked,
                        downloadState: viewModel.downloadStates[application.id] ?? .notStarted,
                        isUpdateCheckEnabled: viewModel.canCheckApplication(application),
                        onCheck: {
                            Task { await viewModel.checkForUpdate(for: application) }
                        },
                        onDownload: {
                            Task { await viewModel.downloadUpdate(for: application) }
                        },
                        onInstall: {
                            Task { await viewModel.installUpdate(for: application) }
                        },
                        onShowDownloadedFile: {
                            viewModel.showDownloadedFile(for: application)
                        }
                    )
                }
                .listStyle(.inset)
                .scrollContentBackground(.hidden)
            }
        }
        .searchable(text: $searchText, placement: .toolbar, prompt: "Search applications")
    }

    private var sourceStatusText: String {
        switch viewModel.appsTorrentConnection.state {
        case .checking: return "Checking session…"
        case .connected: return "Connected"
        case .signInRequired: return "Sign in required"
        case .sessionExpired: return "Session expired"
        }
    }

    private var sourceIndicatorColor: Color {
        switch viewModel.appsTorrentConnection.state {
        case .checking: return .yellow
        case .connected: return .green
        case .signInRequired, .sessionExpired: return .orange
        }
    }

    private var selectionTitle: String {
        switch selection {
        case .all: return "Applications"
        case .updates: return "Updates"
        case .upToDate: return "Up to Date"
        case .attention: return "Needs Attention"
        }
    }

    private var selectionSubtitle: String {
        switch selection {
        case .all:
            return "Installed applications on this Mac"
        case .updates:
            return "Applications with a newer release available"
        case .upToDate:
            return "Applications matching the latest checked release"
        case .attention:
            return "Applications that could not be checked"
        }
    }

    private var emptyStateTitle: String {
        switch selection {
        case .all: return "No Applications Found"
        case .updates: return "No Updates"
        case .upToDate: return "Nothing Checked Yet"
        case .attention: return "All Clear"
        }
    }

    private var emptyStateSymbol: String {
        switch selection {
        case .all: return "square.stack.3d.up.slash"
        case .updates: return "checkmark.circle"
        case .upToDate: return "clock.arrow.circlepath"
        case .attention: return "checkmark.shield"
        }
    }

    private var emptyStateDescription: String {
        switch selection {
        case .all:
            return "Luma could not find any applications in the standard Applications folders."
        case .updates:
            return "Check an application to find out whether a newer release is available."
        case .upToDate:
            return "Run a check on an application to see whether it is up to date."
        case .attention:
            return "No checked applications currently need attention."
        }
    }
}

#Preview {
    ContentView()
}
