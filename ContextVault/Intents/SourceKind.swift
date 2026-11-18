import AppIntents

/// The connected sources as a person names them. This is what makes a
/// source mentionable in a request ("check my Gmail", "from Google
/// Drive"): Siri can fill an intent parameter of this type from the words
/// in the request, helped by the synonyms on each case.
enum SourceKind: String, AppEnum, CaseIterable, Sendable {
    case gmail
    case googleDrive
    case notion
    case obsidian
    case files
    case notes

    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Source")

    static let caseDisplayRepresentations: [SourceKind: DisplayRepresentation] = [
        .gmail: DisplayRepresentation(
            title: "Gmail",
            subtitle: "Email",
            synonyms: ["email", "mail", "inbox", "Google Mail", "my email"]
        ),
        .googleDrive: DisplayRepresentation(
            title: "Google Drive",
            subtitle: "Documents",
            synonyms: ["Drive", "Google Docs", "my Drive"]
        ),
        .notion: DisplayRepresentation(
            title: "Notion",
            subtitle: "Pages",
            synonyms: ["Notion workspace"]
        ),
        .obsidian: DisplayRepresentation(
            title: "Obsidian",
            subtitle: "Notes",
            synonyms: ["Obsidian vault"]
        ),
        .files: DisplayRepresentation(
            title: "Files",
            subtitle: "Folders",
            synonyms: ["folder", "documents folder"]
        ),
        .notes: DisplayRepresentation(
            title: "Notes",
            subtitle: "Saved in Context Vault",
            synonyms: ["my notes", "saved notes", "things I saved"]
        )
    ]

    /// The stored source types this spoken name covers.
    var sourceTypes: Set<SourceType> {
        switch self {
        case .gmail: [.gmail]
        case .googleDrive: [.googleDrive]
        case .notion: [.notion]
        case .obsidian: [.obsidian]
        case .files: [.files]
        case .notes: [.manual, .shareExtension]
        }
    }

    init(_ sourceType: SourceType) {
        switch sourceType {
        case .gmail: self = .gmail
        case .googleDrive: self = .googleDrive
        case .notion: self = .notion
        case .obsidian: self = .obsidian
        case .files: self = .files
        case .manual, .shareExtension: self = .notes
        }
    }
}

/// Card kinds as an app enum, so Siri can read a card's kind and can
/// narrow a lookup ("my appointments", "my bills").
extension CardKind: AppEnum {
    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Kind")

    static let caseDisplayRepresentations: [CardKind: DisplayRepresentation] = [
        .order: DisplayRepresentation(
            title: "Order",
            subtitle: "Purchases and deliveries",
            synonyms: ["package", "delivery", "shipment", "parcel", "purchase"]
        ),
        .travel: DisplayRepresentation(
            title: "Travel",
            subtitle: "Flights, hotels and trips",
            synonyms: ["flight", "trip", "hotel", "itinerary"]
        ),
        .reservation: DisplayRepresentation(
            title: "Reservation",
            subtitle: "Restaurants, tickets and events",
            synonyms: ["booking", "table", "ticket", "event"]
        ),
        .appointment: DisplayRepresentation(
            title: "Appointment",
            subtitle: "Scheduled visits",
            synonyms: ["visit", "meeting", "checkup"]
        ),
        .bill: DisplayRepresentation(
            title: "Bill",
            subtitle: "Bills, payments and subscriptions",
            synonyms: ["payment", "invoice", "subscription", "renewal"]
        ),
        .document: DisplayRepresentation(
            title: "Document",
            subtitle: "Files and pages",
            synonyms: ["file", "doc", "page"]
        ),
        .note: DisplayRepresentation(
            title: "Note",
            subtitle: "Things saved by hand",
            synonyms: ["memo", "reminder"]
        ),
        .other: DisplayRepresentation(title: "Other")
    ]
}
