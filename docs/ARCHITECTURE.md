# Context Vault — Architecture

Context Vault gathers what a person's mail and documents say, distils it into short current facts, and puts those facts where Siri AI looks. The aim is that a general question, asked without naming the app, gets a correct answer:

> "When should I expect my Amazon package with Twelve Kingdoms to arrive?"

Everything is stored and processed on the device. The only network calls the app makes are to the sources the user connects, pulling data in.

## Why the design is index-first

Siri AI (iOS 27.3 Developer Preview) reaches an app in two ways:

1. **Its own search finds one of the app's entities** in the Spotlight semantic index. When it does, what Siri sees of that entity is the set of properties the app indexed.
2. **It calls one of the app's tools** — an app intent marked `@AppIntent(.tool)`. Apple documents that Siri can do this when the app is named, when it is in the foreground, or when a relevant entity from the app appears in a search result.

A request that names no app can only start from route 1. So the product is the quality of what goes into the index: each indexed entity has to be findable from an everyday question and has to carry the answer in its indexed text. Tools and the app skill are the second line, for follow-ups, named requests and freshness.

Whether route 1 works for a background app is not settled by Apple's documentation. [`SIRI_TESTING.md`](SIRI_TESTING.md) is the procedure that settles it.

## Three layers of knowledge

| Layer | Model | What it holds | Does Siri see it? |
|---|---|---|---|
| **Evidence** | `Memory` | The raw item: an email, a document, a note | Documents and notes: yes, as their own index entry. Email: never |
| **Context cards** | `ContextCard` | One short, typed, current fact distilled from evidence | Yes. This is the main thing indexed |
| **Sources** | `SourceAccount` | A connected account | Its general name only ("Gmail"), so a source can be named in a request |

A **context card** is the unit Siri finds: an order, a trip, a reservation, an appointment, a bill. It has a kind, a title, a status, a date, where it came from, and a `statement` — one sentence that answers the likely question:

> Amazon order of The Twelve Kingdoms (paperback): shipped, expected Thursday, November 19, 2026. Source: Gmail, updated Tuesday, November 17, 2026.

Two rules shape the statement. Dates are absolute, because the text sits in an index for days and "tomorrow" would be wrong when it is read. And the sentence stands alone, because it may be all Siri sees.

One real-world thing gets one card. An order confirmation, a shipping notice and a delivery notice are three pieces of evidence about one order; they update a single card through its merge key (kind, counterpart and reference number), so the card's statement is always the current answer.

## The pipeline

```
Connectors            Gmail · Google Drive · Notion · Obsidian · folders
   │                  incremental, each with its own cursor
   ▼
Evidence              Memory (SwiftData). Mail keeps its sender, thread and
   │                  any structured data found in its HTML
   ▼
Sensitivity           on-device model: personal · professional · sensitive
   │                  runs before anything derived can be indexed
   ▼
Extract               1. schema.org JSON-LD in the mail, when present (exact)
   │                  2. the on-device model with guided generation
   │                  Documents get a summary instead of a card
   ▼
Merge                 into the card with the same merge key, newest evidence wins
   ▼
Render                title, statement, detail lines, with absolute dates
   ▼
Index                 Core Spotlight, as app entities
   ▼
Siri AI               finds the entity · may call a tool · may load the skill
```

| Step | Code |
|---|---|
| Sync orchestration, freshness | `Sync/SyncManager.swift` |
| Connectors | `Connectors/GmailConnector.swift`, `GoogleDriveConnector.swift`, `NotionConnector.swift`, `ObsidianConnector.swift` |
| Mail parsing (MIME, HTML to text, JSON-LD) | `Connectors/GmailMessageParser.swift` |
| Extraction | `Knowledge/SchemaOrgExtractor.swift`, `Knowledge/ModelCardExtractor.swift` |
| Merge and expiry | `Knowledge/CardDraft.swift`, `Knowledge/CardMerger.swift` |
| Rendering | `Knowledge/CardRenderer.swift` |
| Pipeline | `Knowledge/CardPipeline.swift` |
| Index | `Indexing/SpotlightIndexer.swift` |
| Store | `Store/VaultStore.swift` |

Work is queued by `Memory.cardsExtractedAt == nil`, so an interrupted pass resumes where it stopped. When the on-device model is unavailable, mail without structured data stays queued; no low-quality card is made in its place.

## What Siri sees

**Entities** (`Intents/`)

| Entity | Indexed as | Notes |
|---|---|---|
| `ContextCardEntity` | App entity | Title, summary (the statement) and details map to index keys. Kind, source, counterpart, date, status and last-updated are described properties. Details need device unlock before Siri reads them out |
| `MemoryEntity` | Searchable item linked to the entity | Documents and notes only |
| `SourceEntity` | App entity | The source's name and spoken synonyms |

Every property has a title and a description written for a reader who has never seen the app, because that is what Siri uses to understand it.

**Tools** — intents Siri AI can call without a fixed phrase

