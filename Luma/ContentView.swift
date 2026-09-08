import SwiftUI

struct ContentView: View {
    @StateObject private var viewModel = ApplicationLibraryViewModel()
    @StateObject private var authenticationManager = AppsTorrentAuthenticationManager()
    @State private var isAppsTorrentBrowserPresented = false

    var body: some View {
        Group {
            if authenticationManager.isLoginCompleted {
                applicationLibrary
            } else {
                AppsTorrentLoginView {
                    authenticationManager.markLoginCompleted()
                }
            }
        }
    }

    private var applicationLibrary: some View {
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
                    List(viewModel.applications) { application in
                        ApplicationRowView(
                            application: application,
                            updateState: viewModel.updateStates[application.id] ?? .notChecked,
                            downloadState: viewModel.downloadStates[application.id] ?? .notStarted,
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
                    .listStyle(.inset)
                }
            }
            .navigationTitle("Applications")
            .toolbar {
                ToolbarItemGroup(placement: .primaryAction) {
                    Button {
                        Task {
                            await viewModel.checkForUpdates()
                        }
                    } label: {
                        if viewModel.isCheckingUpdates {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Label("Check for Updates", systemImage: "arrow.triangle.2.circlepath")
                        }
                    }
                    .disabled(viewModel.isCheckingUpdates || viewModel.isScanning || viewModel.applications.isEmpty)
                    .help("Check all installed applications for updates")

                    Button {
                        isAppsTorrentBrowserPresented = true
                    } label: {
                        Label("Open AppsTorrent", systemImage: "safari")
                    }
                    .help("Open AppsTorrent in Luma's browser session")

                    Menu {
                        Button("Sign Out of AppsTorrent") {
                            Task {
                                await authenticationManager.logout()
                                await viewModel.load()
                            }
                        }
                    } label: {
                        Label("AppsTorrent", systemImage: "person.crop.circle")
                    }
                    .help("Manage the AppsTorrent browser session")

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
            )
        }
    }
}

#Preview {
    ContentView()
}
