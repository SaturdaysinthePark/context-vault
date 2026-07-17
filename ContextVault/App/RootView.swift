import SwiftUI

struct RootView: View {
    @AppStorage("hasOnboarded") private var hasOnboarded = false
    @State private var showOnboarding = false

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
            if !hasOnboarded { showOnboarding = true }
            await SyncManager.shared.syncAll()
            SyncManager.shared.scheduleBackgroundSync()
        }
        .fullScreenCover(isPresented: $showOnboarding) {
            OnboardingView()
        }
    }
}

#Preview {
    RootView()
        .modelContainer(for: [Memory.self, MemoryCollection.self, SourceAccount.self], inMemory: true)
}
