import SwiftUI

struct RootView: View {
    var body: some View {
        TabView {
            Tab("Vault", systemImage: "archivebox") {
                VaultView()
            }
            Tab("Collections", systemImage: "square.stack.3d.up") {
                CollectionsView()
            }
            Tab("Ask", systemImage: "brain.head.profile") {
                ChatView()
            }
            Tab("Sources", systemImage: "link") {
                SourcesView()
            }
        }
        .task {
            await SyncManager.shared.syncAll()
            SyncManager.shared.scheduleBackgroundSync()
        }
    }
}

#Preview {
    RootView()
        .modelContainer(for: [Memory.self, MemoryCollection.self, SourceAccount.self], inMemory: true)
}
