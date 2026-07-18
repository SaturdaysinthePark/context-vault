import SwiftUI
import SwiftData

/// Google Drive connect flow: paste the iOS OAuth Client ID (one-time setup
/// documented in docs/CONNECTORS.md), then sign in with Google via
/// ASWebAuthenticationSession. Tokens land in the Keychain.
struct GoogleDriveConnectSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @State private var clientID = ConnectorSecrets.googleClientID
    @State private var working = false
    @State private var errorMessage: String?
    /// Set once sign-in succeeds; the sheet then shows the scoping step.
    @State private var signedInTokens: GoogleTokens?
    @State private var showingFolderPicker = false

    /// True when the app ships with a baked-in client ID — the normal case.
    /// The paste field only appears for developers running without one.
    private var isConfigured: Bool { !ConnectorSecrets.googleClientID.isEmpty }

    var body: some View {
        NavigationStack {
            Form {
                if let tokens = signedInTokens {
                    scopeStep(tokens: tokens)
                } else {
                    signInStep
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage).foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("Google Drive")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .sheet(isPresented: $showingFolderPicker) {
                if let tokens = signedInTokens {
                    DriveFolderPickerView(
                        title: "Choose folders to sync",
                        loader: {
                            try await DriveFolderService.fetch(
                                tokens: tokens,
                                clientID: trimmedClientID,
                                keychainKey: nil
                            )
                        },
                        onConfirm: { folders in
                            finalize(tokens: tokens, selectedFolderIDs: folders.map(\.id))
                        }
                    )
                }
            }
        }
    }

    @ViewBuilder
    private var signInStep: some View {
        if isConfigured {
            Section {
                Label("Your Docs and text files sync directly from Google to this device. Nothing passes through any other server.", systemImage: "lock.shield")
                    .font(.callout)
            }
        } else {
            Section {
                TextField("xxxx.apps.googleusercontent.com", text: $clientID)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .font(.footnote.monospaced())
            } header: {
                Text("iOS OAuth Client ID")
            } footer: {
                Text("Developer setup: this build has no baked-in client ID. Create one per docs/CONNECTORS.md and paste it here, or set ConnectorSecrets.googleClientID.")
            }
        }

        Section {
            Button {
                signIn()
            } label: {
                if working {
                    HStack { ProgressView(); Text("Signing in…") }
                } else {
                    Label("Sign in with Google", systemImage: "person.badge.key")
                }
            }
            .disabled(working || !clientID.hasSuffix(".apps.googleusercontent.com"))
        }
    }

    private func scopeStep(tokens: GoogleTokens) -> some View {
        Section {
            Button {
                finalize(tokens: tokens, selectedFolderIDs: nil)
            } label: {
                Label("Sync everything", systemImage: "externaldrive.badge.checkmark")
            }
            Button {
                showingFolderPicker = true
            } label: {
                Label("Choose folders…", systemImage: "folder.badge.gearshape")
            }
        } header: {
            Text("What should sync?")
        } footer: {
            Text("You're signed in. Sync your whole Drive, or pick specific folders (subfolders included). You can change this anytime from the source's settings.")
        }
    }

    private var trimmedClientID: String {
        clientID.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func signIn() {
        working = true
        errorMessage = nil

        Task { @MainActor in
            defer { working = false }
            do {
                signedInTokens = try await GoogleDriveAuth().signIn(clientID: trimmedClientID)
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func finalize(tokens: GoogleTokens, selectedFolderIDs: [String]?) {
        let config = GoogleDriveConfig(clientID: trimmedClientID, selectedFolderIDs: selectedFolderIDs)
        let account = SourceAccount(
            sourceType: .googleDrive,
            displayName: "Google Drive",
            configData: try? JSONEncoder().encode(config)
        )
        KeychainStore.save(tokens, for: account.keychainKey)
        context.insert(account)
        try? context.save()

        dismiss()
        Task { await SyncManager.shared.syncAll() }
    }
}

/// Notion connect flow: paste an internal-integration token (created free at
/// notion.so/my-integrations), validated against the API, stored in Keychain.
struct NotionConnectSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @State private var token = ""
    @State private var working = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    SecureField("ntn_… or secret_…", text: $token)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                } header: {
                    Text("Internal integration token")
                } footer: {
                    Text("Create a free internal integration at notion.so/my-integrations, copy its secret, and share the pages you want synced with the integration (page ••• menu → Connections). Steps in docs/CONNECTORS.md.")
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage).foregroundStyle(.red)
                    }
                }

                Section {
                    Button {
                        connect()
                    } label: {
                        if working {
                            HStack { ProgressView(); Text("Validating…") }
                        } else {
                            Label("Connect Notion", systemImage: "link")
                        }
                    }
                    .disabled(working || token.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .navigationTitle("Notion")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    private func connect() {
        working = true
        errorMessage = nil
        let trimmedToken = token.trimmingCharacters(in: .whitespacesAndNewlines)

        Task { @MainActor in
            defer { working = false }
            do {
                let botName = try await NotionConnector.validate(token: trimmedToken)

                let account = SourceAccount(
                    sourceType: .notion,
                    displayName: "Notion (\(botName))"
                )
                KeychainStore.save(NotionConnector.NotionToken(token: trimmedToken), for: account.keychainKey)
                context.insert(account)
                try context.save()

                dismiss()
                Task { await SyncManager.shared.syncAll() }
            } catch {
                errorMessage = "Couldn't validate that token — check it and make sure pages are shared with the integration."
            }
        }
    }
}
