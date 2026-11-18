import Foundation
import FoundationModels

/// Distils evidence with the on-device model when there is no structured
/// markup to read. Two jobs:
///
/// - **Mail:** decide whether the message carries a personal fact worth a
///   card (an order, a booking, an appointment, a bill) and, if so, pull
///   out its parts. Most mail carries none, and the answer is then "none".
/// - **Documents:** write a short summary, which becomes the memory's
///   description in the index.
///
/// Everything runs on device. Nothing here contacts a server.
enum ModelCardExtractor {

    static var isAvailable: Bool {
        if case .available = SystemLanguageModel.default.availability { return true }
        return false
    }

    // MARK: Mail

    @Generable
    enum MailKind: String {
        case order
        case travel
        case reservation
        case appointment
        case bill
        case nothing
    }

    @Generable
    struct MailFacts {
        @Guide(description: """
            What the email is about. order: a purchase, shipment or delivery. travel: a flight, \
            train, hotel or rental car. reservation: a restaurant table, event or ticket. \
            appointment: a scheduled visit with a time. bill: a bill, invoice, payment or \
            subscription renewal. nothing: newsletters, marketing, social notifications, security \
            alerts, or anything without a personal fact worth remembering.
            """)
        var kind: MailKind

        @Guide(description: """
            The specific thing, short and without dates: the product names for an order, \
            'Flight XX 123 from A to B' for a flight, the visit for an appointment, the bill's name.
            """)
        var subject: String

        @Guide(description: "The company or person it is with or from, as a person would say it, for example Amazon. Empty if unknown.")
        var counterpart: String

        @Guide(description: "The current state in one or two words: Ordered, Shipped, Out for delivery, Delivered, Confirmed, Cancelled, Due, Paid. Empty if the email states none.")
        var status: String

        @Guide(description: """
            The single most important date, in ISO 8601: YYYY-MM-DD, or YYYY-MM-DDTHH:MM when the \
            email states a time of day. For an order it is the expected delivery date. Work out \
            relative dates such as 'tomorrow' or 'Thursday' from the date the email was sent. \
            Empty if the email states no date.
            """)
        var date: String

        @Guide(description: "A word or two that introduces that date in a sentence: expected, delivered, departs, check-in, on, due, renews. Empty if there is no date.")
        var dateLabel: String

        @Guide(description: "An end date in ISO 8601 (YYYY-MM-DD), such as a hotel check-out. Empty if none.")
        var endDate: String

        @Guide(description: "Where it takes place: an address, venue or departure airport. Empty if none.")
        var location: String

        @Guide(description: "The total amount with its currency symbol, for example $84.20. Empty if none.")
        var amount: String

        @Guide(description: "The order, booking or confirmation number exactly as written. Empty if none.")
        var reference: String

        @Guide(description: "The delivery carrier, for example UPS. Empty if none.")
        var carrier: String

        @Guide(description: "The tracking number exactly as written. Empty if none.")
        var tracking: String
    }

    /// Extracts at most one draft from a mail message. Returns nil when
    /// the message carries nothing worth a card, or the model is unsure.
    static func draft(fromMail evidence: EvidenceInput) async -> CardDraft? {
        guard isAvailable else { return nil }

        let session = LanguageModelSession(instructions: """
            You read one email at a time and record the single personal fact it carries, \
            if any: an order or delivery, a trip, a reservation, an appointment, or a bill. \
            Record only what the email states. Never invent a date, a number or a name. \
            Most emails carry no such fact; answer with kind nothing for those.
            """)

        let sent = CardRenderer.format(evidence.date, hasTime: false, locale: Locale(identifier: "en_US"))
        let prompt = """
            From: \(evidence.sender ?? "unknown")
            Sent: \(sent)
            Subject: \(evidence.title)

            \(String(evidence.body.prefix(bodyBudget)))
            """

        do {
            let response = try await session.respond(to: prompt, generating: MailFacts.self)
            return draft(from: response.content, evidence: evidence)
        } catch {
            // Best-effort: a failed extraction leaves the memory queued.
            return nil
        }
    }

