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

📐 **Planning phase.** See [`docs/PLAN.md`](docs/PLAN.md) for the full feasibility research, architecture, and phased roadmap, and [`docs/RESEARCH.md`](docs/RESEARCH.md) for the underlying platform research with citations.

## Requirements (target)

- iOS 26 minimum (Foundation Models, IndexedEntity), iOS 27 for the full Siri AI experience
- Apple Intelligence-capable device (iPhone 15 Pro or later for Siri AI features)
- Xcode 27 / Swift 6, SwiftUI, SwiftData
