import SwiftUI
import SwiftData

/// Guided add-to-collection flow:
///   1. choose a source →
///   2. choose how to add from it (entire source / folders / files) →
///   3. pick →
///   4. added (sheet dismisses back to the collection).
struct AddToCollectionSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var collection: MemoryCollection
    @Query(sort: \SourceAccount.createdAt) private var accounts: [SourceAccount]
    @Query private var memories: [Memory]

    var body: some View {
        NavigationStack {
            List {
                Section {
                    if accounts.isEmpty {
                        Text("No sources connected — connect one in the Sources tab, or pick from memories below.")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(accounts) { account in
                        NavigationLink {
                            SourceAddOptionsView(collection: collection, account: account, onDone: { dismiss() })
                        } label: {
                            HStack {
                                Label(account.displayName, systemImage: icon(for: account.sourceType))
                                Spacer()
                                Text("\(memoryCount(for: account))")
                                    .foregroundStyle(.secondary)
                                    .font(.caption)
                            }
                        }
                    }
                } header: {
                    Text("Add from a source")
                }

                Section {
                    NavigationLink {
                        AddMemoriesSheet(collection: collection, embedded: true)
                            .navigationTitle("All memories")
                    } label: {
                        Label("Browse all memories", systemImage: "archivebox")
                    }
                } footer: {
                    Text("Pick individual memories from anywhere in your vault, including manual captures.")
                }
            }
            .navigationTitle("Add to \(collection.name)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    private func memoryCount(for account: SourceAccount) -> Int {
        let prefixes = sourceRefPrefixes(for: account)
        return memories.filter { memory in
            guard let ref = memory.sourceRef else { return false }
            return prefixes.contains { ref.hasPrefix($0) }
        }.count
    }
}

/// Step 2: how to add from this source.
struct SourceAddOptionsView: View {
    @Environment(\.modelContext) private var context
    @Bindable var collection: MemoryCollection
    let account: SourceAccount
    let onDone: () -> Void

    @State private var showingDrivePicker = false

    var body: some View {
        List {
            Section {
                Button {
                    addEntireSource()
                } label: {
                    optionRow(
                        title: "Entire \(shortName)",
                        subtitle: "Everything from this source, now and in the future.",
                        icon: "externaldrive.connected.to.line.below"
                    )
                }

                switch account.sourceType {
                case .googleDrive:
                    Button {
                        showingDrivePicker = true
                    } label: {
                        optionRow(
                            title: "Choose folders…",
                            subtitle: "Selected folders stay synced — new files join automatically.",
                            icon: "folder.badge.gearshape"
                        )
                    }
                case .obsidian, .files:
                    NavigationLink {
                        NotesFolderOptionsView(collection: collection, account: account, onDone: onDone)
                    } label: {
                        optionRow(
                            title: "Choose folders…",
                            subtitle: "Selected folders stay synced — new notes join automatically.",
                            icon: "folder.badge.gearshape"
                        )
                    }
                default:
                    EmptyView()
                }

                NavigationLink {
                    AddMemoriesSheet(collection: collection, fixedAccountID: account.id, embedded: true)
                        .navigationTitle(filesLabel)
                } label: {
                    optionRow(
                        title: "\(filesLabel)…",
                        subtitle: "Hand-pick specific items. One-time — they don't stay synced.",
                        icon: "checklist"
                    )
                }
            } footer: {
                Text("Folders and entire sources are live subscriptions; individually picked items are static.")
            }
        }
        .navigationTitle(account.displayName)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showingDrivePicker) {
            driveFolderPicker
        }
    }

    private var shortName: String {
        switch account.sourceType {
        case .googleDrive: "Google Drive"
        case .notion: "Notion"
        case .obsidian: "vault"
        default: "source"
        }
    }

    private var filesLabel: String {
        switch account.sourceType {
        case .googleDrive: "Choose files"
        case .notion: "Choose pages"
        default: "Choose notes"
        }
    }

    private func optionRow(title: String, subtitle: String, icon: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundStyle(.tint)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).foregroundStyle(.primary)
                Text(subtitle).font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var driveFolderPicker: some View {
        if let config = account.configData.flatMap({ try? JSONDecoder().decode(GoogleDriveConfig.self, from: $0) }),
           let tokens = KeychainStore.load(GoogleTokens.self, for: account.keychainKey) {
            DriveFolderPickerView(
                title: "Choose folders",
                loader: {
                    try await DriveFolderService.fetch(
                        tokens: tokens,
                        clientID: config.clientID,
                        keychainKey: account.keychainKey
                    )
                },
                onConfirm: { folders in
                    for folder in folders {
                        let rule = CollectionRule(
                            sourceAccountID: account.id,
                            sourceTypeRaw: account.sourceTypeRaw,
                            kind: .folder,
                            folderID: folder.id,
                            folderPath: folder.path,
                            displayName: "\(account.displayName) · \(folder.path)"
                        )
                        collection.rules.append(rule)
                        applyNewRule(rule, to: collection, context: context)
                    }
                    onDone()
                }
            )
        }
    }

    private func addEntireSource() {
        let rule = CollectionRule(
            sourceAccountID: account.id,
            sourceTypeRaw: account.sourceTypeRaw,
            kind: .entireSource,
            displayName: "Everything from \(account.displayName)"
        )
        collection.rules.append(rule)
        applyNewRule(rule, to: collection, context: context)
        onDone()
    }
}

/// Step 3 for file-based sources: known folders derived from synced notes.
struct NotesFolderOptionsView: View {
    @Environment(\.modelContext) private var context
    @Bindable var collection: MemoryCollection
    let account: SourceAccount
    let onDone: () -> Void
    @Query private var memories: [Memory]

    private var folders: [String] {
        let prefix = "obsidian:\(account.id.uuidString):"
        return Set(
            memories
                .filter { $0.sourceRef?.hasPrefix(prefix) == true }
                .compactMap(\.sourcePath)
        ).sorted()
    }

    var body: some View {
        List {
            if folders.isEmpty {
                Text("No subfolders found in this source's synced notes yet.")
                    .foregroundStyle(.secondary)
            }
            ForEach(folders, id: \.self) { path in
                Button {
                    addRule(path: path)
                } label: {
                    Label(path, systemImage: "folder")
                        .foregroundStyle(.primary)
                }
            }
        }
        .navigationTitle("Choose folder")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func addRule(path: String) {
        let rule = CollectionRule(
            sourceAccountID: account.id,
            sourceTypeRaw: account.sourceTypeRaw,
            kind: .folder,
            folderPath: path,
            displayName: "\(account.displayName) · \(path)"
        )
        collection.rules.append(rule)
        applyNewRule(rule, to: collection, context: context)
        onDone()
    }
}

/// Shared post-rule-creation work: retroactive apply + reindex.
@MainActor
func applyNewRule(_ rule: CollectionRule, to collection: MemoryCollection, context: ModelContext) {
    try? context.save()
    let changed = (try? CollectionRuleEngine.applyRetroactively(rule, to: collection)) ?? []
    let snapshots = changed.map(MemorySnapshot.init)
    Task {
        try? await SpotlightIndexer.shared.reindex(memories: snapshots)
    }
}

/// sourceRef prefixes for one account across connector types.
func sourceRefPrefixes(for account: SourceAccount) -> [String] {
    ["gdrive:", "notion:", "obsidian:"].map { "\($0)\(account.id.uuidString):" }
}

/// Icon for a source type (shared by source lists).
func icon(for sourceType: SourceType) -> String {
    switch sourceType {
    case .googleDrive: "externaldrive"
    case .notion: "n.square"
    case .obsidian, .files: "folder"
    case .manual, .shareExtension: "square.and.pencil"
    }
}
