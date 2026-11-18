import Foundation
import Testing
@testable import ContextVault

/// How evidence about the same thing combines into one card.
struct CardDraftTests {
    private let thursday = Date(timeIntervalSince1970: 1_795_089_600) // 2026-11-19
    private let friday = Date(timeIntervalSince1970: 1_795_176_000)   // 2026-11-20

    private var confirmation: CardDraft {
        var draft = CardDraft(kind: .order, subject: "The Twelve Kingdoms (paperback)", counterpart: "Amazon")
        draft.status = "Ordered"
        draft.amount = "$14.99"
        draft.reference = "113-5550142-9917034"
        draft.aliases = ["Twelve Kingdoms"]
        draft.mergeKey = CardDraft.makeMergeKey(kind: .order, counterpart: "Amazon", reference: draft.reference)
        return draft
    }

    private var shippingNotice: CardDraft {
        var draft = CardDraft(kind: .order, subject: "Your package", counterpart: "Amazon")
        draft.status = "Shipped"
        draft.date = thursday
        draft.dateLabel = "expected"
        draft.carrier = "UPS"
        draft.tracking = "1Z999AA10123456784"
        draft.reference = "113-5550142-9917034"
        draft.aliases = ["package", "twelve kingdoms"]
        draft.mergeKey = CardDraft.makeMergeKey(kind: .order, counterpart: "Amazon", reference: draft.reference)
        draft.confidence = 0.5
        return draft
    }

    @Test func mergeKeyIsStableAcrossSpellings() {
        let a = CardDraft.makeMergeKey(kind: .order, counterpart: "Amazon.com", reference: " 113-5550142-9917034 ")
        let b = CardDraft.makeMergeKey(kind: .order, counterpart: "amazon com", reference: "113-5550142-9917034")
        #expect(a == "order:amazon-com:113-5550142-9917034")
        #expect(a == b)
        #expect(confirmation.mergeKey == shippingNotice.mergeKey)
    }

    @Test func noReferenceMeansNoMergeKey() {
        #expect(CardDraft.makeMergeKey(kind: .order, counterpart: "Amazon", reference: nil) == nil)
        #expect(CardDraft.makeMergeKey(kind: .order, counterpart: "Amazon", reference: "  ") == nil)
    }

    @Test func newerEvidenceUpdatesStatusAndDateButKeepsEarlierFacts() {
        let merged = confirmation.merging(shippingNotice, incomingIsNewer: true)

        // From the newer shipping notice.
        #expect(merged.status == "Shipped")
        #expect(merged.date == thursday)
        #expect(merged.carrier == "UPS")
        #expect(merged.tracking == "1Z999AA10123456784")
        // Kept from the confirmation, which the notice did not restate.
        #expect(merged.subject == "The Twelve Kingdoms (paperback)")
        #expect(merged.amount == "$14.99")
        // Aliases are combined without duplicates, ignoring case.
        #expect(merged.aliases == ["Twelve Kingdoms", "package"])
    }

    @Test func evidenceArrivingOutOfOrderGivesTheSameCard() {
        // The shipping notice is processed first, the older confirmation later.
        let lateArrival = shippingNotice.merging(confirmation, incomingIsNewer: false)
        let inOrder = confirmation.merging(shippingNotice, incomingIsNewer: true)

        #expect(lateArrival.status == inOrder.status)
        #expect(lateArrival.date == inOrder.date)
        #expect(lateArrival.subject == inOrder.subject)
        #expect(lateArrival.amount == inOrder.amount)
        #expect(lateArrival.carrier == inOrder.carrier)
    }

    @Test func aLaterDateReplacesAnEarlierOne() {
        var delayed = shippingNotice
        delayed.status = "Delayed"
        delayed.date = friday

        let merged = confirmation
            .merging(shippingNotice, incomingIsNewer: true)
            .merging(delayed, incomingIsNewer: true)

        #expect(merged.status == "Delayed")
        #expect(merged.date == friday)
    }

    @Test func aNewerDraftWithoutADateKeepsTheKnownDate() {
        var delivered = CardDraft(kind: .order, subject: "Your package", counterpart: "Amazon")
        delivered.status = "Out for delivery"
        delivered.confidence = 0.5

        let merged = shippingNotice.merging(delivered, incomingIsNewer: true)
        #expect(merged.status == "Out for delivery")
        #expect(merged.date == thursday)
        #expect(merged.dateLabel == "expected")
    }

    @Test func aMoreConfidentNewerDraftMayRenameTheCard() {
        var vague = CardDraft(kind: .order, subject: "Your order", counterpart: "Amazon")
        vague.confidence = 0.5
        var precise = CardDraft(kind: .order, subject: "The Twelve Kingdoms (paperback)", counterpart: "Amazon")
        precise.confidence = 1

        #expect(vague.merging(precise, incomingIsNewer: true).subject == "The Twelve Kingdoms (paperback)")
        #expect(precise.merging(vague, incomingIsNewer: true).subject == "The Twelve Kingdoms (paperback)")
    }

    @Test func draftsSurviveEncodingForStorage() throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970

        let decoded = try decoder.decode(CardDraft.self, from: encoder.encode(shippingNotice))
        #expect(decoded == shippingNotice)
    }

    @Test func ordersLingerAWeekOtherDatedCardsTwoDays() {
        let day = 86_400.0
        #expect(!CardKind.order.isExpired(primaryDate: thursday, endDate: nil, now: thursday.addingTimeInterval(6 * day)))
        #expect(CardKind.order.isExpired(primaryDate: thursday, endDate: nil, now: thursday.addingTimeInterval(8 * day)))

        #expect(!CardKind.appointment.isExpired(primaryDate: thursday, endDate: nil, now: thursday.addingTimeInterval(1 * day)))
        #expect(CardKind.appointment.isExpired(primaryDate: thursday, endDate: nil, now: thursday.addingTimeInterval(3 * day)))
    }

    @Test func aStayExpiresAfterItsEndDateNotItsStart() {
        let day = 86_400.0
        let checkout = thursday.addingTimeInterval(3 * day)
        #expect(!CardKind.travel.isExpired(primaryDate: thursday, endDate: checkout, now: thursday.addingTimeInterval(4 * day)))
        #expect(CardKind.travel.isExpired(primaryDate: thursday, endDate: checkout, now: checkout.addingTimeInterval(3 * day)))
    }

    @Test func documentsAndUndatedCardsNeverExpire() {
        let farFuture = thursday.addingTimeInterval(1000 * 86_400)
        #expect(!CardKind.document.isExpired(primaryDate: thursday, endDate: nil, now: farFuture))
        #expect(!CardKind.order.isExpired(primaryDate: nil, endDate: nil, now: farFuture))
    }
}
