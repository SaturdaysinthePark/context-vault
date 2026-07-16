# Platform Research — Apple Intelligence, Siri, Spotlight & Connectors (July 2026)

Research supporting the Context Vault feasibility verdict in [`PLAN.md`](PLAN.md). All claims cited.

## 1. Timeline / platform context

- **iOS 18 (2024):** App Intents "assistant schemas" announced at WWDC24 (12 domains). Most Siri-facing schema behavior never fully activated for third parties; the iOS 18.2 onscreen-content API served mostly as a conduit to ChatGPT. ([WWDC24 "Bring your app to Siri"](https://developer.apple.com/videos/play/wwdc2024/10133/), [MacStories iOS 18.2 deep dive](https://www.macstories.net/stories/apple-intelligence-and-chatgpt-in-18-2/), [MacRumors](https://www.macrumors.com/2024/11/04/apple-onscreen-awareness-ios-18-2-api-developers/))
- **iOS 26 (Sept 2025):** Foundation Models framework ships — on-device ~3B LLM, free inference, 4,096-token context. Spotlight semantic indexing existed but was flaky in practice (see §4).
- **iOS 26.4 (spring 2026):** context-window management APIs — `SystemLanguageModel.contextSize`, `tokenCount(for:)`. ([Apple TN3193](https://developer.apple.com/documentation/technotes/tn3193-managing-the-on-device-foundation-model-s-context-window), [InfoQ](https://www.infoq.com/news/2026/03/apple-foundation-models-context/))
- **WWDC26 (June 2026) → iOS 27 (ships ~Sept 2026; public beta live since July 14, 2026):** **Siri AI** with personal context, onscreen awareness, and app actions; **App Schemas**; third-party content in the **Spotlight semantic index**; Foundation Models v2 (8K on-device context, vision, PCC 32K, `SpotlightSearchTool`). ([Apple newsroom: Siri AI](https://www.apple.com/newsroom/2026/06/apple-introduces-siri-ai-a-profoundly-more-capable-and-personal-assistant/), [TechCrunch: iOS 27 public beta](https://techcrunch.com/2026/07/14/apple-opens-its-new-siri-ai-to-everyone-with-the-ios-27-public-beta/), [MacRumors](https://www.macrumors.com/2026/06/08/ios-27-and-siri-ai-release-date/))

**Implication:** Context Vault would launch straight into the iOS 27 window where, for the first time, a third-party knowledge vault can genuinely feed Siri's personal-context answers. Documented fact (WWDC26 sessions) — but beta software; treat exact Siri behavior as unproven until GM.

## 2. How real note apps integrate today (competitive gap)

- **Notion:** no knowledge-base exposure to Siri; Shortcuts actions + "open with Siri" only; mid-migration to SwiftUI ([MacRumors](https://www.macrumors.com/2026/06/12/notion-is-migrating-to-swiftui/)). Siri workflows are community Shortcuts hacks ([example](https://matthiasfrank.de/en/voice-notes-to-notion/)).
- **Bear:** rich App Intents/Shortcuts (showcased in [WWDC25 "Develop for Shortcuts and Spotlight"](https://developer.apple.com/videos/play/wwdc2025/260/)), Spotlight indexing, x-callback-url. No native AI ([Bear forum](https://community.bear.app/t/is-apple-intelligence-siri-gemini-integration-coming/19209)).
- **Craft / Things:** strong App Intents adoption for *actions*; AI features in-app only, not Siri-exposed.
- **Key gap:** as of July 2026, **no major notes app exposes its knowledge base as answerable content to Siri.** Apple's own Notes/Mail/Messages are the only content Siri AI mines today.
- Apps shipping Foundation Models features (production viability proof): Stoic, SmartGym, Chronicling. ([Apple newsroom](https://www.apple.com/newsroom/2025/09/apples-foundation-models-framework-unlocks-new-intelligent-app-experiences/), [MacStories](https://www.macstories.net/news/apple-highlights-apps-using-its-foundation-models-framework/))

## 3. App Intents deep-dive

Core stack ([App Intents docs](https://developer.apple.com/documentation/appintents)):

- **`AppEntity`** — model content as structured entities with `DisplayRepresentation` (iOS 16/17+).
- **`IndexedEntity`** (iOS 18+) — mark searchable fields with `indexingKey` (e.g. `@Property(indexingKey: \.textContent)`), then `CSSearchableIndex(...).indexAppEntities([entity])`. Populates the **Spotlight semantic index** so Siri/Apple Intelligence match by meaning. Maintain the index on create/update/delete. ([IndexedEntity docs](https://developer.apple.com/documentation/appintents/indexedentity), [WWDC26 240](https://developer.apple.com/videos/play/wwdc2026/240/))
- **`EntityStringQuery` / `IntentValueQuery`** — fallback for data that can't be pre-indexed; iOS 27 adds structured input and **`IndexedEntityQuery`** for bulk reindexing. ([WWDC26 343](https://developer.apple.com/videos/play/wwdc2026/343/))
- **AssistantSchemas → App Schemas:** iOS 18's `@AssistantIntent/@AssistantEntity/@AssistantEnum(schema:)` macros ([domains](https://developer.apple.com/documentation/appintents/app-intent-domains), [createwithswift guide](https://www.createwithswift.com/creating-app-intents-using-assistant-schemas/)). WWDC26 rebrands/extends as **App Schemas** (`@AppEntity(schema: .messages.message)`) with build-time schema enforcement; `system.search` renamed **`system.searchInApp`** ("Show me X in [App]"). ([WWDC26 240](https://developer.apple.com/videos/play/wwdc2026/240/), [dev.to summary](https://dev.to/arshtechpro/wwdc-2026-build-intelligent-siri-experiences-with-app-schemas-102o))
- **Onscreen content** (iOS 18.2+, expanded iOS 27): `NSUserActivity` association, `.appEntityIdentifier` view annotations, `Transferable` export (`IntentValueRepresentation`) so Siri can read visible content. ([Superwall guide](https://superwall.com/blog/how-to-integrate-siri-and-apple-intelligence-into-your-app-to-query-onscreen), [WWDC26 343](https://developer.apple.com/videos/play/wwdc2026/343/))
- **New in iOS 27** ([WWDC26 343](https://developer.apple.com/videos/play/wwdc2026/343/), [WWDC26 345](https://developer.apple.com/videos/play/wwdc2026/345/)): `OwnershipProvidingEntity`, `IntentDonationManager`, `ProvidesDialog`/`ShowsSnippetView`, entity annotations on notifications, `RelevantEntities`, `SyncableEntity` (stable cross-device entity IDs), `LongRunningIntent` (>30s with Live Activity), `EntityCollection`, `@UnionValue`, `AppIntentsTesting` framework.

**Works vs. aspirational:** Shortcuts/Spotlight/widgets surfaces are mature today. Schema-based Siri conversations and semantic personal-context answers are iOS 27 beta — demoed and documented but not field-proven; iOS 18 history shows Apple can slip these. Fallback: the same intents remain useful via Shortcuts/Spotlight regardless.

## 4. Personal context & the semantic index — third-party contribution

**Yes, as of iOS 27 — documented.** Siri AI reaches third-party apps through four channels: personal-context understanding, onscreen awareness, App Actions, and the **Spotlight semantic index, which apps populate via entity schemas / IndexedEntity**: "Entity schemas contribute your content to the Spotlight semantic index for personal context understanding." ([WWDC26 240](https://developer.apple.com/videos/play/wwdc2026/240/), [Apple newsroom](https://www.apple.com/newsroom/2026/06/apple-introduces-siri-ai-a-profoundly-more-capable-and-personal-assistant/), [Apple Intelligence developer page](https://developer.apple.com/apple-intelligence/))

Caveats:

- Siri AI device floor: iPhone 15 Pro / iPhone 16+; staged late-2026 rollout. ([MacRumors iOS 27 roundup](https://www.macrumors.com/roundup/ios-27/))
- On iOS 26 betas, Spotlight *semantic* search over CSSearchableItems silently failed for some developers ("Text embedding generation timeout", "[CSUserQuery] semanticQuery failed"). Opaque and hard to debug; budget QA time. ([Apple dev forums](https://developer.apple.com/forums/thread/793867), foundational session: [WWDC24 "Support semantic search with Core Spotlight"](https://developer.apple.com/videos/play/wwdc2024/10131/))
- No API exists to inject into Apple's private semantic index of Mail/Messages/Photos — the Spotlight index is the only third-party channel.

## 5. On-device RAG

**Foundation Models framework** ([docs](https://developer.apple.com/documentation/foundationmodels), [HackerNoon guide](https://hackernoon.com/a-developers-guide-to-apples-foundation-models-framework-in-ios-26)):

- iOS 26+: on-device ~3B, 2-bit-quantized; `LanguageModelSession`, `@Generable`/`@Guide` guided generation, `Tool` protocol; 4,096-token context. iOS 26.4: `contextSize` + `tokenCount(for:)`.
- iOS 27 ([WWDC26 241](https://developer.apple.com/videos/play/wwdc2026/241/)): on-device context → **8,192 tokens**; vision; **PCC model: 32K context + reasoning levels** (no API keys, free tier then iCloud+, entitlement required); `LanguageModel` protocol with `MLXLanguageModel` + official **Anthropic and Google Swift packages**; Dynamic Profiles; Evaluations framework; `fm` CLI; Python SDK.
- **`SpotlightSearchTool`** (iOS 27, [WWDC26 246 "LLM search using Core Spotlight"](https://developer.apple.com/videos/play/wwdc2026/246/)): built-in `Tool` doing RAG over the app's own Core Spotlight index — no embeddings or vector DB. Supports `GuidanceProfile` scoping, custom `@Generable` pipeline stages, `tool.searchResults` stream. Limitation: compact-index metadata isn't model-readable — implement `CSSearchableIndexDelegate.searchableItems(forIdentifiers:)` rehydration.

**Embeddings:** `NLContextualEmbedding` (iOS 17+, BERT-class, 512-dim, 256-token window) ([docs](https://developer.apple.com/documentation/naturallanguage/nlcontextualembedding)); older `NLEmbedding`; Core ML/MLX ports (MiniLM/BGE) for higher quality. No embedding API exists for the Foundation Models' own model.

**Vector stores (maturity, July 2026):** [VecturaKit](https://github.com/rryam/VecturaKit) (312★, active, NLContextualEmbedder/MLX/HNSW/hybrid — best pure-Swift choice), [ObjectBox Swift](https://docs.objectbox.io/on-device-vector-search) (commercial-grade HNSW, most mature), [SVDB](https://github.com/Dripfarm/SVDB) (223★, prototype-grade), [sqlite-vec](https://github.com/asg017/sqlite-vec) (solid C extension, immature Swift packaging — [GRDB discussion](https://github.com/groue/GRDB.swift/discussions/1761)), Couchbase Lite ([iOS RAG blog](https://www.couchbase.com/blog/rag-app-vector-ios/)).

**Open-source examples:** Raven (~193★ local document chat on Foundation Models), aftertalk (BM25 hybrid RAG meeting memory), [rudrankriyam/Foundation-Models-Framework-Example](https://github.com/rudrankriyam/Foundation-Models-Framework-Example) (1.2k★, canonical incl. RAG), [Dimillian/FoundationChat](https://github.com/Dimillian/FoundationChat). Practitioner tip: pre-compute embeddings at build time where possible (Couchbase cut app size 98%).

## 6. Connector feasibility

- **Obsidian:** vaults are plain Markdown folders; third-party iOS apps access them via `UIDocumentPickerViewController` folder selection + security-scoped bookmarks (iCloud Drive `iCloud~md~obsidian` or On My iPhone). Proven by "Actions for Obsidian". Bookmark breaks if the folder moves; iCloud sync is eventual. ([Obsidian forum on iOS file access](https://forum.obsidian.md/t/full-file-system-access-for-the-ios-app-open-existing-vault-folder/28266), [Actions for Obsidian FAQ](https://docs.actions.work/actions-for-obsidian/faqs/), [vault-in-iCloud thread](https://forum.obsidian.md/t/iphone-syncing-via-icloud-and-folder-vault-structure/112877))
- **Notion:** REST API + OAuth 2.0 public integrations; 3 req/sec rate limit, `Retry-After` on 429; incremental sync via `last_edited_time` cursor; 2025-09 API version reorganized databases into "data sources"; webhooks (2025+) require a server — a no-backend MVP polls instead. ([Request limits](https://developers.notion.com/reference/request-limits), [OAuth/pagination guide](https://www.resumelens.org/blog/notion/notion-api-and-oauth), [integration architecture guide](https://truto.one/blog/how-to-integrate-with-the-notion-api-architecture-guide-for-b2b-saas/))
- **Google Drive:** broad scopes (`drive.readonly`) are **restricted** → paid CASA Tier 2/3 assessment; `drive.file` is non-sensitive with no verification, per-file/picker access. Use `drive.file` + picker for MVP; `files.export` for Google Docs; `changes.list` for incremental sync. ([Drive scopes guide](https://developers.google.com/workspace/drive/api/guides/api-specific-auth), [CASA overview](https://deepstrike.io/blog/google-casa-security-assessment-2025), [drive.file vs drive.readonly issue](https://github.com/Jose-cd/React-google-drive-picker/issues/79))
- **Local sources:** EventKit, Contacts, any Markdown/text folder via the same bookmark pattern, share-extension capture. Apple Notes has no public API.
- **Background sync:** `BGAppRefreshTask` (~30s, opportunistic) and `BGProcessingTask` (minutes, typically idle/charging) are best-effort — design foreground-first sync with resumable cursors; `LongRunningIntent` + Live Activity for big initial imports.
