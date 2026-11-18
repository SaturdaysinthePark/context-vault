import Foundation

/// Decides which card a draft belongs to, and keeps cards current.
///
/// One real-world thing gets one card. An order confirmation, a shipping
/// notice and a delivery notice are three pieces of evidence about one
/// order, so they update a single card rather than producing three. That
/// is what lets the card's statement be *the* current answer.
@MainActor
enum CardMerger {

    /// Creates a new card from a draft. Does not insert or save it.
    static func makeCard(
        from draft: CardDraft,
        source: SourceType,
        sourceAccountID: UUID? = nil,
        evidenceID: UUID? = nil,
        asOf: Date
    ) -> ContextCard {
        let card = ContextCard(
            kind: draft.kind,
            title: draft.subject,
            sourceType: source,
            sourceAccountID: sourceAccountID,
            evidenceIDs: evidenceID.map { [$0] } ?? [],
            asOf: asOf
        )
        write(draft, to: card, asOf: asOf)
        return card
    }

    /// Merges a draft into an existing card and re-renders its text.
    static func update(_ card: ContextCard, with draft: CardDraft, evidenceID: UUID?, asOf: Date) {
        let incomingIsNewer = asOf >= card.asOf
        let merged = card.draft?.merging(draft, incomingIsNewer: incomingIsNewer) ?? draft
        if let evidenceID, !card.evidenceIDs.contains(evidenceID) {
            card.evidenceIDs.append(evidenceID)
        }
        write(merged, to: card, asOf: max(asOf, card.asOf))
        // Fresh evidence about a card brings it back if it was archived.
        if incomingIsNewer, !isExpired(card) {
            card.isArchived = false
        }
    }

    /// Finds the card a draft belongs to and updates it, or creates one.
    /// The card is inserted into the store's context but not saved or
    /// indexed; the caller batches those.
    ///
    /// Matching order: the draft's merge key (the same order number seen
    /// in another email), then the evidence itself (the same memory being
    /// extracted again after an edit).
    static func upsert(
        _ draft: CardDraft,
        source: SourceType,
        sourceAccountID: UUID? = nil,
        evidenceID: UUID?,
        asOf: Date
    ) throws -> ContextCard {
        let store = VaultStore.shared

        if let key = draft.mergeKey, let existing = try store.card(mergeKey: key) {
            update(existing, with: draft, evidenceID: evidenceID, asOf: asOf)
            return existing
        }
        if let evidenceID,
           let existing = try store.cards(evidenceID: evidenceID).first(where: { $0.evidenceIDs.count == 1 }) {
            // Re-extraction of one memory replaces what it said before
            // rather than merging with its own earlier reading.
            write(draft, to: existing, asOf: asOf)
            return existing
        }

        let card = makeCard(
            from: draft,
            source: source,
            sourceAccountID: sourceAccountID,
            evidenceID: evidenceID,
            asOf: asOf
        )
        store.context.insert(card)
        return card
    }

    /// Whether a card's moment has passed and it should leave the index
    /// (see `CardKind.isExpired`).
    static func isExpired(_ card: ContextCard, now: Date = .now) -> Bool {
        card.kind.isExpired(primaryDate: card.primaryDate, endDate: card.endDate, now: now)
    }

    /// Archives cards whose date has passed. Returns the cards changed, so
    /// the caller can reindex them (which removes them from the index).
    static func archiveExpired(now: Date = .now) throws -> [ContextCard] {
        let expired = try VaultStore.shared.cards(includeArchived: false).filter { isExpired($0, now: now) }
        for card in expired {
            card.isArchived = true
        }
        return expired
    }

    // MARK: Writing

    /// Renders a draft and writes every derived field onto the card.
    private static func write(_ draft: CardDraft, to card: ContextCard, asOf: Date) {
        let rendered = CardRenderer.render(draft, source: card.sourceType, asOf: asOf)
        card.kind = draft.kind
        card.title = rendered.title
        card.statement = rendered.statement
        card.detail = rendered.detail
        card.attributes = rendered.attributes
        card.aliases = draft.aliases
        card.primaryDate = draft.date
        card.primaryDateHasTime = draft.dateHasTime
        card.endDate = draft.endDate
        card.status = draft.status
        card.mergeKey = draft.mergeKey
        card.counterpart = draft.counterpart
        card.confidence = draft.confidence
        card.asOf = asOf
        card.draft = draft
    }
}
