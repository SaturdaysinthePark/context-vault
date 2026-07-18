# Connector setup

Both connectors sync directly from the provider to your device — Context Vault has no server. Each needs a one-time setup on the provider's side.

## Google Drive

What syncs: Google Docs (exported as text) and Markdown/plain-text files, incrementally by modification time.

One-time setup (~5 minutes):

1. Go to [console.cloud.google.com](https://console.cloud.google.com) → create a project (e.g. "Context Vault Dev").
2. **APIs & Services → Library** → search "Google Drive API" → **Enable**.
3. **APIs & Services → OAuth consent screen** → External → fill in the app name + your email → save. Under **Test users**, add your own Google account. Leave the app in **Testing** mode.
4. **APIs & Services → Credentials → Create credentials → OAuth client ID** → Application type **iOS** → bundle ID `com.saturdaysinthepark.contextvault` → Create.
5. Copy the **Client ID** (looks like `1234567890-abc123.apps.googleusercontent.com`).
6. In Context Vault: Sources → Google Drive → paste the Client ID → **Sign in with Google**.

Notes:
- The app uses the `drive.readonly` scope. In Testing mode this works immediately for your test-user account with no verification. Publishing the app later requires either Google's CASA security assessment for that scope, or switching to the `drive.file` + picker model — a decision for App Store time, not now.
- Because the consent screen is unverified, Google shows a "Google hasn't verified this app" warning during sign-in — tap **Continue**. That's expected in Testing mode.
- Tokens are stored in the iOS Keychain and refreshed automatically.

## Notion

What syncs: every page shared with your integration, converted to Markdown (headings, lists, to-dos, quotes, code, callouts; tables/media skipped for now), incrementally by last-edited time.

One-time setup (~2 minutes):

1. Go to [notion.so/my-integrations](https://www.notion.so/my-integrations) → **New integration** → name it (e.g. "Context Vault"), pick your workspace, type **Internal**.
2. Under Capabilities, **Read content** is all it needs.
3. Copy the **Internal Integration Secret** (starts with `ntn_` or `secret_`).
4. Share content with it: open a Notion page → **•••** menu → **Connections** → add your integration. Sharing a top-level page includes its sub-pages.
5. In Context Vault: Sources → Notion → paste the token → **Connect Notion**.

Notes:
- Why not "Sign in with Notion"? Public OAuth requires a client secret embedded in the app, which isn't safe to ship. The internal token is Notion's supported path for personal use, and it's actually less setup than OAuth.
- The API is rate-limited to 3 requests/second; the first sync of a large workspace takes a few minutes and later syncs only fetch what changed.
- The token is stored in the iOS Keychain. Deleting the source in the app deletes the token.

## Simulator tip

Both connectors work in the iOS Simulator — the Google sign-in sheet and Notion API calls run fine there. For Google, sign in with the same account you added as a test user.
