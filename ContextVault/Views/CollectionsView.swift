import SwiftUI
import SwiftData

/// Collections with aspects, synced folders/sources, and the per-collection
/// Siri visibility toggle.
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
                        description: Text("Collections group memories — subscribe whole folders and sources, or hand-pick — and control what Siri can see.")
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
                                                .accessibilityLabel("Has synced folders or sources")
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
    @Query(sort: \SourceAccount.createdAt) private var accounts: [SourceAccount]
    @State private var showingAdd = false
    @State private var showingEdit = false
    @State private var unsubscribeTarget: CollectionRule?
    @State private var collapsedGroups: Set<UUID?> = []

    /// The collection scaffolded by source: each involved source lists its
    /// subscriptions (folders / entire source) and its hand-picked singles;
    /// manual captures land in a final "Captured" group.
    private struct SourceGroup {
        var accountID: UUID?          // nil = Captured
        var title: String
        var iconName: String
        var subscriptions: [(rule: CollectionRule, memories: [Memory])] = []
        var singles: [Memory] = []
    }

    private var sourceGroups: [SourceGroup] {
        var remaining = collection.memories.sorted { $0.modifiedAt > $1.modifiedAt }

        // 1. Subscriptions claim their matches (first-match dedupe).
        var subscriptionsByAccount: [UUID: [(CollectionRule, [Memory])]] = [:]
        for rule in collection.rules {
            let matched = remaining.filter { CollectionRuleEngine.matches(rule, $0) }
            remaining.removeAll { memory in matched.contains { $0.id == memory.id } }
            subscriptionsByAccount[rule.sourceAccountID, default: []].append((rule, matched))
        }

        // 2. Leftover members are singles, grouped by owning account.
        var singlesByAccount: [UUID: [Memory]] = [:]
        var captured: [Memory] = []
        for memory in remaining {
            if let owner = accounts.first(where: { account in
                sourceRefPrefixes(for: account).contains { memory.sourceRef?.hasPrefix($0) == true }
            }) {
                singlesByAccount[owner.id, default: []].append(memory)
            } else {
                captured.append(memory)
            }
        }

        // 3. Assemble in account order; keep groups that have content.
        var result: [SourceGroup] = []
        var coveredAccountIDs = Set<UUID>()
        for account in accounts {
            let subs = subscriptionsByAccount[account.id] ?? []
            let singles = singlesByAccount[account.id] ?? []
            coveredAccountIDs.insert(account.id)
            guard !subs.isEmpty || !singles.isEmpty else { continue }
            result.append(SourceGroup(
                accountID: account.id,
                title: account.displayName,
                iconName: icon(for: account.sourceType),
                subscriptions: subs,
                singles: singles
            ))
        }
        // Rules whose source was disconnected still render.
        for (accountID, subs) in subscriptionsByAccount where !coveredAccountIDs.contains(accountID) {
            result.append(SourceGroup(
                accountID: accountID,
                title: "Disconnected source",
                iconName: "questionmark.folder",
                subscriptions: subs
            ))
        }
        if !captured.isEmpty {
            result.append(SourceGroup(accountID: nil, title: "Captured", iconName: "square.and.pencil", singles: captured))
        }
        return result
    }

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
                Button {
                    showingAdd = true
                } label: {
                    Label("Add to collection", systemImage: "plus.circle")
                }
            }

            if collection.memories.isEmpty && collection.rules.isEmpty {
                Section {
                    Text("Nothing here yet — add folders, sources, or individual memories.")
                        .foregroundStyle(.secondary)
                }
            } else {
                memoryGroups
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
        .sheet(isPresented: $showingAdd) {
            AddToCollectionSheet(collection: collection)
        }
        .sheet(isPresented: $showingEdit) {
            CollectionFormSheet(collection: collection)
        }
        .confirmationDialog(
            "Unsubscribe from \(unsubscribeTarget?.displayName ?? "")?",
            isPresented: Binding(
                get: { unsubscribeTarget != nil },
                set: { if !$0 { unsubscribeTarget = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Unsubscribe, keep memories") {
                if let rule = unsubscribeTarget { unsubscribe(rule, removeMemories: false) }
            }
            Button("Unsubscribe and remove its memories", role: .destructive) {
                if let rule = unsubscribeTarget { unsubscribe(rule, removeMemories: true) }
            }
            Button("Cancel", role: .cancel) {}
        }
    }

    @ViewBuilder
    private var memoryGroups: some View {
        let grouped = sourceGroups
        let hasSubscriptions = grouped.contains { !$0.subscriptions.isEmpty }
        ForEach(Array(grouped.enumerated()), id: \.offset) { index, group in
            let isCollapsed = collapsedGroups.contains(group.accountID)
            Section {
                if !isCollapsed {
                    // Subscribed folders / entire-source rows: chevron into contents.
                    ForEach(group.subscriptions, id: \.0.id) { rule, matched in
                        NavigationLink {
                            SourceMemoriesView(title: rule.folderPath ?? "Everything", memories: matched)
                        } label: {
                            HStack {
                                Label(
                                    rule.kind == .folder ? (rule.folderPath ?? "Folder") : "Everything from this source",
                                    systemImage: rule.kind == .folder ? "folder.badge.gearshape" : "externaldrive.connected.to.line.below"
                                )
                                Spacer()
                                Text("\(matched.count)")
                                    .foregroundStyle(.secondary)
                                    .font(.caption)
                            }
                        }
                        .swipeActions(edge: .trailing) {
                            Button("Unsubscribe", role: .destructive) {
                                unsubscribeTarget = rule
                            }
                        }
                    }

                    // Hand-picked singles: title only — the header already
                    // names the source, so no preview or source line.
                    ForEach(group.singles) { memory in
                        NavigationLink {
                            MemoryDetailView(memory: memory)
                        } label: {
                            HStack {
                                Text(memory.title).lineLimit(1)
                                if memory.fidelity == .metadataOnly {
                                    Text("metadata only")
                                        .font(.caption2)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(.quaternary, in: Capsule())
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                    .onDelete { offsets in
                        removeMemories(group.singles, at: offsets)
                    }
                }
            } header: {
                Button {
                    withAnimation {
                        if isCollapsed {
                            collapsedGroups.remove(group.accountID)
                        } else {
                            collapsedGroups.insert(group.accountID)
                        }
                    }
                } label: {
                    HStack {
                        Image(systemName: isCollapsed ? "chevron.right" : "chevron.down")
                            .font(.caption2)
                        Label(group.title, systemImage: group.iconName)
                        Spacer()
                        if isCollapsed {
                            Text("\(group.subscriptions.count + group.singles.count)")
                                .font(.caption)
                        }
                    }
                }
                .buttonStyle(.plain)
            } footer: {
                if index == grouped.count - 1 && hasSubscriptions {
                    Text("Folders and sources stay live — new files in them join this collection on every sync. Swipe a folder to unsubscribe. Tap a source name to collapse it.")
                }
            }
        }
    }

    private func unsubscribe(_ rule: CollectionRule, removeMemories: Bool) {
        if removeMemories {
            // Detach this group's current members. No exclusions recorded —
            // the rule is gone, so nothing would re-add them.
            let members = collection.memories.filter { CollectionRuleEngine.matches(rule, $0) }
            for memory in members {
                memory.collections.removeAll { $0.id == collection.id }
            }
        }
        collection.rules.removeAll { $0.id == rule.id }
        try? context.save()
        Task { @MainActor in
            try? await VaultStore.shared.reindexCollection(collection)
        }
    }

    private func removeMemories(_ memories: [Memory], at offsets: IndexSet) {
        var exclusions = collection.excludedMemoryIDs
        for offset in offsets {
            let memory = memories[offset]
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

// MARK: - Membership picker

/// Multi-select picker for adding/removing vault memories in a collection.
/// With `fixedAccountID`, filters to one source and hides the source picker.
/// With `embedded`, renders for use inside an existing NavigationStack.
struct AddMemoriesSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var collection: MemoryCollection
    var fixedAccountID: UUID? = nil
    var embedded: Bool = false

    @Query(sort: \Memory.modifiedAt, order: .reverse) private var memories: [Memory]
    @Query(sort: \SourceAccount.createdAt) private var accounts: [SourceAccount]
    @State private var searchText = ""
    @State private var sourceFilter: UUID?

    private var activeFilter: UUID? { fixedAccountID ?? sourceFilter }

    private var filtered: [Memory] {
        var result = memories
        if let activeFilter, let account = accounts.first(where: { $0.id == activeFilter }) {
            let prefixes = sourceRefPrefixes(for: account)
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
        if embedded {
            content
        } else {
            NavigationStack {
                content
                    .navigationTitle("Add to \(collection.name)")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Done") {
                                dismiss()
                                finishReindex()
                            }
                        }
                    }
            }
        }
    }

    private var content: some View {
        VStack(spacing: 0) {
            if fixedAccountID == nil && accounts.count > 1 {
                Picker("Source", selection: $sourceFilter) {
                    Text("All sources").tag(UUID?.none)
                    ForEach(accounts) { account in
                        Text(account.displayName).tag(UUID?.some(account.id))
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
                .padding(.top, 8)
            }

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
            .searchable(text: $searchText, prompt: "Search")
        }
        .onDisappear {
            if embedded { finishReindex() }
        }
    }

    private func toggle(_ memory: Memory) {
        if let index = memory.collections.firstIndex(where: { $0.id == collection.id }) {
            memory.collections.remove(at: index)
            // User removal: synced folders/sources must never re-add it.
            collection.excludedMemoryIDs.insert(memory.id)
        } else {
            memory.collections.append(collection)
            collection.excludedMemoryIDs.remove(memory.id)
        }
        try? memory.modelContext?.save()
    }

    private func finishReindex() {
        let target = collection
        Task { @MainActor in
            try? await VaultStore.shared.reindexCollection(target)
        }
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
