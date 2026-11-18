import Foundation

// Value types for context cards. Kept free of SwiftData and Apple-only
// frameworks so the knowledge layer (rendering, merging, search,
// extraction) can be compiled and unit-tested on its own.

/// What a context card is about. Kinds are deliberately few: each one maps
/// to a family of questions a person asks Siri ("when does it arrive?",
/// "what time is it?", "when is it due?").
enum CardKind: String, Codable, CaseIterable, Sendable {
    case order
    case travel
    case reservation
    case appointment
    case bill
    case document
    case note
    case other

    var displayName: String {
        switch self {
        case .order: "Order"
        case .travel: "Travel"
        case .reservation: "Reservation"
        case .appointment: "Appointment"
        case .bill: "Bill"
        case .document: "Document"
        case .note: "Note"
        case .other: "Other"
        }
    }

    var pluralName: String {
        switch self {
        case .order: "Orders & deliveries"
        case .travel: "Travel"
        case .reservation: "Reservations"
        case .appointment: "Appointments"
        case .bill: "Bills & subscriptions"
        case .document: "Documents"
        case .note: "Notes"
        case .other: "Other"
        }
    }

    var systemImage: String {
        switch self {
        case .order: "shippingbox"
        case .travel: "airplane"
        case .reservation: "ticket"
        case .appointment: "calendar"
        case .bill: "creditcard"
        case .document: "doc.text"
        case .note: "note.text"
        case .other: "square.dashed"
        }
    }

    /// Everyday words people use for this kind of thing. They are indexed
    /// as keywords so "my package" finds an order card.
    var synonyms: [String] {
        switch self {
        case .order: ["package", "parcel", "delivery", "shipment", "purchase", "arrive", "arriving", "tracking"]
        case .travel: ["flight", "trip", "hotel", "booking", "itinerary", "check-in", "boarding"]
        case .reservation: ["booking", "table", "ticket", "event", "show"]
        case .appointment: ["meeting", "visit", "checkup", "schedule"]
        case .bill: ["payment", "invoice", "subscription", "renewal", "due", "charge"]
        case .document: ["file", "doc", "paper", "agreement"]
        case .note: ["memo", "reminder"]
        case .other: []
        }
    }

    /// Kinds whose cards stop being useful once their date has passed.
    var expiresAfterDate: Bool {
        switch self {
        case .order, .travel, .reservation, .appointment, .bill: true
        case .document, .note, .other: false
        }
    }

    /// Whether a card of this kind, with these dates, has had its moment
    /// and should leave the system index. Orders linger a week after their
    /// date (people ask "did it arrive?"); other dated cards, two days.
    func isExpired(primaryDate: Date?, endDate: Date?, now: Date = .now) -> Bool {
        guard expiresAfterDate, let last = endDate ?? primaryDate else { return false }
        let graceDays: Double = self == .order ? 7 : 2
        return now.timeIntervalSince(last) > graceDays * 86_400
    }
}

/// Well-known keys for `ContextCard.attributes`. Free-form keys are allowed
/// too; these are the ones the renderer and merger understand.
enum CardFact {
    static let items = "Items"
    static let reference = "Reference"
    static let carrier = "Carrier"
    static let tracking = "Tracking number"
    static let location = "Location"
    static let amount = "Amount"
    static let dateLabel = "Date label"
    static let summary = "Summary"
}

/// A Sendable copy of a card for crossing actors (indexing, App Intents) —
/// SwiftData models must stay on their own context. It also carries the
/// one decision that needs the rest of the store: whether Siri may see it.
struct CardSnapshot: Sendable, Identifiable, Equatable {
    var id: UUID
    var kind: CardKind
    var title: String
    var statement: String
    var detail: String
    var attributes: [String: String]
    var aliases: [String]
    var primaryDate: Date?
    var endDate: Date?
    var status: String?
    var sourceType: SourceType
    var counterpart: String?
    var asOf: Date
    var createdAt: Date
    var isArchived: Bool
    var isSiriVisible: Bool

    var sourceLabel: String {
        CardRenderer.sourceLabel(counterpart: counterpart, source: sourceType)
    }

    /// Identifier used when the card is indexed as a plain searchable item.
    var itemIdentifier: String { "card-\(id.uuidString)" }

    /// Words that help the semantic and lexical index match this card.
    var keywords: [String] {
        var words = aliases
        words.append(kind.displayName)
        words.append(contentsOf: kind.synonyms)
        words.append(sourceType.displayName)
        if let counterpart { words.append(counterpart) }
        if let status { words.append(status) }
        if let items = attributes[CardFact.items] { words.append(items) }
        var seen = Set<String>()
        return words.filter { !$0.isEmpty && seen.insert($0.lowercased()).inserted }
    }

    /// Spotlight ranking hint: things that are about to happen outrank
    /// things that are far off or already past.
    func indexPriority(now: Date = .now) -> Int {
        guard let primaryDate else { return 1 }
        let days = primaryDate.timeIntervalSince(now) / 86_400
        if days >= -1 && days <= 14 { return 10 }
        if days > 14 { return 5 }
        return 1
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
        endDate: Date? = nil,
        status: String? = nil,
        sourceType: SourceType,
        counterpart: String? = nil,
        asOf: Date = .now,
        createdAt: Date = .now,
        isArchived: Bool = false,
        isSiriVisible: Bool = true
    ) {
        self.id = id
        self.kind = kind
        self.title = title
        self.statement = statement
        self.detail = detail
        self.attributes = attributes
        self.aliases = aliases
        self.primaryDate = primaryDate
        self.endDate = endDate
        self.status = status
        self.sourceType = sourceType
        self.counterpart = counterpart
        self.asOf = asOf
        self.createdAt = createdAt
        self.isArchived = isArchived
        self.isSiriVisible = isSiriVisible
    }
}
