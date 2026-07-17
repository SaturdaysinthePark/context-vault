# Context Vault

**A personal memory & context vault for iOS 27 — make Apple Intelligence *your* intelligence.**

Context Vault connects to the places your knowledge already lives (Obsidian, Notion, Google Drive, and more), catalogs it into **memories** organized in **collections**, and exposes it — on your terms — to Apple Intelligence and Siri. When you ask Siri a question, it can draw on your vault: your notes, your research, your project docs, your highlights. Because the vault syncs from external sources that keep growing, your on-phone AI keeps getting smarter.

## Why now

iOS 27 is the first iOS release where this is genuinely possible:

- **Siri AI** (iOS 27) answers from personal context, and third-party apps can contribute content to the Spotlight **semantic index** via App Intents entity schemas (`IndexedEntity` / App Schemas). That index is the sanctioned channel into Siri's personal-context understanding.
- **Foundation Models framework v2** provides a free on-device LLM (8K context) plus a Private Cloud Compute model (32K context) — with tool calling, guided generation, and the new **`SpotlightSearchTool`** that performs retrieval-augmented answers over the app's own Spotlight index with zero embedding infrastructure.
- No major notes or PKM app currently exposes its knowledge base as answerable Siri content. The lane is empty.

## Core concepts

| Concept | What it is |
|---|---|
| **Memory** | A normalized piece of knowledge (note, doc, page, highlight) synced from a source or captured directly |
| **Collection** | A user-curated grouping of memories with **aspects** — topic, people, projects, timeframes, source filters |
| **Aspects** | Structured lenses on a collection that sharpen retrieval and scope questions ("ask my Work collection") |
| **Siri visibility** | Per-collection control over exactly which memories the system AI can see |

## Product pillars

1. **Connectors** — Obsidian (vault folder access), Notion (OAuth API), Google Drive (`drive.file` scope), plus free local sources: calendar, contacts, any Markdown folder, share-extension capture.
2. **In-app "Ask your Vault"** — on-device RAG chat with citations back to source memories.
3. **System-level Siri answers** — vault content in the Spotlight semantic index; App Schemas; "Show me X in Context Vault."
4. **Privacy-first** — local-first storage, on-device inference, granular per-collection AI exposure. Your data never touches our servers (there are none).

## Status

🚧 **Phase 1–2 scaffold in place** — data models, ingestion pipeline, Spotlight/Siri indexing, App Intents, on-device chat, and the Obsidian/Markdown-folder connector. See [`docs/PLAN.md`](docs/PLAN.md) for the roadmap and [`docs/RESEARCH.md`](docs/RESEARCH.md) for the platform research with citations.

## Building

The repo uses [XcodeGen](https://github.com/yonaskolb/XcodeGen) to keep the project file out of git:

```sh
brew install xcodegen
xcodegen generate
open ContextVault.xcodeproj
```

Build and run on an Apple Intelligence-capable device or simulator (Xcode 26+; Xcode 27 beta for the `SpotlightSearchTool` path). If you prefer not to use XcodeGen, create a new iOS App project in Xcode named `ContextVault` and drag the `ContextVault/` source folder in.

### Project layout

```
ContextVault/
  App/         entry point + root tab view
  Models/      SwiftData: Memory, MemoryCollection (aspects, Siri toggle), SourceAccount
  Store/       VaultStore — main-actor gateway used by intents/sync/indexing
  Ingestion/   MarkdownNormalizer + Chunker (token-budget-aware)
  Indexing/    SpotlightIndexer — the semantic-index bridge to Siri (privacy-filtered)
  AI/          VaultChatService — Foundation Models RAG (iOS 27 SpotlightSearchTool path gated)
  Intents/     AppEntities (IndexedEntity), AskVaultIntent, CaptureMemoryIntent, App Shortcuts
  Connectors/  Connector protocol + ObsidianConnector (security-scoped folder sync)
  Sync/        SyncManager — foreground-first + BGProcessingTask top-ups
  Views/       Vault, Collections, Ask (chat with citations), Sources
ContextVaultTests/  Chunker + normalizer unit tests (Swift Testing)
```

## Requirements (target)

- iOS 26 minimum (Foundation Models, IndexedEntity), iOS 27 for the full Siri AI experience
- Apple Intelligence-capable device (iPhone 15 Pro or later for Siri AI features)
- Xcode 27 / Swift 6, SwiftUI, SwiftData
