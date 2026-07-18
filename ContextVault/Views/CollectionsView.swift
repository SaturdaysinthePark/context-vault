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
    @State private var showingAdd = false
    @State private var showingEdit = false
    @State private var unsubscribeTarget: CollectionRule?

    /// Memories grouped by the first synced folder/source they match, plus
    /// the hand-picked remainder. Order: rules in creation order, then
    /// hand-picked.
    private var groups: [(rule: CollectionRule?, memories: [Memory])] {
        var remaining = collection.memories.sorted { $0.modifiedAt > $1.modifiedAt }
        var result: [(CollectionRule?, [Memory])] = []

        for rule in collection.rules {
            let matched = remaining.filter { CollectionRuleEngine.matches(rule, $0) }
            remaining.removeAll { memory in matched.contains { $0.id == memory.id } }
            result.append((rule, matched))
        }
        result.append((nil, remaining))
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
        let grouped = groups
        ForEach(Array(grouped.enumerated()), id: \.offset) { index, group in
            let isLastSyncedGroup = group.rule != nil
                && (index + 1 >= grouped.count || grouped[index + 1].rule == nil)
            Section {
                if group.memories.isEmpty {
                    Text(group.rule == nil ? "No hand-picked memories." : "Nothing synced from here yet.")
                        .foregroundStyle(.secondary)
                        .font(.callout)
                } else {
                    ForEach(group.memories) { memory in
                        NavigationLink {
                            MemoryDetailView(memory: memory)
                        } label: {
                            MemoryRow(memory: memory)
                        }
                    }
                    .onDelete { offsets in
                        removeMemories(group.memories, at: offsets)
                    }
                }
            } header: {
                if let rule = group.rule {
                    HStack {
                        Label("\(rule.displayName) (\(group.memories.count))",
                              systemImage: rule.kind == .folder ? "folder.badge.gearshape" : "externaldrive.connected.to.line.below")
                        Spacer()
                        Menu {
                            Button("Unsubscribe…", role: .destructive) {
                                unsubscribeTarget = rule
                            }
                        } label: {
                            Image(systemName: "ellipsis.circle")
                        }
                    }
                } else {
                    Text("Hand-picked (\(group.memories.count))")
                }
            } footer: {
                if isLastSyncedGroup {
                    Text("Synced folders stay live — new files in them join this collection on every sync.")
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
