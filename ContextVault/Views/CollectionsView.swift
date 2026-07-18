import SwiftUI
import SwiftData

/// Collections with aspects, live rules, and the per-collection Siri
/// visibility toggle.
struct CollectionsView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \MemoryCollection.name) private var collections: [MemoryCollection]
    @State private var showingNew = false

    var body: some View {
        NavigationStack {
            Group {
                if collections.isEmpty {
                    ContentUnavailableView(
                        "No collections yet",
                        systemImage: "square.stack.3d.up",
                        description: Text("Collections group memories — by hand or by subscribing to sources and folders — and control what Siri can see.")
                    )
                } else {
                    List {
                        ForEach(collections) { collection in
                            NavigationLink {
                                CollectionDetailView(collection: collection)
                            } label: {
                                VStack(alignment: .leading, spacing: 4) {
                                    HStack {
                                        Text(collection.name).font(.headline)
                                        Spacer()
                                        if !collection.rules.isEmpty {
                                            Image(systemName: "arrow.triangle.2.circlepath.circle")
                                                .foregroundStyle(.secondary)
                                                .accessibilityLabel("Has live rules")
                                        }
                                        if !collection.siriVisible {
                                            Image(systemName: "eye.slash")
                                                .foregroundStyle(.secondary)
                                                .accessibilityLabel("Hidden from Siri")
                                        }
                                    }
                                    Text("\(collection.memories.count) memories")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                        .onDelete { offsets in
                            for offset in offsets {
                                context.delete(collections[offset])
                            }
                            try? context.save()
                        }
                    }
                }
            }
            .navigationTitle("Collections")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button("New", systemImage: "plus") { showingNew = true }
                }
            }
            .sheet(isPresented: $showingNew) {
                CollectionFormSheet(collection: nil)
            }
        }
    }
}

struct CollectionDetailView: View {
    @Bindable var collection: MemoryCollection
    @Environment(\.modelContext) private var context
    @State private var showingAddMemories = false
    @State private var showingEdit = false
    @State private var showingEntireSourcePicker = false
    @State private var showingDriveFolderFlow = false
    @State private var showingObsidianFolderPicker = false

