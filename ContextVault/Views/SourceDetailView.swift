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

    private var gmailConfig: GmailConfig? {
        account.configData.flatMap { try? JSONDecoder().decode(GmailConfig.self, from: $0) }
    }

    /// Reads and writes the Gmail scope stored in the account's config.
    /// Changing it clears the sync cursor so the next sync reaches back
    /// over the lookback window with the new query.
    private var gmailScope: Binding<GmailScope> {
        Binding(
            get: { gmailConfig?.scope ?? .transactional },
            set: { newScope in
                guard var config = gmailConfig, config.scope != newScope else { return }
                config.scope = newScope
                account.configData = try? JSONEncoder().encode(config)
                account.syncCursor = nil
                try? context.save()
                runSync()
            }
        )
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

            if account.sourceType == .gmail {
                Section {
                    Picker("Mail to read", selection: gmailScope) {
                        ForEach(GmailScope.allCases, id: \.self) { option in
                            Text(option.title).tag(option)
                        }
                    }
                } header: {
                    Text("Scope")
                } footer: {
                    Text("\(gmailScope.wrappedValue.explanation) Messages stay on this device; Siri is only given the short facts distilled from them.")
                }
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

            Section {
                NavigationLink {
                    SourceMemoriesView(title: account.displayName, memories: memories)
                } label: {
                    Label("View memories (\(memories.count))", systemImage: "archivebox")
                }
            }

            Section {
                Button(role: .destructive) {
                    confirmingDisconnect = true
                } label: {
                    Label("Disconnect source", systemImage: "trash")
                }
            } footer: {
                Text("Removes the connection and its access token. Already-synced memories and cards stay in your vault, and stay visible to Siri until you delete them or hide them in Privacy.")
            }
        }
        .navigationTitle(account.displayName)
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog("Disconnect \(account.displayName)?", isPresented: $confirmingDisconnect) {
            Button("Disconnect", role: .destructive) {
                KeychainStore.delete(for: account.keychainKey)
                // The source itself stops being findable by Siri. What was
                // already gathered from it stays in the vault, as before.
                let accountID = account.id
                Task { await SpotlightIndexer.shared.removeSources(ids: [accountID]) }
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

/// A source's memories, mirrored in the source's own folder structure:
/// one section per folder path, root items first, searchable.
struct SourceMemoriesView: View {
    let title: String
    let memories: [Memory]
    @State private var searchText = ""

    private var filtered: [Memory] {
        guard !searchText.isEmpty else { return memories }
        return memories.filter {
            $0.title.localizedCaseInsensitiveContains(searchText) ||
            $0.body.localizedCaseInsensitiveContains(searchText)
        }
    }

    /// Folder path → memories, root ("" key) first, then alphabetical.
    private var grouped: [(folder: String, memories: [Memory])] {
        let dictionary = Dictionary(grouping: filtered) { $0.sourcePath ?? "" }
        return dictionary
            .sorted { a, b in
                if a.key.isEmpty != b.key.isEmpty { return a.key.isEmpty }
                return a.key.localizedCaseInsensitiveCompare(b.key) == .orderedAscending
            }
            .map { (folder: $0.key, memories: $0.value.sorted { $0.modifiedAt > $1.modifiedAt }) }
    }

    var body: some View {
        List {
            ForEach(grouped, id: \.folder) { group in
                Section {
                    ForEach(group.memories) { memory in
                        NavigationLink {
                            MemoryDetailView(memory: memory)
                        } label: {
                            MemoryRow(memory: memory)
                        }
                    }
                } header: {
                    Label(group.folder.isEmpty ? "Top level" : group.folder,
                          systemImage: "folder")
                }
            }
        }
        .searchable(text: $searchText, prompt: "Search this source")
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .overlay {
            if memories.isEmpty {
                ContentUnavailableView("Nothing synced yet", systemImage: "archivebox")
            }
        }
    }
}
