import SwiftUI
import SwiftData

/// Per-source screen: sync status and controls, sync scope (Drive), and this
/// source's memories — memory browsing lives here, under each source.
struct SourceDetailView: View {
    @Bindable var account: SourceAccount
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Memory.modifiedAt, order: .reverse) private var allMemories: [Memory]

    @State private var showingScopePicker = false
    @State private var syncing = false
    @State private var confirmingDisconnect = false

    private var refPrefix: String {
        let type: String
        switch account.sourceType {
        case .googleDrive: type = "gdrive"
        case .notion: type = "notion"
        case .obsidian, .files: type = "obsidian"
        default: type = account.sourceType.rawValue
        }
        return "\(type):\(account.id.uuidString):"
    }

    private var memories: [Memory] {
        allMemories.filter { $0.sourceRef?.hasPrefix(refPrefix) == true }
    }

    private var driveConfig: GoogleDriveConfig? {
        account.configData.flatMap { try? JSONDecoder().decode(GoogleDriveConfig.self, from: $0) }
    }

    var body: some View {
        List {
            Section("Status") {
                LabeledContent("Memories", value: "\(memories.count)")
                LabeledContent("Last synced",
                               value: account.lastSyncedAt?.formatted(.relative(presentation: .named)) ?? "Never")
                Button {
                    runSync()
                } label: {
                    if syncing {
                        HStack { ProgressView(); Text("Syncing…") }
                    } else {
                        Label("Sync now", systemImage: "arrow.triangle.2.circlepath")
                    }
                }
                .disabled(syncing)
            }

            if account.sourceType == .googleDrive {
                Section {
                    LabeledContent("Scope") {
                        if let ids = driveConfig?.selectedFolderIDs, !ids.isEmpty {
                            Text("\(ids.count) folder\(ids.count == 1 ? "" : "s")")
                        } else {
                            Text("Everything")
                        }
                    }
                    Button {
                        showingScopePicker = true
                    } label: {
                        Label("Edit synced folders", systemImage: "folder.badge.gearshape")
                    }
                    Button {
                        fullResync()
                    } label: {
                        Label("Full resync", systemImage: "arrow.counterclockwise")
                    }
                    .disabled(syncing)
                } header: {
                    Text("Sync scope")
                } footer: {
                    Text("Narrowing the scope keeps already-synced memories but stops updating them. Full resync re-reads everything in scope — use it after moving files between folders.")
                }
            }

            Section("Memories") {
                if memories.isEmpty {
                    Text("Nothing synced yet.").foregroundStyle(.secondary)
                } else {
                    ForEach(memories) { memory in
                        NavigationLink {
                            MemoryDetailView(memory: memory)
                        } label: {
                            MemoryRow(memory: memory)
                        }
                    }
                }
            }

            Section {
                Button(role: .destructive) {
                    confirmingDisconnect = true
                } label: {
                    Label("Disconnect source", systemImage: "trash")
                }
            } footer: {
                Text("Removes the connection and its access token. Already-synced memories stay in your vault.")
            }
        }
        .navigationTitle(account.displayName)
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog("Disconnect \(account.displayName)?", isPresented: $confirmingDisconnect) {
            Button("Disconnect", role: .destructive) {
                KeychainStore.delete(for: account.keychainKey)
                context.delete(account)
                try? context.save()
                dismiss()
            }
        }
        .sheet(isPresented: $showingScopePicker) {
            if let config = driveConfig,
               let tokens = KeychainStore.load(GoogleTokens.self, for: account.keychainKey) {
                DriveFolderPickerView(
                    title: "Synced folders",
                    initialSelection: config.selectedFolderIDs ?? [],
                    loader: {
                        try await DriveFolderService.fetch(
                            tokens: tokens,
                            clientID: config.clientID,
                            keychainKey: account.keychainKey
                        )
                    },
                    onConfirm: { folders in
                        saveScope(folderIDs: folders.map(\.id), config: config)
                    }
                )
            }
        }
    }

    private func saveScope(folderIDs: [String], config: GoogleDriveConfig) {
        var updated = config
        updated.selectedFolderIDs = folderIDs.isEmpty ? nil : folderIDs
        account.configData = try? JSONEncoder().encode(updated)
        // Scope changed: reset the cursor so history in newly included
        // folders backfills (the modifiedTime cursor would skip old files).
        account.syncCursor = nil
        try? context.save()
        runSync()
    }

    private func fullResync() {
        account.syncCursor = nil
        try? context.save()
        runSync()
    }

    private func runSync() {
        syncing = true
        Task {
            await SyncManager.shared.syncAll()
            syncing = false
        }
    }
}