    var body: some View {
        List {
            Section {
                Toggle(isOn: $collection.siriVisible) {
                    Label("Visible to Siri & Apple Intelligence", systemImage: "sparkles")
                }
                .onChange(of: collection.siriVisible) {
                    Task { @MainActor in
                        try? await VaultStore.shared.reindexCollection(collection)
                    }
                }
            } footer: {
                Text("When off, memories in this collection are removed from the system index and Siri can't use them as context.")
            }

            if !collection.details.isEmpty {
                Section("About") {
                    Text(collection.details).font(.callout)
                }
            }

            if !collection.aspects.isEmpty {
                Section("Aspects") {
                    ForEach(collection.aspects, id: \.self) { aspect in
                        LabeledContent(aspect.kind.rawValue.capitalized, value: aspect.value)
                    }
                }
            }

            Section {
                if collection.rules.isEmpty {
                    Text("No rules — this collection only contains hand-picked memories.")
                        .foregroundStyle(.secondary)
                        .font(.callout)
                } else {
                    ForEach(collection.rules) { rule in
                        Label(rule.displayName,
                              systemImage: rule.kind == .entireSource ? "externaldrive.connected.to.line.below" : "folder.badge.gearshape")
                    }
                    .onDelete { offsets in
                        var rules = collection.rules
                        rules.remove(atOffsets: offsets)
                        collection.rules = rules
                        try? context.save()
                    }
                }
            } header: {
                Text("Rules")
            } footer: {
                Text("Rules keep this collection live: new memories from a subscribed source or folder join automatically on every sync. Removing a rule keeps memories already added.")
            }

            Section {
                Menu {
                    Button {
                        showingDriveFolderFlow = true
                    } label: {
                        Label("Add Google Drive folder…", systemImage: "externaldrive")
                    }
                    Button {
                        showingObsidianFolderPicker = true
                    } label: {
                        Label("Add notes folder…", systemImage: "folder")
                    }
                    Button {
                        showingEntireSourcePicker = true
                    } label: {
                        Label("Add entire source…", systemImage: "externaldrive.connected.to.line.below")
                    }
                    Divider()
                    Button {
                        showingAddMemories = true
                    } label: {
                        Label("Pick individual memories…", systemImage: "checklist")
                    }
                } label: {
                    Label("Add to collection", systemImage: "plus.circle")
                }

                if collection.memories.isEmpty {
                    Text("No memories yet.").foregroundStyle(.secondary)
                } else {
                    ForEach(collection.memories) { memory in
                        NavigationLink {
                            MemoryDetailView(memory: memory)
                        } label: {
                            MemoryRow(memory: memory)
                        }
                    }
                    .onDelete { offsets in
                        removeMemories(at: offsets)
                    }
                }
            } header: {
                Text("Memories")
            }
        }
        .navigationTitle(collection.name)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Edit") { showingEdit = true }
            }
            ToolbarItem(placement: .secondaryAction) {
                ShareLink(
                    item: ContextPackExporter.render(
                        aboutMe: (try? VaultStore.shared.aboutMeCard())
                            .flatMap { $0.siriVisible ? $0.content : nil },
                        collections: [ContextPackExporter.input(from: collection)]
                    ),
                    preview: SharePreview("\(collection.name) — Context Pack")
                ) {
                    Label("Export Context Pack (Markdown for any AI)", systemImage: "square.and.arrow.up")
                }
            }
        }
        .sheet(isPresented: $showingAddMemories) {
            AddMemoriesSheet(collection: collection)
        }
        .sheet(isPresented: $showingEdit) {
            CollectionFormSheet(collection: collection)
        }
        .sheet(isPresented: $showingEntireSourcePicker) {
            EntireSourceRuleSheet(collection: collection)
        }
        .sheet(isPresented: $showingDriveFolderFlow) {
            DriveFolderRuleSheet(collection: collection)
        }
        .sheet(isPresented: $showingObsidianFolderPicker) {
            NotesFolderRuleSheet(collection: collection)
        }
    }

    private func removeMemories(at offsets: IndexSet) {
        var exclusions = collection.excludedMemoryIDs
        for offset in offsets {
            let memory = collection.memories[offset]
            exclusions.insert(memory.id)
            memory.collections.removeAll { $0.id == collection.id }
        }
        collection.excludedMemoryIDs = exclusions
        try? context.save()
        Task { @MainActor in
            try? await VaultStore.shared.reindexCollection(collection)
        }
    }
}

// MARK: - Rule creation sheets

/// Subscribe a collection to everything from one source.
struct EntireSourceRuleSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Bindable var collection: MemoryCollection
    @Query(sort: \SourceAccount.createdAt) private var accounts: [SourceAccount]

    var body: some View {
        NavigationStack {
            List {
                if accounts.isEmpty {
                    Text("No sources connected yet.").foregroundStyle(.secondary)
                }
                ForEach(accounts) { account in
                    Button {
                        addRule(for: account)
                    } label: {
                        Label(account.displayName, systemImage: "externaldrive.connected.to.line.below")
                    }
                }
            }
            .navigationTitle("Add entire source")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    private func addRule(for account: SourceAccount) {
        let rule = CollectionRule(
            sourceAccountID: account.id,
            sourceTypeRaw: account.sourceTypeRaw,
            kind: .entireSource,
            displayName: "Entire source: \(account.displayName)"
        )
        collection.rules.append(rule)
        applyNewRule(rule, to: collection, context: context)
        dismiss()
    }
}

/// Subscribe a collection to Google Drive folders (subtrees included).
struct DriveFolderRuleSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Bindable var collection: MemoryCollection
    @Query(sort: \SourceAccount.createdAt) private var accounts: [SourceAccount]

    @State private var pickerAccount: SourceAccount?

    private var driveAccounts: [SourceAccount] {
        accounts.filter { $0.sourceType == .googleDrive }
    }

    var body: some View {
        NavigationStack {
            List {
                if driveAccounts.isEmpty {
                    Text("Connect Google Drive in Sources first.").foregroundStyle(.secondary)
                }
                ForEach(driveAccounts) { account in
                    Button {
                        pickerAccount = account
                    } label: {
                        Label(account.displayName, systemImage: "externaldrive")
                    }
                }
            }
            .navigationTitle("Add Drive folder")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .sheet(item: $pickerAccount) { account in
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
                            addRules(folders: folders, account: account)
                        }
                    )
                }
            }
        }
    }

    private func addRules(folders: [(id: String, path: String)], account: SourceAccount) {
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
        dismiss()
    }
}

