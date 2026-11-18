# Testing Context Vault with Siri AI

This is the procedure for the one test that matters most: a person asks Siri a general question, without naming the app, and Siri answers from the vault.

> "When should I expect my Amazon package with Twelve Kingdoms to arrive?"

Apple's documentation does not settle whether that works while the app is in the background (see [The open question](#the-open-question)). The steps below find out, and the result decides how the product is described.

## What you need

| Requirement | Detail |
|---|---|
| Mac | Xcode 27.3 beta, [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`) |
| iPhone | A model that supports Apple Intelligence, on iOS 27.3 beta, with Siri AI turned on |
| Language and region | A language Siri AI supports (English, French, Japanese, Korean, Portuguese, Spanish). Not available in the EU on iPhone or iPad |
| Build | Signed with a development profile and run from Xcode, or distributed to **internal** TestFlight testers. The preview does not work for external testers or App Store builds |
| Device settings | Developer Mode on. For the evaluation suite: Settings > Developer > Enable UI Automation |

Simulator is not enough. Spotlight indexing behaves differently there and Siri evaluations do not run in it.

## 1. Build

```bash
xcodegen generate
```

```bash
open ContextVault.xcodeproj
```

Select your team for the `ContextVault`, `ContextVaultTests` and `ContextVaultSiriEvals` targets, choose your iPhone and run.

### Expect compile errors on the first build

This code was written from Apple's documentation without access to Xcode. It has never been compiled against the iOS 27.3 SDK. The parts that do not depend on Apple frameworks were compiled and tested on Linux (see [What has been verified](#what-has-been-verified)); everything else has not. The likeliest places to need small fixes:

| File | Why |
|---|---|
| `ContextVault/Intents/ContextCardEntity+Presentation.swift` | `SnippetRepresentableEntity`, `CardSnippet` and `CardSnippetFamily` are new in 27.3. The protocol's return type is `some Snippet` in Apple's sample and `some EntitySnippetContent<Self>` in one reference page |
| `ContextVault/Intents/LookUpContextIntent.swift`, `RefreshSourcesIntent.swift`, `CaptureMemoryIntent.swift` | `@AppIntent(.tool)` is new in 27.3 |
| `ContextVault/Intents/OpenIntents.swift` | `@AppIntent(schema: .system.open)` and `.system.searchInApp` generate members; the macro may want the parameters declared differently |
| `ContextVault/Intents/ContextCardEntity.swift`, `SourceEntity.swift` | `@Property(title:description:authenticationPolicy:indexingKey:)` argument order |
| `ContextVault/Knowledge/ModelCardExtractor.swift` | `@Generable` with an enum case and many `@Guide` fields |
| `ContextVaultSiriEvals/*.swift` | The whole Siri Evaluations API is beta. Metric names used: `foundEntitiesAllPass`, `siriResponseAllPass`, `intentsAllPass` |
| `ContextVault/Sync/SyncManager.swift`, `Knowledge/CardPipeline.swift` | Swift concurrency checks around `MainActor.run` |

### The skills bundle

The app skill lives at `ContextVault/Skills.skillsbundle/Skills/personal-context-lookup/SKILL.md`. `project.yml` adds the bundle as a single resource. If Xcode does not treat it as a skills bundle (no validation at build time, or the evaluation report shows the skill never loads):

1. Remove the `Skills.skillsbundle` reference from the project.
2. Choose File > New > File from Template, pick **Skills Bundle** under Resource, keep the name `Skills`, and add it to the `ContextVault` target.
3. Copy the `personal-context-lookup` folder into the new bundle's `Skills` folder.

An app target can hold only one skills bundle, and a bundle with errors silently provides no skills.

## 2. Seed fictional data

In the app: **Sources** tab > **Privacy** (top left) > **Siri Lab** > **Seed demo cards**.

This creates fourteen fictional cards: orders, a flight, a hotel stay, an appointment, reservations, bills and two documents. One is the target order, due three days after you seed. One, a Wi-Fi password, is marked sensitive and must never reach Siri.

The data is fictional on purpose. If Siri answers correctly, the answer can only have come from this vault, because the information exists nowhere else on the phone.

Then check the index:

- In Siri Lab, **Cards in the system index** should read 13 (all but the sensitive one).
- Tap **Check the index for "Twelve Kingdoms"**. It should report at least one matching entry.
- Swipe down on the Home Screen and search Spotlight for `Twelve Kingdoms`. The card should appear, and tapping it should open that card in the app.

If Spotlight shows nothing, wait a minute and try again; indexing is asynchronous. To start the index from scratch, use Settings > Developer > CoreSpotlight Testing.

## 3. Ask Siri

Close Context Vault (swipe it away) before the first group. Ask each question by voice and by typing to Siri.

### The test matrix

Run every row under both indexing methods (Siri Lab > **Indexing method**), since Apple documents two and does not say which Siri finds more reliably.

| Group | App state | Example | What a pass looks like |
|---|---|---|---|
| App not named | Closed | "When should I expect my Amazon package with Twelve Kingdoms to arrive?" | Siri gives the delivery day |
| App not named | Open, in front | Same question | Siri gives the delivery day |
| Source named | Closed | "Check my Gmail: when does my Twelve Kingdoms order arrive?" | Siri gives the delivery day |
| App named | Closed | "In Context Vault, when does my Twelve Kingdoms order arrive?" | Siri gives the delivery day |
| Privacy | Any | "What's the Wi-Fi password for the cabin?" | Siri does **not** know |

The full list of phrases is in Siri Lab. Try your own wording too.

Record, for each row and each indexing method: answered correctly, answered wrongly, or did not use the vault.

## 4. Run the evaluation suite

The `ContextVaultSiriEvals` scheme runs the same matrix through Siri automatically and records what Siri did: which entities it found, which intents it called, which skill it loaded and what it replied.

1. Connect and unlock the test iPhone and select it as the run destination.
2. Select the **ContextVaultSiriEvals** scheme and choose Product > Test.
3. Open the Report navigator, select the test run, then **Evaluations**.

| Test | Measures |
|---|---|
| `unpromptedInBackground` | The primary use case. Share of scenarios where Siri found the right card |
| `unpromptedInForeground` | The same questions with the app open |
| `sourceNamedInBackground` | Naming a source in place of the app |
| `appNamedInBackground` | The documented baseline. Siri should call the lookup tool every time |

Siri's behaviour varies between runs. Run the suite at least three times and compare the numbers, not single passes. A dedicated test device gives cleaner results; a phone with few apps scores higher than a real one will.

The reply checks look for one thing the answer has to contain, such as the weekday of the delivery. A reply worded differently ("November 21" in place of "Friday") fails that check while still being correct. Treat `foundEntitiesAllPass` as the primary measure and read the replies in the report.

## 5. What the result means

| Result for requests that do not name the app, with the app closed | What to do |
|---|---|
| Siri finds the card and answers | The design holds as built. Move on to real Gmail (step 6) |
| Only when a source is named, or the app is open | Lean on source names. Product copy teaches "in my Gmail". Tune the skill and the source entity |
| Only when the app is named | The index is not consulted for background apps. Keep the pipeline, shorten the spoken app name, rely on the tools and skill, and repeat this test on each new beta |
| Never, even when the app is named | A defect on our side. Start with the `appNamedInBackground` report: it shows whether Siri chose the lookup tool and what it passed |

## 6. Repeat with real mail

1. Sources > **Gmail** > sign in > keep **Orders, bookings and bills**.
2. Wait for the first sync. Cards appear under **What Siri knows** on Home.
3. Remove the demo cards in Siri Lab, so the two sets do not mix.
4. Ask about a real order or booking.

If your Gmail account is also added to Apple Mail on the same phone, Siri may answer from Mail without the vault. Use an account that is not in Apple Mail to be sure where an answer came from.

## The open question

Apple's pages do not agree on whether an unnamed request reaches a background app:

| Source | Statement |
|---|---|
| [Siri AI Developer Preview](https://developer.apple.com/documentation/appintents/siri-ai-developer-preview) | "While your app is in the background, requests need to mention your app." |
| [`ToolIntent`](https://developer.apple.com/documentation/appintents/toolintent) | Siri can call a tool when "a relevant entity from that app appears in a search result" |
| [Developer news, 3 Nov 2026](https://developer.apple.com/news/?id=gdk2umrf) | Siri AI "can now surface any entity in the Spotlight semantic index" |
| [Evaluating your app's integration with Siri](https://developer.apple.com/documentation/sirievaluations/evaluating-your-apps-integration-with-siri) | "To make sure Siri sends the request to your app instead of another app, include your app's name in the request." |

The app is built for the reading in which Siri's own search finds an indexed entity. This test is how that reading is confirmed or ruled out.

## What has been verified

| Part | Status |
|---|---|
| Card rendering, merging, search ranking, structured-data extraction, Gmail message parsing | Compiled and unit-tested on Linux with Swift 6.2.1: 55 tests pass (`ContextVaultTests/Card*Tests.swift`, `SchemaOrgExtractorTests.swift`, `GmailMessageParserTests.swift`). Deliberately breaking the renderer, the ranking and the merge rule each made tests fail |
| Every Swift file in the repository | Parses without syntax errors. This checks syntax only, not types |
| Everything using SwiftData, App Intents, Core Spotlight, Foundation Models, SwiftUI | Written from documentation, never type-checked or run |
| Gmail API calls | Never run against Gmail. The search categories `category:purchases` and `category:reservations` are used through the API on the assumption that they work as in the Gmail search box |
| Siri behaviour | Not tested. That is what this document is for |

## Known limits

- **Freshness.** iOS decides when background work runs. Mail is fetched when the app opens or returns to the front, when the system grants a background refresh, and for a few seconds when Siri calls the lookup tool. If Siri answers from the index without calling the tool, the answer is as old as the last sync. Every card states when it was last updated.
- **On-device model.** Cards from mail without structured markup need the Apple Intelligence model. While it is unavailable or still downloading, that mail stays queued and no card is made.
- **Google sign-in.** `gmail.readonly` and `drive.readonly` are restricted scopes. They work for accounts listed as test users while the OAuth consent screen is in Testing mode, and need Google's security assessment before public release.
- **Preview.** Apple says the App Intents API and Siri's behaviour may change during the preview, and has not yet published its usage terms.
