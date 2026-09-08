import SwiftUI

struct ContentView: View {
    @StateObject private var viewModel = ApplicationLibraryViewModel()

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
                    List(viewModel.applications) { application in
                        ApplicationRowView(application: application)
                    }
                    .listStyle(.inset)
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
                        if viewModel.isScanning {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Label("Refresh", systemImage: "arrow.clockwise")
                        }
                    }
                    .disabled(viewModel.isScanning)
                    .help("Scan installed applications")
                }
            }
        }
        .frame(minWidth: 620, minHeight: 420)
        .task {
            await viewModel.load()
        }
    }
}

#Preview {
    ContentView()
}
