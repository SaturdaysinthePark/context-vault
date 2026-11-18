# Context Vault

**A personal memory & context vault for iOS 27 — make Apple Intelligence *your* intelligence.**

Context Vault connects to the places your information already lives (Gmail, Google Drive, Notion, Obsidian), distils it into short current facts called **context cards**, and puts them where Siri AI looks. The aim: you ask Siri a general question, without naming this app, and it answers from your vault.

> "When should I expect my Amazon package with Twelve Kingdoms to arrive?"

Whether Siri does that for an app in the background is not settled by Apple's documentation. [`docs/SIRI_TESTING.md`](docs/SIRI_TESTING.md) is the test that settles it.

## Why now

iOS 27 is the first iOS release where this is genuinely possible:

- **Siri AI** (iOS 27) answers from personal context, and third-party apps can contribute content to the Spotlight **semantic index** via App Intents entity schemas (`IndexedEntity` / App Schemas). That index is the sanctioned channel into Siri's personal-context understanding.
- **Foundation Models framework v2** provides a free on-device LLM (8K context) plus a Private Cloud Compute model (32K context) — with tool calling, guided generation, and the new **`SpotlightSearchTool`** that performs retrieval-augmented answers over the app's own Spotlight index with zero embedding infrastructure.
- No major notes or PKM app currently exposes its knowledge base as answerable Siri content. The lane is empty.

## Core concepts

| Concept | What it is |
|---|---|
| **Context card** | One short, typed, current fact distilled from your sources: an order, a trip, a reservation, an appointment, a bill. The unit Siri finds |
| **Memory** | The raw evidence a card comes from: an email, a document, a note. Synced from a source or captured directly |
| **Collection** | A user-curated grouping of memories with **aspects** — topic, people, projects, timeframes, source filters |
| **Aspects** | Structured lenses on a collection that sharpen retrieval and scope questions ("ask my Work collection") |
| **Siri visibility** | Control over exactly what the system AI can see: by source, by kind of card, by collection, plus a master switch |

## Product pillars

1. **Connectors** — Gmail (read-only, narrow by default), Google Drive, Notion, Obsidian and any Markdown folder.
2. **About Me card** — an auto-distilled, editable portrait of the user built by the on-device model from their memories; always-on context that answers "who am I?", not just "what did I write?"
3. **In-app "Ask your Vault"** — on-device RAG chat with citations back to source memories, and one-tap save of answers back into the vault.
4. **System-level Siri answers** — context cards indexed as app entities in the Spotlight semantic index; tools Siri AI can call; an app skill; sources you can name in a request ("in my Gmail").
5. **Privacy-first** — local storage, on-device distilling, sensitivity auto-tagging, and a privacy dashboard. Email is never shared with Siri, only the cards made from it. There are no Context Vault servers. Content you choose to share with Siri is handled by Apple Intelligence under Apple's terms.
6. **Context Packs** — export any collection (plus your About Me card) as Markdown for use in ChatGPT, Claude, or any other AI. One vault, every AI.

## Status

🚧 **Redesigned for the Siri AI Developer Preview (iOS 27.3 beta), November 2026. Not yet built in Xcode.**

- The logic that does not depend on Apple frameworks (card rendering, merging, search, structured-data extraction, Gmail parsing) is compiled and covered by 55 passing unit tests.
- Everything that uses SwiftData, App Intents, Core Spotlight, Foundation Models or SwiftUI was written from Apple's documentation and has never been compiled. Expect fixes on the first build.
- Siri's behaviour is untested. That is the next step.

See [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md) for the design, [`docs/SIRI_TESTING.md`](docs/SIRI_TESTING.md) for the device test, [`docs/PLAN.md`](docs/PLAN.md) for the roadmap and [`docs/RESEARCH.md`](docs/RESEARCH.md) for the platform research.

## Building

The repo uses [XcodeGen](https://github.com/yonaskolb/XcodeGen) to keep the project file out of git:

```sh
brew install xcodegen
xcodegen generate
open ContextVault.xcodeproj
```

Build with Xcode 27.3 beta and run on an Apple Intelligence iPhone on iOS 27.3 beta. Siri AI and Spotlight indexing need a physical device. Full steps, including the skills bundle, are in [`docs/SIRI_TESTING.md`](docs/SIRI_TESTING.md).

### Project layout

```
ContextVault/
  App/         entry point, root tab view, navigation from Siri and Spotlight
  Models/      SwiftData: Memory, ContextCard, MemoryCollection, SourceAccount; plain card types
  Store/       VaultStore — main-actor gateway used by intents, sync and indexing
  Connectors/  Gmail, Google Drive, Notion, Obsidian and folders
  Sync/        SyncManager — sync, background refresh, refresh when Siri asks
  Ingestion/   Markdown, PDF, document and image text extraction
  Knowledge/   evidence to cards: extract, merge, render, search, pipeline, demo data
  Indexing/    SpotlightIndexer and the Siri exposure settings
  Intents/     entities, tools, open and search intents, card snippet
  AI/          on-device chat, About Me distiller, sensitivity classifier
  Skills.skillsbundle/  the app skill Siri AI loads
  Views/       Home, cards, collections, Ask, sources, privacy, Siri Lab
ContextVaultTests/      unit tests (Swift Testing)
ContextVaultSiriEvals/  Siri Evaluations, run on a device
```

## Requirements

- iOS 27.3 beta during the Siri AI Developer Preview
- An Apple Intelligence iPhone, set to a language Siri AI supports; not available in the EU on iPhone and iPad
- Xcode 27.3 beta, SwiftUI, SwiftData
