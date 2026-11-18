import Foundation
import Testing
@testable import ContextVault

struct CardRendererTests {
    private let locale = Locale(identifier: "en_US")
    private let utc = TimeZone(identifier: "UTC")!

    /// 2026-11-19 12:00 UTC, a Thursday.
    private let delivery = Date(timeIntervalSince1970: 1_795_089_600)
    /// 2026-11-17 12:00 UTC, a Tuesday.
    private let updated = Date(timeIntervalSince1970: 1_794_916_800)

    private func render(_ draft: CardDraft, source: SourceType = .gmail) -> CardRenderer.Rendered {
        CardRenderer.render(draft, source: source, asOf: updated, locale: locale, timeZone: utc)
    }

    @Test func orderStatementAnswersTheQuestion() {
        var draft = CardDraft(kind: .order, subject: "The Twelve Kingdoms (paperback)", counterpart: "Amazon")
        draft.status = "Shipped"
        draft.date = delivery
        draft.dateLabel = "expected"

        let rendered = render(draft)

        #expect(rendered.title == "Amazon order: The Twelve Kingdoms (paperback)")
        #expect(rendered.statement ==
            "Amazon order of The Twelve Kingdoms (paperback): shipped, expected Thursday, November 19, 2026. "
            + "Source: Gmail, updated Tuesday, November 17, 2026.")
    }

    @Test func datesAreAbsoluteNeverRelative() {
        var draft = CardDraft(kind: .order, subject: "Cable", counterpart: "Amazon")
        draft.date = delivery
        let statement = render(draft).statement
        for relative in ["today", "tomorrow", "yesterday", "in 2 days"] {
            #expect(!statement.localizedCaseInsensitiveContains(relative))
        }
        #expect(statement.contains("2026"))
    }

    @Test func timeOfDayAppearsOnlyWhenItMatters() {
        var draft = CardDraft(kind: .appointment, subject: "Dental cleaning with Dr. Okafor", counterpart: "Lakeside Dental")
        draft.date = Date(timeIntervalSince1970: 1_795_098_600) // 14:30 UTC the same day
        draft.dateHasTime = true
        #expect(render(draft).statement.contains("2:30"))

        draft.dateHasTime = false
        #expect(!render(draft).statement.contains("2:30"))
    }

    @Test func counterpartIsNotRepeatedWhenTheSubjectNamesIt() {
        let named = CardDraft(kind: .travel, subject: "Stay at Alder Street Hotel, Denver", counterpart: "Alder Street Hotel")
        #expect(render(named).statement.hasPrefix("Stay at Alder Street Hotel, Denver."))

        let unnamed = CardDraft(kind: .bill, subject: "Electricity bill", counterpart: "Cascade Power")
        #expect(render(unnamed).statement.hasPrefix("Electricity bill (Cascade Power)."))
    }

    @Test func defaultDateLabelFollowsTheKind() {
        var bill = CardDraft(kind: .bill, subject: "Electricity bill")
        bill.date = delivery
        #expect(render(bill).statement.contains("due Thursday"))

        var flight = CardDraft(kind: .travel, subject: "Flight NW 482")
        flight.date = delivery
        #expect(render(flight).statement.contains("departs Thursday"))
    }

    @Test func detailListsOneFactPerLine() {
        var draft = CardDraft(kind: .order, subject: "The Twelve Kingdoms", counterpart: "Amazon")
        draft.status = "Shipped"
        draft.date = delivery
        draft.reference = "113-5550142-9917034"
        draft.carrier = "UPS"
        draft.tracking = "1Z999AA10123456784"

        let rendered = render(draft)
        let lines = rendered.detail.components(separatedBy: "\n")

        #expect(lines.contains("Items: The Twelve Kingdoms"))
        #expect(lines.contains("Status: Shipped"))
        #expect(lines.contains("Expected: Thursday, November 19, 2026"))
        #expect(lines.contains("Reference: 113-5550142-9917034"))
        #expect(lines.contains("Carrier: UPS"))
        #expect(lines.contains("Tracking number: 1Z999AA10123456784"))
        #expect(lines.contains("Source: Gmail"))
        #expect(rendered.attributes[CardFact.carrier] == "UPS")
        #expect(rendered.attributes[CardFact.items] == "The Twelve Kingdoms")
    }

    @Test func blankFieldsAreLeftOut() {
        var draft = CardDraft(kind: .order, subject: "Cable", counterpart: "  ")
        draft.status = ""
        draft.carrier = "   "
        let rendered = render(draft)
        #expect(rendered.title == "Cable")
        #expect(!rendered.detail.contains("Status"))
        #expect(!rendered.detail.contains("Carrier"))
        #expect(rendered.statement.hasPrefix("Cable. "))
    }

    @Test func summaryIsIncludedAndEndsCleanly() {
        var draft = CardDraft(kind: .document, subject: "Apartment lease")
        draft.summary = "Pets are allowed with a $300 deposit"
        let statement = render(draft, source: .googleDrive).statement
        #expect(statement.contains("Pets are allowed with a $300 deposit. Source: Google Drive"))
    }

    @Test func sourceLabelNamesCounterpartAndSource() {
        #expect(CardRenderer.sourceLabel(counterpart: "Amazon", source: .gmail) == "Amazon, via Gmail")
        #expect(CardRenderer.sourceLabel(counterpart: nil, source: .googleDrive) == "Google Drive")
        #expect(CardRenderer.sourceLabel(counterpart: " ", source: .notion) == "Notion")
    }
}