| Tool | Does |
|---|---|
| `LookUpContextIntent` | Finds cards for a topic, optionally limited to a source or kind. Returns the cards; Siri does the reasoning |
| `RefreshSourcesIntent` | Checks fast-moving sources for new information |
| `CaptureMemoryIntent` | Saves a note |

Adding any tool removes the app's App Shortcuts from Siri (Apple's rule). They stay for Spotlight and the Action button, backed by `AskVaultIntent` and `CaptureMemoryIntent`.

**Other surfaces**

- **App skill** (`Skills.skillsbundle/Skills/personal-context-lookup/SKILL.md`): tells Siri when to consult the vault and how to answer from a card.
- **Schema intents**: `OpenCardIntent` and `OpenMemoryIntent` (`.system.open`), `SearchVaultIntent` (`.system.searchInApp`).
- **Card snippet**: the view Siri shows for a card.
- **Onscreen context**: card and memory views carry `.appEntityIdentifier`, so "this one" resolves.
- **Mentionable sources**: the `SourceKind` app enum with synonyms, the source's name in each card's indexed text, and `SourceEntity`.

**Two ways to index a card.** Apple documents `indexAppEntities` and, separately, a searchable item linked with `associateAppEntity`, and says not to use both for the same content. Which one Siri finds more reliably is not documented. `CardIndexingPath` switches between them from the Siri Lab so the two can be compared on a device.

## Freshness

iOS decides when background work runs, so "constantly updated" is not achievable on the device alone. In order of reliability:

1. **App open, or return to the foreground** — a sync of every source.
2. **Refresh on ask** — when Siri calls the lookup tool, a few seconds' top-up of mail before answering.
3. **Background app refresh** (`BGAppRefreshTask`) — a short mail top-up, when the system allows.
4. **Background processing** (`BGProcessingTask`) — a full sync when the device is idle.

If Siri answers from the index without calling the tool, the answer is as old as the last sync. Every card carries its last-updated date so Siri can say how current it is. Near-real-time updates would need a small push relay server, which the app does not have.

Cards whose date has passed are archived and leave the index: orders a week after their date, other dated cards after two days.

## Privacy

The set of things Siri can see is narrow, and every control removes from it.

- **Email is never indexed.** Only the cards distilled from it are.
- **Sensitivity** is classified on device before anything derived from a memory can be indexed. Sensitive content is held back, and a card inherits the sensitivity of its evidence.
- **Controls** (`Views/PrivacyView.swift`, settings in `Indexing/SiriExposure.swift`): a master switch that empties the index, and toggles by source, by kind of card and by collection.
- **Entity queries honour the same rules.** A hidden card or memory is not returned to the system by any route.
- **Unlock before details.** Reference and tracking numbers sit in a property Siri must authenticate to read.

What does leave the device: content the user shares with Siri is handled by Apple Intelligence under Apple's terms, which for this preview Apple has not yet published. Tokens go only to the provider they belong to.

## What is stored where

| Data | Where |
|---|---|
| Memories, cards, collections, About Me card, sync cursors | SwiftData (SQLite) in the app sandbox |
| Folder access grants | Security-scoped bookmarks in the same store |
| OAuth and API tokens | iOS Keychain |
| What Siri can see | Core Spotlight index, managed by the OS |
| Privacy settings | UserDefaults |
| Model inference | On-device Foundation Model |

## In-app features that share the store

- **Ask** (`AI/VaultChatService.swift`): on-device question answering. It retrieves matching cards first, then documents from the Spotlight index, and cites the memories it used.
- **About Me card** (`AI/ProfileDistiller.swift`): an editable profile distilled from recent memories; indexed for Siri and prepended to every chat prompt.
- **Collections** (`Models/MemoryCollection.swift`): user-curated groups of memories with aspects and a Siri toggle.
- **Context Packs** (`Export/ContextPackExporter.swift`): Markdown export of a collection for use in another assistant.
- **Siri Lab** (`Views/SiriLabView.swift`): fictional seed data, index checks and the test phrases.

## Not built yet

- **Graph layer.** People, organisations and products as their own nodes with aliases, for "everything about X" and better alias matching. Cards carry their own aliases and counterpart for now.
- **Cards from documents.** A document gets a summary on its memory, not a dated card.
- **Push relay** for near-real-time mail.
- **Adoption of `SpotlightSearchTool`** in the in-app chat.

## Glossary

- **Evidence** — a raw item from a source (`Memory`).
- **Context card** — one short, typed, current fact distilled from evidence; what Siri finds.
- **Statement** — the card's one-sentence answer, with absolute dates.
- **Merge key** — the identity that lets later evidence update the same card.
- **Counterpart** — who the evidence is from or with: merchant, airline, clinic.
- **Snapshot** — a plain copy of a model object, safe to pass between actors (`CardSnapshot`, `MemorySnapshot`, `SourceSnapshot`).
- **Sync cursor** — a per-source marker that makes sync incremental.
