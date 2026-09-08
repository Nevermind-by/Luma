import SwiftUI

struct ContentView: View {
    @StateObject private var viewModel = ApplicationLibraryViewModel()
    @State private var isAppsTorrentBrowserPresented = false
    @State private var searchText = ""

    private var filteredApplications: [InstalledApplication] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return viewModel.applications }

        return viewModel.applications.filter {
            $0.name.localizedCaseInsensitiveContains(query)
                || $0.id.bundleIdentifier.localizedCaseInsensitiveContains(query)
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                if viewModel.isScanning && viewModel.applications.isEmpty {
                    ProgressView("Scanning Applications…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if viewModel.applications.isEmpty {
                    ContentUnavailableView(
                        "No Applications Found",
                        systemImage: "square.stack.3d.up.slash",
                        description: Text("Luma could not find any applications in the standard Applications folders.")
                    )
                } else {
                    List {
                        Section {
                            AppsTorrentConnectionCard(
                                connection: viewModel.appsTorrentConnection,
                                onSignIn: {
                                    isAppsTorrentBrowserPresented = true
                                },
                                onSignOut: {
                                    Task {
                                        await viewModel.logoutAppsTorrent()
                                    }
                                }
                            )
                        }

                        Section {
                            ForEach(filteredApplications) { application in
                                ApplicationRowView(
                                    application: application,
                                    updateState: viewModel.updateStates[application.id] ?? .notChecked,
                                    downloadState: viewModel.downloadStates[application.id] ?? .notStarted,
                                    isUpdateCheckEnabled: viewModel.canCheckAppsTorrent,
                                    onCheck: {
                                        Task {
                                            await viewModel.checkForUpdate(for: application)
                                        }
                                    },
                                    onDownload: {
                                        Task {
                                            await viewModel.downloadUpdate(for: application)
                                        }
                                    },
                                    onShowDownloadedFile: {
                                        viewModel.showDownloadedFile(for: application)
                                    }
                                )
                            }
                        } header: {
                            Text("Applications")
                        }
                    }
                    .listStyle(.inset)
                    .searchable(text: $searchText, placement: .toolbar, prompt: "Search applications")
                }
            }
            .navigationTitle("Applications")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        Task {
                            await viewModel.load()
                        }
                    } label: {
                        Label("Refresh", systemImage: "arrow.clockwise")
                    }
                    .disabled(viewModel.isScanning || viewModel.isCheckingUpdates)
                    .help("Scan installed applications")
                }
            }
        }
        .frame(minWidth: 760, minHeight: 520)
        .task {
            await viewModel.load()
        }
        .sheet(isPresented: $isAppsTorrentBrowserPresented) {
            AppsTorrentBrowserView(
                url: URL(string: "https://appstorrent.ru")!
            ) {
                viewModel.markAppsTorrentLoginCompleted()
            }
        }
    }
}

#Preview {
    ContentView()
}
