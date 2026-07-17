import AppIntents

/// App Shortcuts — zero-setup phrases users can speak to Siri from day one.
struct ContextVaultShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: AskVaultIntent(),
            phrases: [
                "Ask \(.applicationName)",
                "Ask my vault in \(.applicationName)",
                "Ask \(.applicationName) about my notes"
            ],
            shortTitle: "Ask your Vault",
            systemImageName: "brain.head.profile"
        )
        AppShortcut(
            intent: CaptureMemoryIntent(),
            phrases: [
                "Capture a memory in \(.applicationName)",
                "Remember this in \(.applicationName)"
            ],
            shortTitle: "Capture Memory",
            systemImageName: "tray.and.arrow.down"
        )
    }
}
