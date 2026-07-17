import SwiftUI
import SwiftData

@main
struct ContextVaultApp: App {
    let container: ModelContainer

    init() {
        do {
            container = try ModelContainer(
                for: Memory.self, MemoryCollection.self, SourceAccount.self
            )
        } catch {
            fatalError("Failed to create ModelContainer: \(error)")
        }
        SyncManager.shared.registerBackgroundTasks()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
        }
        .modelContainer(container)
    }
}
