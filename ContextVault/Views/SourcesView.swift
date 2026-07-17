import SwiftUI
import SwiftData
import UniformTypeIdentifiers

/// Connected sources. Phase 1 ships the folder-based connector (Obsidian or
/// any Markdown folder); Notion and Google Drive land in Phase 3.
struct SourcesView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \SourceAccount.createdAt) private var accounts: [SourceAccount]
    @State private var showingFolderPicker = false
    @State private var pickerSourceType: SourceType = .obsidian
    @State private var syncing = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(accounts) { account in
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
                    .onDelete { offsets in
                        for offset in offsets { context.delete(accounts[offset]) }
                        try? context.save()
                    }
                } header: {
                    Text("Connected")
                } footer: {
                    if accounts.isEmpty {
                        Text("Nothing connected yet. Your vault syncs entirely on device.")
                    }
                }

                Section("Add a source") {
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
                    LabeledContent {
                        Text("Coming soon").font(.caption).foregroundStyle(.secondary)
                    } label: {
                        Label("Notion", systemImage: "n.square")
                    }
                    LabeledContent {
                        Text("Coming soon").font(.caption).foregroundStyle(.secondary)
                    } label: {
                        Label("Google Drive", systemImage: "externaldrive")
                    }
                }
            }
            .navigationTitle("Sources")
            .toolbar {
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
