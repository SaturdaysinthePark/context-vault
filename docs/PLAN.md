# Context Vault — iOS 27 Personal AI Memory Vault: Feasibility Research & Plan

## Context

Greenfield project. Context Vault is a "personal memory / context vault" iOS app targeting iOS 27:

1. Connect to external knowledge services (Obsidian, Notion, Google Drive, …)
2. Catalog synced content into "memories" / "collections"
3. Users create collections and choose aspects
4. Apple Intelligence / Siri uses the vault's knowledge as context when answering — going beyond Apple's out-of-the-box personal context

Supporting platform research with full citations lives in [`RESEARCH.md`](RESEARCH.md).

## Feasibility verdict: YES — and the timing is unusually good

iOS 27 (WWDC June 2026, public beta live since July 14 2026, ships ~Sept 2026) is the **first iOS release where a third-party app can genuinely feed Siri's personal-context answers**:

- **Siri AI** (iOS 27): personal context, onscreen awareness, App Actions. Third-party apps contribute content to the **Spotlight semantic index** via App Intents entity schemas / `IndexedEntity` — Apple: "Entity schemas contribute your content to the Spotlight semantic index for personal context understanding" (WWDC26 session 240). This is the sanctioned (and only) path into Siri's personal context — there is no API to inject into Apple's private index of Mail/Messages/Photos.
- **Foundation Models framework v2** (iOS 27): on-device ~3B model with 8K context (4K on iOS 26), vision, guided generation (`@Generable`), tool calling; **Private Cloud Compute model with 32K context** (free tier, entitlement required); official Anthropic/Google Swift packages for frontier fallback via `LanguageModel` protocol.
- **`SpotlightSearchTool`** (iOS 27, WWDC26 session 246): built-in Foundation Models tool that does **RAG over the app's own Core Spotlight index — no embeddings/vector DB needed**. This is nearly purpose-built for Context Vault's in-app "chat with your vault".
- New iOS 27 App Intents affordances that map directly to our needs: `system.searchInApp` schema ("Show me X in Context Vault"), `SyncableEntity` (stable IDs across devices), `LongRunningIntent` (long syncs w/ Live Activity), `IndexedEntityQuery` (bulk reindex), onscreen-content annotations (`.appEntityIdentifier`, `Transferable`).
- No major notes app (Notion, Bear, Craft, …) exposes its knowledge base as answerable Siri content today — **the "knowledge source for Siri" lane is empty**.

**Risks (documented):**
- Siri AI is beta: device floor iPhone 15 Pro / 16+, staged rollout late 2026; Apple slipped comparable iOS 18-era Siri features. Mitigation: everything we build (App Intents, Spotlight index, Shortcuts) is independently useful even if Siri AI slips.
- Spotlight *semantic* indexing had silent-failure bugs in iOS 26 betas (embedding timeouts). Budget QA time; keyword Spotlight still works.
- On-device context is small (8K tokens) → chunking + token bookkeeping matter (TN3193, `contextSize` / `tokenCount(for:)` APIs).
- What Siri can answer from = what we put in the index; compact index metadata isn't model-readable → implement `CSSearchableIndexDelegate` rehydration.

## Architecture

**Local-first, privacy-first: all content and indexes on device. No backend for MVP.**

```
Connectors (Notion API / Google Drive API / Obsidian files / EventKit / …)
        │  incremental sync (BGProcessingTask + foreground)
        ▼
Ingestion pipeline: normalize → Markdown/plaintext → chunk → enrich
        │
        ├── SwiftData/SQLite store: Memory, Collection, SourceAccount, SyncState
        ├── Core Spotlight index (CSSearchableItem + IndexedEntity, indexingKey on text)
        │        ├── feeds Siri AI personal context + Spotlight semantic search  (SYSTEM surface)
        │        └── feeds SpotlightSearchTool                                   (IN-APP RAG)
        └── (v1.1) vector index: NLContextualEmbedding + VecturaKit or ObjectBox HNSW
                 └── finer-grained chunk retrieval, iOS 26 compat, hybrid BM25
        ▼
AI surfaces
  • In-app "Ask your Vault" chat: LanguageModelSession + SpotlightSearchTool (+ PCC 32K / Anthropic-Google Swift pkg fallback for long context)
  • Siri / Apple Intelligence: App Schemas + system.searchInApp + IndexedEntity semantic index
  • Shortcuts: "Ask Context Vault" intent (works on any iOS 26+ device, pre-Siri-AI fallback)
  • Widgets/watch: resurfacing, "memory of the day"
```

**Data model:**
- `Memory` — a normalized content item (note, doc, page, highlight) with source ref, chunk children, metadata
- `Collection` — user-curated grouping with **aspects** (topic tags, people, projects, time ranges, source filters); collections scope both retrieval (GuidanceProfile scoping of SpotlightSearchTool) and Siri exposure (per-collection "visible to Siri" toggle)
- `SourceAccount` — connector auth + sync cursor

## Connector feasibility (validated)

