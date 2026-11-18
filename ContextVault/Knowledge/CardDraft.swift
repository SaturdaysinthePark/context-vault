import Foundation

/// The structured facts pulled out of one piece of evidence, before they
/// become (or update) a `ContextCard`. Extractors produce drafts; the
/// merger decides which card a draft belongs to; the renderer turns the
/// result into the text Siri reads.
struct CardDraft: Sendable, Equatable, Codable {
    var kind: CardKind
    /// The thing itself: item names, the flight, the clinic visit, the
    /// document title. Never empty.
    var subject: String
    /// Who it is with or from: merchant, airline, clinic, biller, sender.
    var counterpart: String?
    /// Human-readable state: "Shipped", "Out for delivery", "Confirmed".
    var status: String?
    /// The date a person will ask about.
    var date: Date?
    var dateHasTime: Bool = false
    /// How to introduce the date in a sentence: "expected", "departs",
    /// "due". Nil picks a default for the kind.
    var dateLabel: String?
    var endDate: Date?
    var location: String?
    /// Money, already formatted for reading: "$84.20".
    var amount: String?
    /// Order, booking or confirmation number.
    var reference: String?
    var carrier: String?
    var tracking: String?
    /// A sentence or two of free text, mainly for documents and notes.
    var summary: String?
    var aliases: [String] = []
    /// Stable identity across evidence. Nil means "never merge".
    var mergeKey: String?
    var confidence: Double = 1

    /// Builds the conventional merge key for a kind, counterpart and
    /// reference: "order:amazon:113-5550142-9917034".
    static func makeMergeKey(kind: CardKind, counterpart: String?, reference: String?) -> String? {
        guard let reference = reference?.trimmingCharacters(in: .whitespacesAndNewlines),
              !reference.isEmpty else { return nil }
        let who = (counterpart ?? "unknown")
            .lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .joined(separator: "-")
        return "\(kind.rawValue):\(who):\(reference.lowercased())"
    }

    /// Combines two drafts about the same thing into one.
    ///
    /// The newer evidence wins wherever it says something: a "shipped"
    /// email replaces the status and delivery date from the order
    /// confirmation. Wherever the newer evidence is silent, the older
    /// facts are kept, because a shipping notice often omits what the
    /// confirmation spelled out (the items, the amount).
    ///
    /// - Parameter incomingIsNewer: whether `incoming` is more recent than
    ///   `self`. Evidence can arrive out of order, so the caller decides
    ///   by comparing evidence dates, not by arrival.
    func merging(_ incoming: CardDraft, incomingIsNewer: Bool) -> CardDraft {
        let newer = incomingIsNewer ? incoming : self
        let older = incomingIsNewer ? self : incoming

        var result = newer
        // The first-seen name of the thing is usually the most specific
        // one; a later notice may only say "your package". Keep it unless
        // the newer draft is the more confident extraction.
        if !older.subject.isEmpty, newer.confidence <= older.confidence {
            result.subject = older.subject
        }
        if newer.kind == .other { result.kind = older.kind }
        result.counterpart = newer.counterpart ?? older.counterpart
        result.status = newer.status ?? older.status
        if newer.date == nil {
            result.date = older.date
            result.dateHasTime = older.dateHasTime
            result.dateLabel = older.dateLabel
        }
        result.endDate = newer.endDate ?? older.endDate
        result.location = newer.location ?? older.location
        result.amount = newer.amount ?? older.amount
        result.reference = newer.reference ?? older.reference
        result.carrier = newer.carrier ?? older.carrier
        result.tracking = newer.tracking ?? older.tracking
        result.summary = newer.summary ?? older.summary
        result.mergeKey = newer.mergeKey ?? older.mergeKey
        result.confidence = max(newer.confidence, older.confidence)

        var seen = Set<String>()
        result.aliases = (older.aliases + newer.aliases).filter {
            !$0.isEmpty && seen.insert($0.lowercased()).inserted
        }
        return result
    }
}
