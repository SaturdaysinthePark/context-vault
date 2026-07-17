import SwiftUI
import SwiftData

/// The "About Me" card section shown at the top of the Vault tab: a
/// distilled, editable portrait of the user built from their memories.
struct AboutMeCardSection: View {
    @Query private var cards: [ProfileCard]
    @State private var showingEditor = false

    private var card: ProfileCard? { cards.first }

    var body: some View {
        Section {
            Button {
                showingEditor = true
            } label: {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Label("About Me", systemImage: "person.crop.circle")
                            .font(.headline)
                        Spacer()
                        if card?.pendingSuggestion != nil {
                            Text("New draft")
                                .font(.caption2.bold())
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(.tint.opacity(0.15), in: Capsule())
                        }
                        if card?.siriVisible == false {
                            Image(systemName: "eye.slash").foregroundStyle(.secondary)
                        }
                    }
                    if let content = card?.content, !content.isEmpty {
                        Text(content)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(3)
                    } else {
                        Text("Builds itself from your memories after your first sync — tap to distill now.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .buttonStyle(.plain)
        }
        .sheet(isPresented: $showingEditor) {
            AboutMeEditorView()
        }
    }
}

/// Full-card editor: view/edit the markdown, accept or dismiss a pending
/// distilled draft, re-distill on demand, control Siri visibility, export.
struct AboutMeEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var card: ProfileCard?
    @State private var text = ""
    @State private var siriVisible = true
    @State private var distilling = false

    var body: some View {
        NavigationStack {
            Form {
                if let pending = card?.pendingSuggestion {
                    Section("New distilled draft") {
                        Text(pending).font(.callout).lineLimit(8)
                        HStack {
                            Button("Use draft") {
                                text = pending
                                card?.pendingSuggestion = nil
                                card?.userEdited = false
                                save()
                            }
                            .buttonStyle(.borderedProminent)
                            Button("Dismiss", role: .destructive) {
                                card?.pendingSuggestion = nil
                                save()
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                }

                Section {
                    TextEditor(text: $text)
                        .frame(minHeight: 220)
                } header: {
                    Text("Your profile (Markdown)")
                } footer: {
                    Text("This card rides along with every question you ask, and Siri can answer identity questions from it. Distillation never overwrites your edits.")
                }

                Section {
                    Toggle(isOn: $siriVisible) {
                        Label("Visible to Siri & Apple Intelligence", systemImage: "sparkles")
                    }
                    Button {
                        distilling = true
                        Task {
                            if #available(iOS 26.0, *) {
                                await ProfileDistiller().distill()
                            }
                            await load()
                            distilling = false
                        }
                    } label: {
                        if distilling {
                            HStack { ProgressView(); Text("Distilling…") }
                        } else {
                            Label("Re-distill from memories", systemImage: "wand.and.stars")
                        }
                    }
                    .disabled(distilling)

                    if !text.isEmpty {
                        ShareLink(
                            item: ContextPackExporter.renderAboutMe(text),
                            preview: SharePreview("About Me — Context Pack")
                        ) {
                            Label("Export as Context Pack", systemImage: "square.and.arrow.up")
                        }
                    }
                }

                if let date = card?.lastDistilledAt {
                    Section {
                        LabeledContent("Last distilled", value: date.formatted(.relative(presentation: .named)))
                    }
                }
            }
            .navigationTitle("About Me")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        if text != card?.content { card?.userEdited = true }
                        card?.content = text
                        save()
                        dismiss()
                    }
                }
            }
            .task { await load() }
            .onChange(of: siriVisible) {
                card?.siriVisible = siriVisible
                save()
            }
        }
    }

    @MainActor
    private func load() async {
        card = try? VaultStore.shared.aboutMeCard()
        text = card?.content ?? ""
        siriVisible = card?.siriVisible ?? true
    }

    @MainActor
    private func save() {
        try? VaultStore.shared.context.save()
        Task { try? await VaultStore.shared.reindexAboutMeCard() }
    }
}
