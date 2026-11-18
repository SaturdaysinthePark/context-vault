import SwiftUI
import SwiftData
import UniformTypeIdentifiers

/// Connected sources: Gmail, Google Drive, Notion, and folder-based sources
/// (Obsidian or any Markdown folder).
struct SourcesView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \SourceAccount.createdAt) private var accounts: [SourceAccount]
    @State private var showingFolderPicker = false
    @State private var pickerSourceType: SourceType = .obsidian
    @State private var showingGoogleDriveConnect = false
    @State private var showingNotionConnect = false
    @State private var showingGmailConnect = false
    @State private var syncing = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(accounts) { account in
                        NavigationLink {
                            SourceDetailView(account: account)
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(account.displayName).font(.headline)
                                if let last = account.lastSyncedAt {
                                    Text("Last synced \(last.formatted(.relative(presentation: .named)))")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                } else {
                                    Text("Not synced yet")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                    .onDelete { offsets in
                        for offset in offsets {
                            KeychainStore.delete(for: accounts[offset].keychainKey)
                            let accountID = accounts[offset].id
                            Task { await SpotlightIndexer.shared.removeSources(ids: [accountID]) }
                            context.delete(accounts[offset])
                        }
                        try? context.save()
                    }
                } header: {
                    Text("Connected")
                } footer: {
                    if accounts.isEmpty {
                        Text("Nothing connected yet. Your vault syncs entirely on device.")
                    } else {
                        Text("Tap a source to browse its memories, adjust sync scope, or disconnect.")
                    }
                }

                Section {
                    Button {
                        pickerSourceType = .obsidian
                        showingFolderPicker = true
                    } label: {
                        Label("Obsidian vault", systemImage: "folder.badge.gearshape")
                    }
                    Button {
                        pickerSourceType = .files
                        showingFolderPicker = true
                    } label: {
                        Label("Markdown folder", systemImage: "folder")
                    }
                    // One-account sources disappear once connected.
                    if !accounts.contains(where: { $0.sourceType == .gmail }) {
                        Button {
                            showingGmailConnect = true
                        } label: {
                            Label("Gmail", systemImage: "envelope")
                        }
                    }
                    if !accounts.contains(where: { $0.sourceType == .googleDrive }) {
                        Button {
                            showingGoogleDriveConnect = true
                        } label: {
                            Label("Google Drive", systemImage: "externaldrive")
                        }
                    }
                    if !accounts.contains(where: { $0.sourceType == .notion }) {
                        Button {
                            showingNotionConnect = true
                        } label: {
                            Label("Notion", systemImage: "n.square")
                        }
                    }
                } header: {
                    Text("Add a source")
                } footer: {
                    if accounts.contains(where: { [.gmail, .googleDrive, .notion].contains($0.sourceType) }) {
                        Text("Already-connected sources are managed above. Folder sources can be added more than once.")
                    }
                }
            }
            .navigationTitle("Sources")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    NavigationLink {
                        PrivacyView()
                    } label: {
                        Label("Privacy", systemImage: "hand.raised")
                    }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        syncing = true
                        Task {
                            await SyncManager.shared.syncAll()
                            syncing = false
                        }
                    } label: {
                        if syncing {
                            ProgressView()
                        } else {
                            Label("Sync now", systemImage: "arrow.triangle.2.circlepath")
                        }
                    }
                    .disabled(syncing || accounts.isEmpty)
                }
            }
            .fileImporter(
                isPresented: $showingFolderPicker,
                allowedContentTypes: [.folder]
            ) { result in
                guard case .success(let url) = result else { return }
                addFolderSource(url)
            }
            .sheet(isPresented: $showingGoogleDriveConnect) {
                GoogleDriveConnectSheet()
            }
            .sheet(isPresented: $showingNotionConnect) {
                NotionConnectSheet()
            }
            .sheet(isPresented: $showingGmailConnect) {
                GmailConnectSheet()
            }
        }
    }

    private func addFolderSource(_ url: URL) {
        guard url.startAccessingSecurityScopedResource() else { return }
        defer { url.stopAccessingSecurityScopedResource() }

        do {
            // Plain bookmark: on iOS the security scope is carried implicitly
            // (the macOS-only .withSecurityScope option doesn't exist here).
            let bookmark = try url.bookmarkData(
                options: [],
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
            let account = SourceAccount(
                sourceType: pickerSourceType,
                displayName: url.lastPathComponent,
                configData: bookmark
            )
            context.insert(account)
            try context.save()

            Task { await SyncManager.shared.syncAll() }
        } catch {
            // Bookmark creation failed; nothing persisted.
        }
    }
}
