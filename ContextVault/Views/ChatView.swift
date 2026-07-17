import SwiftUI
import SwiftData

/// "Ask your Vault" — on-device RAG chat with citations.
struct ChatView: View {
    struct Message: Identifiable {
        let id = UUID()
        var role: Role
        var text: String
        var sourceMemoryIDs: [UUID] = []

        enum Role { case user, assistant }
    }

    @Query(sort: \MemoryCollection.name) private var collections: [MemoryCollection]
    @State private var messages: [Message] = []
    @State private var input = ""
    @State private var scopedCollectionID: UUID?
    @State private var isThinking = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 12) {
                            if messages.isEmpty {
                                ContentUnavailableView(
                                    "Ask your vault anything",
                                    systemImage: "brain.head.profile",
                                    description: Text("Answers come from your own memories, on device.")
                                )
                                .padding(.top, 80)
                            }
                            ForEach(messages) { message in
                                MessageBubble(message: message)
                                    .id(message.id)
                            }
                            if isThinking {
                                ProgressView().padding(.leading)
                            }
                        }
                        .padding()
                    }
                    .onChange(of: messages.count) {
                        if let last = messages.last {
                            withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
                        }
                    }
                }

                Divider()
                composer
            }
            .navigationTitle("Ask")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Picker("Scope", selection: $scopedCollectionID) {
                            Text("All memories").tag(UUID?.none)
                            ForEach(collections) { collection in
                                Text(collection.name).tag(UUID?.some(collection.id))
                            }
                        }
                    } label: {
                        Label("Scope", systemImage: "line.3.horizontal.decrease.circle")
                    }
                }
            }
        }
    }

    private var composer: some View {
        HStack(spacing: 8) {
            TextField("Ask about your memories…", text: $input, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .lineLimit(1...4)
                .onSubmit(send)
            Button("Send", systemImage: "arrow.up.circle.fill", action: send)
                .labelStyle(.iconOnly)
                .font(.title2)
                .disabled(input.trimmingCharacters(in: .whitespaces).isEmpty || isThinking)
        }
        .padding()
    }

    private func send() {
        let question = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !question.isEmpty, !isThinking else { return }
        input = ""
        messages.append(Message(role: .user, text: question))
        isThinking = true

        let collectionID = scopedCollectionID
        Task {
            defer { isThinking = false }
            do {
                let scoped: MemoryCollection? = collectionID.flatMap { id in
                    collections.first { $0.id == id }
                }
                let service = VaultChatService()
                let answer = try await service.ask(question, scopedTo: scoped)
                messages.append(Message(
                    role: .assistant,
                    text: answer.text,
                    sourceMemoryIDs: answer.sourceMemoryIDs
                ))
            } catch {
                messages.append(Message(role: .assistant, text: error.localizedDescription))
            }
        }
    }
}

struct MessageBubble: View {
    let message: ChatView.Message

    var body: some View {
        VStack(alignment: message.role == .user ? .trailing : .leading, spacing: 6) {
            Text(message.text)
                .padding(12)
                .background(
                    message.role == .user ? AnyShapeStyle(.tint.opacity(0.15)) : AnyShapeStyle(.quaternary),
                    in: RoundedRectangle(cornerRadius: 16)
                )

            if !message.sourceMemoryIDs.isEmpty {
                SourceCitations(memoryIDs: message.sourceMemoryIDs)
            }
        }
        .frame(maxWidth: .infinity, alignment: message.role == .user ? .trailing : .leading)
    }
}

/// Provenance chips: which memories the answer drew on.
struct SourceCitations: View {
    let memoryIDs: [UUID]
    @State private var titles: [(UUID, String)] = []

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(titles, id: \.0) { _, title in
                    Label(title, systemImage: "doc.text")
                        .font(.caption2)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(.quaternary, in: Capsule())
                        .lineLimit(1)
                }
            }
        }
        .task {
            titles = (try? await MainActor.run {
                try VaultStore.shared.memories(ids: memoryIDs).map { ($0.id, $0.title) }
            }) ?? []
        }
    }
}
