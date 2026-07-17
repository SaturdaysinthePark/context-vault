# Context Vault — Architecture, told as a first-time user's journey

One sentence: Context Vault maintains **one on-device knowledge store** (the vault) filled from external sources, then **projects it into two places** — the system index Siri/Apple Intelligence reads, and an in-app AI chat. The only network calls ever made are to sources the user connects, pulling data *in*.

## Step 1 — First open

**Seen:** onboarding — "Connect Obsidian or a Markdown folder" or start empty. Then four tabs: Vault, Collections, Ask, Sources.

**Under the hood:** `ContextVaultApp` opens the SwiftData database (a local SQLite file in the app sandbox) with four tables: `Memory`, `MemoryCollection`, `SourceAccount`, `ProfileCard`. A background sync task is registered with iOS. Nothing is stored yet; zero network.

## Step 2 — Connect a source

**Seen:** the standard iOS folder picker (Obsidian vault or any Markdown folder).

**Under the hood:** iOS issues a **security-scoped bookmark** — a durable permission token for that one folder. We store a `SourceAccount` row: type, name, the bookmark, and an empty **sync cursor**. For Obsidian there is no account, no OAuth, no API — file access is the whole integration. (Notion will differ: OAuth token in the Keychain, `last_edited_time` cursor. Google Drive: OAuth + `drive.file` scope, changes-token cursor.)

## Step 3 — Sync: the ingestion pipeline (`SyncManager` → `ObsidianConnector` → `MarkdownNormalizer`)

For each file newer than the cursor:

1. **Read** the `.md` file (skipping `.obsidian/` internals; iCloud files not yet local get a download request and are picked up next pass).
2. **Normalize** — strip YAML front matter and Markdown noise, resolve `[[wiki links]]`, extract a title (first H1, else filename).
3. **Store** as a `Memory` row keyed by `sourceRef` (e.g. `obsidian:<account>:<path>`) so re-syncs update rather than duplicate.
4. **Index** into Core Spotlight (next step).
5. Advance the cursor (newest modification time seen) — this is what makes sync incremental.

After each pass, two on-device AI steps run best-effort: **sensitivity classification** of new memories and a **profile distillation** refresh (below).

## Step 4 — The Spotlight index: the bridge to Siri (`SpotlightIndexer`)

iOS keeps a per-device search index (Core Spotlight) that, on iOS 27, doubles as the **semantic index Siri AI reads for personal context**. Apps cannot inject into Siri directly — this index is the only sanctioned channel. We write one searchable item per memory: title, text, aspect keywords, dates.

**The privacy gate lives here.** `isSiriVisible` is computed before writing: the memory's collections must allow Siri exposure (uncollected memories default to visible), AND it must not be classified `sensitive` (unless the user overrode that per-memory). Not visible → actively deleted from the index. A master kill-switch (Privacy dashboard) empties the index entirely and blocks re-population.

**`MemorySnapshot`** is pure plumbing: SwiftData models can't cross threads, and indexing runs on a background actor, so we copy the needed fields into a plain immutable struct and hand that across. A mail envelope, not a concept.

## Step 5 — Collections & aspects

A `MemoryCollection` groups memories; **aspects** (topic/person/project/timeframe/source) are stored as JSON and injected into the index as keywords, sharpening what Siri matches, and scoping chat questions ("ask my Work collection"). The per-collection **"Visible to Siri" toggle** triggers reindexing of everything in it.

## Step 6 — The About Me card (`ProfileCard`, `ProfileDistiller`)

Memories answer "what did I write?" — the card answers "who am I?", which no single memory contains. After syncs (and on demand), the on-device Foundation Model reads recent memory summaries and distills one Markdown card with four sections: who I am, current projects, how I write, preferences. Zero user effort.

- User-editable; distillation **never overwrites edits** — new drafts land as a "pending suggestion" to accept or dismiss.
- Indexed in Spotlight (`profile-about-me`) so Siri can answer identity questions.
- Prepended to **every** chat prompt: the densest, highest-value tokens in the small on-device context window.

## Step 7 — "Ask" chat: on-device RAG (`VaultChatService`)

1. **Retrieve:** search the Spotlight index for the question; load the top ~8 memories from SQLite.
2. **Budget:** pack the About Me card + memory summaries into the model's window (~4K tokens iOS 26, 8K iOS 27), tracked in characters (~4/token).
3. **Generate:** `LanguageModelSession` (Apple's ~3B on-device model) with instructions to answer *only* from the provided context.
4. **Provenance:** the answer carries the IDs of the memories used → citation chips in the UI; tap-through to sources.
5. **Two-way:** any answer can be saved back into the vault with one tap, so context reflects use.

On iOS 27, step 1 collapses into Apple's `SpotlightSearchTool` (the model retrieves for itself); the current manual path remains the iOS 26 fallback.

## Step 8 — Siri

- **Today (any Apple Intelligence device):** "Ask Context Vault…" App Shortcut runs `AskVaultIntent` — the same RAG pipeline, spoken.
- **iOS 27 Siri AI:** the user just asks Siri naturally; Siri's personal-context system finds vault content *because it's in the semantic index from Step 4*. No app invocation needed. This is the app's core bet and differentiator.

## What's stored where

| Data | Where | Leaves device? |
|---|---|---|
| Memories, collections, aspects, About Me card, sync cursors | SQLite (SwiftData), app sandbox | Never |
| Folder access grants | Security-scoped bookmarks in the same DB | Never |
| OAuth tokens (Notion/Drive, future) | iOS Keychain | Only to that provider's API |
| Siri-visible content | Core Spotlight index (OS-managed, per-device) | Never |
| AI processing | On-device Foundation Model (opt-in PCC later) | On-device by default |

## Glossary

- **Memory** — one normalized piece of knowledge (note/doc/page); the vault's atom.
- **Collection** — user-curated group of memories with aspects and a Siri-visibility toggle.
- **Aspect** — a structured lens on a collection (topic, person, project, timeframe, source).
- **About Me card** — the single auto-distilled, editable profile of the user; always-on AI context.
- **Sensitivity** — on-device classification (personal/professional/sensitive); `sensitive` auto-hides from Siri.
- **MemorySnapshot / ProfileCardSnapshot** — thread-safe copies of model data for the indexing actor.
- **Sync cursor** — per-source high-water mark making sync incremental.
- **Context Pack** — a Markdown export of selected context for use in any other AI.
