import SwiftUI
import SwiftData

/// Collections with aspects and the per-collection Siri visibility toggle.
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
                        description: Text("Collections group memories and control what Siri can see.")
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
                NewCollectionSheet()
            }
        }
    }
}

struct CollectionDetailView: View {
    @Bindable var collection: MemoryCollection
    @State private var showingAddMemories = false

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

            if !collection.aspects.isEmpty {
                Section("Aspects") {
                    ForEach(collection.aspects, id: \.self) { aspect in
                        LabeledContent(aspect.kind.rawValue.capitalized, value: aspect.value)
                    }
                }
            }

            Section("Memories") {
                Button {
                    showingAddMemories = true
                } label: {
                    Label("Add memories", systemImage: "plus.circle")
                }
                if collection.memories.isEmpty {
                    Text("No memories yet — add some from your vault.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(collection.memories) { memory in
                        NavigationLink {
                            MemoryDetailView(memory: memory)
                        } label: {
                            MemoryRow(memory: memory)
                        }
                    }
                }
            }
        }
        .navigationTitle(collection.name)
        .sheet(isPresented: $showingAddMemories) {
            AddMemoriesSheet(collection: collection)
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                ShareLink(
                    item: ContextPackExporter.render(
                        aboutMe: (try? VaultStore.shared.aboutMeCard())
                            .flatMap { $0.siriVisible ? $0.content : nil },
                        collections: [ContextPackExporter.input(from: collection)]
                    ),
                    preview: SharePreview("\(collection.name) — Context Pack")
                ) {
                    Label("Export Context Pack", systemImage: "square.and.arrow.up")
                }
            }
        }
    }
}

/// Multi-select picker for adding/removing vault memories in a collection.
struct AddMemoriesSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var collection: MemoryCollection
    @Query(sort: \Memory.modifiedAt, order: .reverse) private var memories: [Memory]
    @State private var searchText = ""

    private var filtered: [Memory] {
        guard !searchText.isEmpty else { return memories }
        return memories.filter {
            $0.title.localizedCaseInsensitiveContains(searchText) ||
            $0.body.localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        NavigationStack {
            List(filtered) { memory in
                let isMember = memory.collections.contains { $0.id == collection.id }
                Button {
                    toggle(memory)
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(memory.title).lineLimit(1).foregroundStyle(.primary)
                            Text(memory.body)
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
        } else {
            memory.collections.append(collection)
        }
        try? memory.modelContext?.save()
    }
}

struct NewCollectionSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @State private var name = ""
    @State private var details = ""
    @State private var aspects: [Aspect] = []
    @State private var newAspectKind: Aspect.Kind = .topic
    @State private var newAspectValue = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("Collection") {
                    TextField("Name", text: $name)
                    TextField("Description (optional)", text: $details)
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
            .navigationTitle("New Collection")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") {
                        let collection = MemoryCollection(name: name, details: details, aspects: aspects)
                        context.insert(collection)
                        try? context.save()
                        dismiss()
                    }
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }
}