/// Subscribe a collection to known folders of file-based sources (Obsidian /
/// Markdown). Folders are derived from already-synced memories — no
/// filesystem browsing needed.
struct NotesFolderRuleSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Bindable var collection: MemoryCollection
    @Query(sort: \SourceAccount.createdAt) private var accounts: [SourceAccount]
    @Query private var memories: [Memory]

    private var folderOptions: [(account: SourceAccount, path: String)] {
        let fileAccounts = accounts.filter { $0.sourceType == .obsidian || $0.sourceType == .files }
        var result: [(SourceAccount, String)] = []
        for account in fileAccounts {
            let prefix = "obsidian:\(account.id.uuidString):"
            let paths = Set(
                memories
                    .filter { $0.sourceRef?.hasPrefix(prefix) == true }
                    .compactMap(\.sourcePath)
            )
            for path in paths.sorted() {
                result.append((account, path))
            }
        }
        return result
    }

    var body: some View {
        NavigationStack {
            List {
                if folderOptions.isEmpty {
                    Text("No subfolders found in your synced notes yet.")
                        .foregroundStyle(.secondary)
                }
                ForEach(Array(folderOptions.enumerated()), id: \.offset) { _, option in
                    Button {
                        addRule(account: option.account, path: option.path)
                    } label: {
                        VStack(alignment: .leading) {
                            Label(option.path, systemImage: "folder")
                            Text(option.account.displayName)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .navigationTitle("Add notes folder")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    private func addRule(account: SourceAccount, path: String) {
        let rule = CollectionRule(
            sourceAccountID: account.id,
            sourceTypeRaw: account.sourceTypeRaw,
            kind: .folder,
            folderPath: path,
            displayName: "\(account.displayName) · \(path)"
        )
        collection.rules.append(rule)
        applyNewRule(rule, to: collection, context: context)
        dismiss()
    }
}

/// Shared post-rule-creation work: retroactive apply + reindex.
@MainActor
private func applyNewRule(_ rule: CollectionRule, to collection: MemoryCollection, context: ModelContext) {
    try? context.save()
    let changed = (try? CollectionRuleEngine.applyRetroactively(rule, to: collection)) ?? []
    let snapshots = changed.map(MemorySnapshot.init)
    Task {
        try? await SpotlightIndexer.shared.reindex(memories: snapshots)
    }
}

// MARK: - Membership picker

/// Multi-select picker for adding/removing vault memories in a collection,
/// with a source filter.
struct AddMemoriesSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var collection: MemoryCollection
    @Query(sort: \Memory.modifiedAt, order: .reverse) private var memories: [Memory]
    @Query(sort: \SourceAccount.createdAt) private var accounts: [SourceAccount]
    @State private var searchText = ""
    @State private var sourceFilter: UUID? // SourceAccount.id

    private var filtered: [Memory] {
        var result = memories
        if let sourceFilter, let account = accounts.first(where: { $0.id == sourceFilter }) {
            let prefixes = ["gdrive:", "notion:", "obsidian:"].map { "\($0)\(account.id.uuidString):" }
            result = result.filter { memory in
                guard let ref = memory.sourceRef else { return false }
                return prefixes.contains { ref.hasPrefix($0) }
            }
        }
        guard !searchText.isEmpty else { return result }
        return result.filter {
            $0.title.localizedCaseInsensitiveContains(searchText) ||
            $0.body.localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("Source", selection: $sourceFilter) {
                    Text("All sources").tag(UUID?.none)
                    ForEach(accounts) { account in
                        Text(account.displayName).tag(UUID?.some(account.id))
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
                .padding(.top, 8)

                List(filtered) { memory in
                    let isMember = memory.collections.contains { $0.id == collection.id }
                    Button {
                        toggle(memory)
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(memory.title).lineLimit(1).foregroundStyle(.primary)
                                Text(memory.sourcePath ?? memory.body)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                            Spacer()
                            Image(systemName: isMember ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(isMember ? AnyShapeStyle(.tint) : AnyShapeStyle(.tertiary))
                        }
                    }
                }
                .searchable(text: $searchText, prompt: "Search your vault")
            }
            .navigationTitle("Add to \(collection.name)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                        Task { @MainActor in
                            try? await VaultStore.shared.reindexCollection(collection)
                        }
                    }
                }
            }
        }
    }

    private func toggle(_ memory: Memory) {
        if let index = memory.collections.firstIndex(where: { $0.id == collection.id }) {
            memory.collections.remove(at: index)
            // User removal: rules must never re-add this memory.
            collection.excludedMemoryIDs.insert(memory.id)
        } else {
            memory.collections.append(collection)
            collection.excludedMemoryIDs.remove(memory.id)
        }
        try? memory.modelContext?.save()
    }
}

// MARK: - Create / edit form

struct CollectionFormSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    /// nil = create mode; non-nil = edit mode.
    let collection: MemoryCollection?

    @State private var name = ""
    @State private var details = ""
    @State private var aspects: [Aspect] = []
    @State private var newAspectKind: Aspect.Kind = .topic
    @State private var newAspectValue = ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name", text: $name)
                    TextField("Description (optional)", text: $details, axis: .vertical)
                        .lineLimit(2...4)
                } header: {
                    Text("Collection")
                } footer: {
                    Text("The description is indexed with this collection's memories and given to the AI when you scope questions to it — a good one sharpens both Siri matching and chat answers.")
                }
                Section("Aspects") {
                    ForEach(aspects, id: \.self) { aspect in
                        LabeledContent(aspect.kind.rawValue.capitalized, value: aspect.value)
                    }
                    .onDelete { aspects.remove(atOffsets: $0) }

                    HStack {
                        Picker("", selection: $newAspectKind) {
                            ForEach(Aspect.Kind.allCases, id: \.self) {
                                Text($0.rawValue.capitalized).tag($0)
                            }
                        }
                        .labelsHidden()
                        TextField("Value", text: $newAspectValue)
                        Button("Add", systemImage: "plus.circle.fill") {
                            aspects.append(Aspect(kind: newAspectKind, value: newAspectValue))
                            newAspectValue = ""
                        }
                        .labelStyle(.iconOnly)
                        .disabled(newAspectValue.isEmpty)
                    }
                }
            }
            .navigationTitle(collection == nil ? "New Collection" : "Edit Collection")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(collection == nil ? "Create" : "Save") {
                        save()
                        dismiss()
                    }
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .onAppear {
                if let collection {
                    name = collection.name
                    details = collection.details
                    aspects = collection.aspects
                }
            }
        }
    }

    private func save() {
        if let collection {
            collection.name = name
            collection.details = details
            collection.aspects = aspects
            try? context.save()
            Task { @MainActor in
                try? await VaultStore.shared.reindexCollection(collection)
            }
        } else {
            let created = MemoryCollection(name: name, details: details, aspects: aspects)
            context.insert(created)
            try? context.save()
        }
    }
}
