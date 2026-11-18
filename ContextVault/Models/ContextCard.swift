import Foundation
import SwiftData

/// One short, typed, current fact distilled from evidence — the unit Siri
/// finds. An order, a delivery, a reservation, an appointment, a bill, or
/// the summary of a document.
///
/// Why cards exist: Siri AI answers from the entities an app puts in the
/// Spotlight semantic index, and what it sees of an entity is the set of
/// properties the app indexes. A raw email is a poor answer to "when does
/// my package arrive?"; a card whose `statement` already says so is a good
/// one. Later evidence about the same thing (shipped → out for delivery →
/// delivered) updates the same card through its `mergeKey` instead of
/// adding more.
@Model
final class ContextCard {
    @Attribute(.unique) var id: UUID
    var kindRaw: String
    /// Short name of the thing: "Amazon order: The Twelve Kingdoms".
    var title: String
    /// One self-contained sentence that answers the likely question, with
    /// absolute dates. Rendered by `CardRenderer`; never hand-edited.
    var statement: String
    /// A few "Label: value" lines with the supporting facts.
    var detail: String
    /// JSON-encoded `[String: String]` of structured facts (see `CardFact`).
    var attributesData: Data?
    /// JSON-encoded `CardDraft`: the structured facts this card was rendered
    /// from. Kept so later evidence can be merged in and the text re-rendered.
    var draftData: Data?
    /// Other words a person might use for this card (item names, merchant
    /// nicknames). They go into the index as keywords.
    var aliases: [String]
    /// The date a person is most likely asking about: expected delivery,
    /// departure, appointment time, due date.
    var primaryDate: Date?
    /// Whether `primaryDate` carries a meaningful time of day.
    var primaryDateHasTime: Bool
    var endDate: Date?
    /// Human-readable state: "Shipped", "Out for delivery", "Confirmed".
    var status: String?
    /// Stable identity across pieces of evidence, e.g.
    /// "order:amazon:113-5550142-9917034". Cards with the same key merge.
    var mergeKey: String?
    var sourceTypeRaw: String
    var sourceAccountID: UUID?
    /// Who the evidence came from: merchant, airline, clinic, sender.
    var counterpart: String?
    /// IDs of the memories this card was distilled from (provenance).
    var evidenceIDs: [UUID]
    /// When the newest evidence was produced — how current the card is.
    var asOf: Date
    var createdAt: Date
    var sensitivityRaw: String
    /// User override: expose to Siri even though classified sensitive.
    var forceSiriVisible: Bool
    /// 0…1 confidence of the extraction that produced the card.
    var confidence: Double
    /// Archived cards stay in the app but leave the system index.
    var isArchived: Bool
    /// Fictional card created by the Siri Lab for testing.
    var isDemo: Bool
    var indexedAt: Date?

    var kind: CardKind {
        get { CardKind(rawValue: kindRaw) ?? .other }
        set { kindRaw = newValue.rawValue }
    }

    var sourceType: SourceType {
        get { SourceType(rawValue: sourceTypeRaw) ?? .manual }
        set { sourceTypeRaw = newValue.rawValue }
    }

    var sensitivity: Sensitivity {
        get { Sensitivity(rawValue: sensitivityRaw) ?? .unclassified }
        set { sensitivityRaw = newValue.rawValue }
    }

    var attributes: [String: String] {
        get {
            guard let attributesData else { return [:] }
            return (try? JSONDecoder().decode([String: String].self, from: attributesData)) ?? [:]
        }
        set {
            attributesData = newValue.isEmpty ? nil : try? JSONEncoder().encode(newValue)
        }
    }

    /// The structured facts behind the rendered text, if recorded.
    var draft: CardDraft? {
        get {
            guard let draftData else { return nil }
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .secondsSince1970
            return try? decoder.decode(CardDraft.self, from: draftData)
        }
        set {
            guard let newValue else { draftData = nil; return }
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .secondsSince1970
            draftData = try? encoder.encode(newValue)
        }
    }

    /// "Amazon, via Gmail" — who it came from and through which source.
    var sourceLabel: String {
        CardRenderer.sourceLabel(counterpart: counterpart, source: sourceType)
    }

    init(
        id: UUID = UUID(),
        kind: CardKind,
        title: String,
        statement: String = "",
        detail: String = "",
        attributes: [String: String] = [:],
        aliases: [String] = [],
        primaryDate: Date? = nil,
        primaryDateHasTime: Bool = false,
        endDate: Date? = nil,
        status: String? = nil,
        mergeKey: String? = nil,
        sourceType: SourceType,
        sourceAccountID: UUID? = nil,
        counterpart: String? = nil,
        evidenceIDs: [UUID] = [],
        asOf: Date = .now,
        createdAt: Date = .now,
        confidence: Double = 1,
        isDemo: Bool = false
    ) {
        self.id = id
        self.kindRaw = kind.rawValue
        self.title = title
        self.statement = statement
        self.detail = detail
        self.attributesData = attributes.isEmpty ? nil : try? JSONEncoder().encode(attributes)
        self.aliases = aliases
        self.primaryDate = primaryDate
        self.primaryDateHasTime = primaryDateHasTime
        self.endDate = endDate
        self.status = status
        self.mergeKey = mergeKey
        self.sourceTypeRaw = sourceType.rawValue
        self.sourceAccountID = sourceAccountID
        self.counterpart = counterpart
        self.evidenceIDs = evidenceIDs
        self.asOf = asOf
        self.createdAt = createdAt
        self.sensitivityRaw = Sensitivity.unclassified.rawValue
        self.forceSiriVisible = false
        self.confidence = confidence
        self.isArchived = false
        self.isDemo = isDemo
    }
}

extension CardSnapshot {
    init(_ card: ContextCard, isSiriVisible: Bool) {
        self.id = card.id
        self.kind = card.kind
        self.title = card.title
        self.statement = card.statement
        self.detail = card.detail
        self.attributes = card.attributes
        self.aliases = card.aliases
        self.primaryDate = card.primaryDate
        self.endDate = card.endDate
        self.status = card.status
        self.sourceType = card.sourceType
        self.counterpart = card.counterpart
        self.asOf = card.asOf
        self.createdAt = card.createdAt
        self.isArchived = card.isArchived
        self.isSiriVisible = isSiriVisible
    }
}
