import SwiftUI
import SwiftData

@main
struct ContextVaultApp: App {
    // Single shared container: views (@Query), intents, and sync must all
    // observe the same ModelContainer or changes won't propagate.
    let container = VaultStore.shared.container

    init() {
        SyncManager.shared.registerBackgroundTasks()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
        }
        .modelContainer(container)
    }
}
