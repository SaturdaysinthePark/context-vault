import SwiftUI
import SwiftData

/// First-launch flow — the "90 seconds to value" arc: connect Gmail or a
/// notes folder (or skip), watch the vault build, land in the app with
/// context already working. Syncing and distilling happen on device.
struct OnboardingView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @AppStorage("hasOnboarded") private var hasOnboarded = false

    private enum Step {
        case welcome
        case building(String)
        case done(cardBuilt: Bool)
    }

    @State private var step: Step = .welcome
    @State private var showingFolderPicker = false
    @State private var showingGmailConnect = false
    @Query private var accounts: [SourceAccount]

    var body: some View {
        VStack(spacing: 24) {
            switch step {
            case .welcome:
                Spacer()
                Image(systemName: "brain.head.profile")
                    .font(.system(size: 56))
                    .foregroundStyle(.tint)
                Text("Your AI, with your context")
                    .font(.title.bold())
                    .multilineTextAlignment(.center)
                Text("Connect your mail or notes and Context Vault turns them into short facts Siri can answer from: when a package arrives, when a flight leaves, when a bill is due. Your messages and documents stay on your iPhone; you choose what Siri sees.")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal)
                Spacer()
                Button {
                    showingGmailConnect = true
                } label: {
                    Label("Connect Gmail", systemImage: "envelope.badge")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                Button {
                    showingFolderPicker = true
                } label: {
                    Label("Connect Obsidian or a Markdown folder", systemImage: "folder.badge.plus")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                Button("Start with an empty vault") {
                    finish()
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)

            case .building(let status):
                Spacer()
                ProgressView().controlSize(.large)
                Text("Building your vault")
                    .font(.title2.bold())
                Text(status)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                Spacer()

            case .done(let cardBuilt):
                Spacer()
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 56))
                    .foregroundStyle(.green)
                Text(cardBuilt ? "Your context is ready" : "Vault connected")
                    .font(.title2.bold())
                Text(cardBuilt
                    ? "Your sources are synced and your first cards are ready. Ask your vault anything — or just ask Siri, without naming this app."
                    : "Your sources are synced. Cards are distilled once Apple Intelligence is available, and more appear after each sync.")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal)
                Spacer()
                Button {
                    finish()
                } label: {
                    Text("Open my vault").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }
        }
        .padding(24)
        .interactiveDismissDisabled()
        .fileImporter(
            isPresented: $showingFolderPicker,
            allowedContentTypes: [.folder]
        ) { result in
            guard case .success(let url) = result else { return }
            connectAndBuild(url)
        }
        .sheet(isPresented: $showingGmailConnect, onDismiss: {
            // The sheet starts a sync itself when it connects an account.
            if accounts.contains(where: { $0.sourceType == .gmail }) {
                build(status: "Reading your recent mail…")
            }
        }) {
            GmailConnectSheet()
        }
    }

    private func connectAndBuild(_ url: URL) {
        guard url.startAccessingSecurityScopedResource() else { return }
        defer { url.stopAccessingSecurityScopedResource() }

        do {
            let bookmark = try url.bookmarkData(
                options: [],
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
            let account = SourceAccount(
                sourceType: .obsidian,
                displayName: url.lastPathComponent,
                configData: bookmark
            )
            context.insert(account)
            try context.save()
        } catch {
            return
        }

        build(status: "Reading your notes…")
    }

    /// Runs a sync and the first distilling pass, then reports whether
    /// any context cards (or the About Me card) came out of it.
    private func build(status: String) {
        step = .building(status)
        Task { @MainActor in
            // A sync also runs the distilling pass that produces cards.
            await SyncManager.shared.syncAll()
            step = .building("Distilling your About Me card…")
            let profileBuilt = await ProfileDistiller().distill()
            let cards = (try? VaultStore.shared.cards(includeArchived: false)) ?? []
            step = .done(cardBuilt: !cards.isEmpty || profileBuilt)
        }
    }

    private func finish() {
        hasOnboarded = true
        dismiss()
    }
}