- **Obsidian — easiest, best power-user fit, do first.** Vaults are plain Markdown folders. A third-party app reads them via `UIDocumentPickerViewController` folder selection + **security-scoped bookmark** (works for iCloud Drive vaults incl. `iCloud~md~obsidian`, and On My iPhone vaults). Proven pattern: "Actions for Obsidian" does exactly this. Caveats: bookmark breaks if the vault folder moves; iCloud sync is eventual, files may need `startDownloadingUbiquitousItem` coordination. No OAuth, no rate limits, fully offline.
- **Notion — REST API + OAuth 2.0 public integration.** 3 req/sec rate limit with `Retry-After` on 429; incremental sync via `last_edited_time` cursor (search/query sorted desc, checkpoint timestamp); 2025-09 API version reorganized databases into "data sources"; webhooks exist (2025+) but a server would be needed to receive them — for a no-backend MVP, poll-on-foreground + background refresh instead. OAuth from iOS via `ASWebAuthenticationSession`; token in Keychain.
- **Google Drive — feasible but scope strategy matters.** Broad scopes (`drive.readonly`) are **restricted** and require Google's paid CASA security assessment — avoid for MVP. Use **`drive.file`** (non-sensitive, no verification) + Google Picker/document picker so users explicitly select folders/files to sync; `files.export` for Google Docs → text; `changes.list` for incremental sync. GoogleSignIn iOS SDK for OAuth.
- **Freebie local sources (no API friction):** EventKit (calendar), Contacts, HealthKit summaries, Files/iCloud Drive folders generally (same bookmark pattern as Obsidian — works for ANY markdown/text folder, e.g. Logseq, Bear backups), Safari reading list via share extension. Apple Notes has **no public API** — skip (Shortcuts-based export workaround at best).
- **Background sync reality:** `BGAppRefreshTask` (~30s, opportunistic) + `BGProcessingTask` (minutes, usually requires idle/power) are best-effort only — design sync as *foreground-first with background top-ups*, resumable cursors per source, and `LongRunningIntent` + Live Activity for big initial imports.
- **App Store policy:** data aggregation from user-authorized sources is fine; needs privacy nutrition labels, clear purpose strings, and (our differentiator) on-device processing means the privacy story is clean.

## Product ideas beyond the core (differentiators)

1. **Per-collection Siri exposure controls** — privacy story: "you decide exactly which memories the system AI can see." Power-user killer feature; Apple gives no such granularity.
2. **Aspects as retrieval lenses** — a collection isn't just a folder: aspects (people, projects, timeframes, sources) become structured metadata in the index → better semantic matching and scoped Q&A ("ask my Work collection").
3. **Memory capture inbox** — share extension + Action button intent: capture any URL/text/screenshot into the vault; auto-filed into collections by the on-device model (guided generation classification).
4. **Auto-collections** — on-device model clusters new memories into suggested collections ("Looks like a 'Home Renovation' collection is forming").
5. **Daily digest / resurfacing** — "memories relevant to today" widget using RelevantEntities + calendar context (spaced-repetition-style rediscovery).
6. **Vault timeline & provenance** — every AI answer cites which memories it used; tap-through to source (trust + debuggability).
7. **On-device summarization cascade** — summarize each doc at sync time (Foundation Models), index the summary too → better semantic recall within small context windows.
8. **Cross-device vault** — SyncableEntity + CloudKit private DB (E2E encrypted) later; entity IDs already stable.
9. **Frontier escape hatch** — long/hard questions optionally routed to PCC 32K model or user's own Anthropic/Google key via official Swift packages.
10. **Open format** — vault exportable as plain Markdown bundle; power users' trust anchor.

## Plan of work

### Phase 0 — Planning docs (this commit)
- `README.md` (vision + feasibility summary), `docs/PLAN.md` (this plan), `docs/RESEARCH.md` (platform research with citations)
- Follow-up: Xcode project scaffold (SwiftUI app, iOS 26 min target with iOS 27 feature gates, SwiftData, App Intents wiring) — project creation/build requires a Mac with Xcode 27

### Phase 1 — Vault core (no connectors yet)
- Data model (Memory/Collection/SourceAccount), manual capture (paste/share extension/files import)
- Ingestion pipeline: normalize → chunk → CSSearchableItem/IndexedEntity indexing
- Collections UI with aspects; per-collection Siri-visibility toggle

### Phase 2 — In-app AI ("Ask your Vault")
- LanguageModelSession + SpotlightSearchTool RAG chat; citations UI; token budgeting (TN3193)
- iOS 26 fallback path (manual retrieval + prompt stuffing); availability handling (unsupported devices)

### Phase 3 — Connectors
- Obsidian (folder-based, simplest, most power-user cred) → Notion (OAuth) → Google Drive
- BGProcessingTask incremental sync, LongRunningIntent + Live Activity for initial import

### Phase 4 — System integration polish
- App Schemas / system.searchInApp adoption, onscreen-content annotations, Shortcuts suite, widgets, donation via IntentDonationManager
- Test with iOS 27 beta Siri AI on device (iPhone 15 Pro+ required)

### Verification
- Unit: chunking/normalization; AppIntentsTesting framework for intents
- Device QA: Spotlight semantic search returns vault items; Siri AI answers from vault content (iOS 27 beta device); in-app chat answers with citations; sync survives background termination

## Key references
- WWDC26 240 (App Intents/semantic index), 343/345 (App Intents new), 246 (SpotlightSearchTool), 241 (Foundation Models v2)
- TN3193 context-window management; IndexedEntity docs; Apple Siri AI newsroom (June 2026); TechCrunch iOS 27 public beta (July 14 2026)
- Libraries: VecturaKit (312★, active), ObjectBox HNSW (mature), SVDB (prototype-grade); examples: rudrankriyam/Foundation-Models-Framework-Example (1.2k★), Raven, FoundationChat