    /// Characters of body text given to the model. The on-device window
    /// is small; the facts are nearly always near the top of a message.
    static let bodyBudget = 5000

    /// Turns the model's answer into a draft, discarding anything that
    /// fails a sanity check. Kept separate from the model call so the
    /// checks can be unit-tested.
    static func draft(from facts: MailFacts, evidence: EvidenceInput) -> CardDraft? {
        let kind: CardKind
        switch facts.kind {
        case .order: kind = .order
        case .travel: kind = .travel
        case .reservation: kind = .reservation
        case .appointment: kind = .appointment
        case .bill: kind = .bill
        case .nothing: return nil
        }
        guard let subject = clean(facts.subject) else { return nil }

        let counterpart = clean(facts.counterpart) ?? evidence.senderName
        var draft = CardDraft(kind: kind, subject: subject, counterpart: counterpart)
        draft.status = clean(facts.status)
        draft.location = clean(facts.location)
        draft.amount = clean(facts.amount)
        draft.reference = clean(facts.reference)
        draft.carrier = clean(facts.carrier)
        draft.tracking = clean(facts.tracking)
        draft.confidence = 0.7

        // A model can produce a well-formed date that is nonsense. Accept
        // only dates near the message: a month before to a little over a
        // year after it was sent.
        if let (date, hasTime) = SchemaOrgExtractor.parseDate(facts.date),
           plausible(date, relativeTo: evidence.date) {
            draft.date = date
            draft.dateHasTime = hasTime
            draft.dateLabel = clean(facts.dateLabel)
        }
        if let (end, _) = SchemaOrgExtractor.parseDate(facts.endDate),
           plausible(end, relativeTo: evidence.date),
           let start = draft.date, end >= start {
            draft.endDate = end
        }

        // Identity: a reference number joins evidence across threads (an
        // order confirmation and its shipping notice are separate threads
        // with the same order number). Without one, fall back to the thread.
        draft.mergeKey = CardDraft.makeMergeKey(kind: kind, counterpart: counterpart, reference: draft.reference)
            ?? evidence.threadKey.map { "thread:\($0)" }
        return draft
    }

    static func plausible(_ date: Date, relativeTo sent: Date) -> Bool {
        let days = date.timeIntervalSince(sent) / 86_400
        return days >= -30 && days <= 400
    }

    // MARK: Documents

    @Generable
    struct DocumentSummary {
        @Guide(description: """
            Two or three sentences stating what the document is and the facts someone would \
            later ask about: names, dates, amounts, decisions, terms. Plain statements, no \
            preamble such as 'This document'. Only what the text supports.
            """)
        var summary: String
    }

    /// Documents shorter than this are their own summary.
    static let minimumLengthToSummarize = 600

    /// Writes a short summary of a document. Returns nil when the document
    /// is too short to need one or the model is unavailable.
    static func summary(ofDocument evidence: EvidenceInput) async -> String? {
        guard isAvailable, evidence.body.count >= minimumLengthToSummarize else { return nil }

        let session = LanguageModelSession(instructions: """
            You summarize a person's own documents and notes so they can be found again. \
            State only what the text says. Never invent facts.
            """)
        let prompt = "Title: \(evidence.title)\n\n\(String(evidence.body.prefix(bodyBudget)))"

        do {
            let response = try await session.respond(to: prompt, generating: DocumentSummary.self)
            return clean(response.content.summary)
        } catch {
            return nil
        }
    }

    // MARK: Helpers

    private static func clean(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let placeholders: Set<String> = ["", "none", "n/a", "na", "unknown", "null", "empty", "-"]
        return placeholders.contains(trimmed.lowercased()) ? nil : trimmed
    }
}
