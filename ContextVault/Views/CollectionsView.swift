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
                }
            }
        }
        .navigationTitle(collection.name)
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
