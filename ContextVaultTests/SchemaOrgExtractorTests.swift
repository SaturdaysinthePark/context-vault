import Foundation
import Testing
@testable import ContextVault

/// Reading the structured order and booking data senders embed in mail.
/// All fixtures are fictional.
struct SchemaOrgExtractorTests {

    @Test func parcelDeliveryBecomesAnOrderCardWithADeliveryDate() throws {
        let json = """
        {
          "@context": "http://schema.org",
          "@type": "ParcelDelivery",
          "deliveryAddress": { "@type": "PostalAddress", "addressLocality": "Seattle" },
          "expectedArrivalUntil": "2026-11-19T20:00:00-08:00",
          "carrier": { "@type": "Organization", "name": "UPS" },
          "itemShipped": { "@type": "Product", "name": "The Twelve Kingdoms (paperback)" },
          "trackingNumber": "1Z999AA10123456784",
          "partOfOrder": {
            "@type": "Order",
            "orderNumber": "113-5550142-9917034",
            "merchant": { "@type": "Organization", "name": "Amazon" },
            "orderStatus": "http://schema.org/OrderInTransit"
          }
        }
        """
        let draft = try #require(SchemaOrgExtractor.drafts(fromJSONLD: [json]).first)

        #expect(draft.kind == .order)
        #expect(draft.subject == "The Twelve Kingdoms (paperback)")
        #expect(draft.counterpart == "Amazon")
        #expect(draft.status == "In transit")
        #expect(draft.carrier == "UPS")
        #expect(draft.tracking == "1Z999AA10123456784")
        #expect(draft.reference == "113-5550142-9917034")
        #expect(draft.dateLabel == "expected")
        #expect(draft.dateHasTime)
        // 20:00 at UTC-8 on the 19th is 04:00 UTC on the 20th.
        #expect(draft.date == Date(timeIntervalSince1970: 1_795_147_200))
        #expect(draft.mergeKey == "order:amazon:113-5550142-9917034")
    }

    @Test func orderListsItsItemsAndTotal() throws {
        let json = """
        {
          "@context": "http://schema.org",
          "@type": "Order",
          "merchant": { "@type": "Organization", "name": "Fernwood Outfitters" },
          "orderNumber": "FW-771203",
          "orderStatus": "http://schema.org/OrderProcessing",
          "priceCurrency": "USD",
          "price": "129.00",
          "acceptedOffer": [
            { "@type": "Offer", "itemOffered": { "@type": "Product", "name": "Trail hiking boots" } },
            { "@type": "Offer", "itemOffered": { "@type": "Product", "name": "Wool socks" } }
          ]
        }
        """
        let draft = try #require(SchemaOrgExtractor.drafts(fromJSONLD: [json]).first)

        #expect(draft.subject == "Trail hiking boots, Wool socks")
        #expect(draft.status == "Processing")
        #expect(draft.amount == "$129.00")
        #expect(draft.aliases == ["Trail hiking boots", "Wool socks"])
        #expect(draft.mergeKey == "order:fernwood-outfitters:fw-771203")
    }

    @Test func anOrderAndItsDeliveryInOneEmailBecomeOneDraft() {
        let order = """
        {"@type": "Order", "orderNumber": "A-1", "merchant": {"name": "Shop"},
         "acceptedOffer": {"itemOffered": {"name": "Desk lamp"}}}
        """
        let delivery = """
        {"@type": "ParcelDelivery", "expectedArrivalUntil": "2026-11-19",
         "trackingNumber": "T-9", "partOfOrder": {"@type": "Order", "orderNumber": "A-1", "merchant": {"name": "Shop"}}}
        """
        let drafts = SchemaOrgExtractor.drafts(fromJSONLD: [order, delivery])

        #expect(drafts.count == 1)
        #expect(drafts.first?.subject == "Desk lamp")
        #expect(drafts.first?.tracking == "T-9")
        #expect(drafts.first?.date != nil)
        #expect(drafts.first?.dateHasTime == false)
    }

    @Test func flightReservationNamesTheRouteAndDeparture() throws {
        let json = """
        {
          "@context": "http://schema.org",
          "@type": "FlightReservation",
          "reservationNumber": "QK7R2M",
          "reservationStatus": "http://schema.org/ReservationConfirmed",
          "reservationFor": {
            "@type": "Flight",
            "flightNumber": "482",
            "airline": { "@type": "Airline", "name": "Northwind Air", "iataCode": "NW" },
            "departureAirport": { "@type": "Airport", "name": "Seattle", "iataCode": "SEA" },
            "departureTime": "2026-11-28T07:45:00-08:00",
            "arrivalAirport": { "@type": "Airport", "name": "Denver", "iataCode": "DEN" }
          }
        }
        """
        let draft = try #require(SchemaOrgExtractor.drafts(fromJSONLD: [json]).first)

        #expect(draft.kind == .travel)
        #expect(draft.subject == "Flight NW 482 from Seattle (SEA) to Denver (DEN)")
        #expect(draft.counterpart == "Northwind Air")
        #expect(draft.status == "Confirmed")
        #expect(draft.dateLabel == "departs")
        #expect(draft.dateHasTime)
        #expect(draft.location == "Seattle (SEA)")
        #expect(draft.mergeKey == "travel:northwind-air:qk7r2m-482")
    }

    @Test func lodgingReservationHasCheckInAndCheckOut() throws {
        let json = """
        {
          "@type": "LodgingReservation",
          "reservationNumber": "ASH-90412",
          "reservationFor": {
            "@type": "LodgingBusiness",
            "name": "Alder Street Hotel",
            "address": { "streetAddress": "12 Alder Street", "addressLocality": "Denver", "addressRegion": "CO" }
          },
          "checkinDate": "2026-11-28",
          "checkoutDate": "2026-12-01"
        }
        """
        let draft = try #require(SchemaOrgExtractor.drafts(fromJSONLD: [json]).first)

        #expect(draft.subject == "Stay at Alder Street Hotel")
        #expect(draft.dateLabel == "check-in")
        #expect(draft.dateHasTime == false)
        #expect(draft.location == "12 Alder Street, Denver, CO")
        let start = try #require(draft.date)
        let end = try #require(draft.endDate)
        #expect(end.timeIntervalSince(start) == 3 * 86_400)
    }

    @Test func restaurantAndEventReservations() throws {
        let restaurant = """
        {"@type": "FoodEstablishmentReservation", "reservationNumber": "JR-77", "partySize": 4,
         "startTime": "2026-11-18T19:00:00-08:00",
         "reservationFor": {"@type": "FoodEstablishment", "name": "Juniper & Rye"}}
        """
        let event = """
        {"@type": "EventReservation", "reservationNumber": "ORP-553198",
         "reservationFor": {"@type": "Event", "name": "The Paper Lanterns", "startDate": "2026-12-16T20:00:00-08:00",
                            "location": {"@type": "Place", "name": "Orpheum Theatre"}}}
        """
        let drafts = SchemaOrgExtractor.drafts(fromJSONLD: [restaurant, event])
        #expect(drafts.count == 2)

        let table = try #require(drafts.first { $0.counterpart == "Juniper & Rye" })
        #expect(table.kind == .reservation)
        #expect(table.subject == "Table for 4 at Juniper & Rye")

        let show = try #require(drafts.first { $0.subject == "The Paper Lanterns" })
        #expect(show.counterpart == "Orpheum Theatre")
        #expect(show.location == "Orpheum Theatre")
    }

    @Test func invoiceBecomesABillWithItsDueDateAndAmount() throws {
        let json = """
        {"@type": "Invoice", "description": "Electricity bill", "paymentDueDate": "2026-11-25",
         "provider": {"@type": "Organization", "name": "Cascade Power"},
         "totalPaymentDue": {"@type": "PriceSpecification", "price": 84.2, "priceCurrency": "USD"}}
        """
        let draft = try #require(SchemaOrgExtractor.drafts(fromJSONLD: [json]).first)
        #expect(draft.kind == .bill)
        #expect(draft.subject == "Electricity bill")
        #expect(draft.counterpart == "Cascade Power")
        #expect(draft.dateLabel == "due")
        #expect(draft.amount == "$84.20")
    }

    @Test func graphArraysAndFullTypeURLsAreUnderstood() {
        let graph = """
        {"@context": "http://schema.org", "@graph": [
          {"@type": "http://schema.org/Order", "orderNumber": "G-1", "merchant": "Shop",
           "acceptedOffer": {"itemOffered": {"name": "Kettle"}}},
          {"@type": ["Thing", "Organization"], "name": "Shop"}
        ]}
        """
        let array = """
        [{"@type": "Order", "orderNumber": "G-2", "seller": {"name": "Other Shop"}, "description": "Gift card"}]
        """
        let drafts = SchemaOrgExtractor.drafts(fromJSONLD: [graph, array])
        #expect(drafts.map(\.subject) == ["Kettle", "Gift card"])
        #expect(drafts.map(\.counterpart) == ["Shop", "Other Shop"])
    }

    @Test func theSenderStandsInWhenNoMerchantIsNamed() throws {
        let json = """
        {"@type": "Order", "orderNumber": "X-9", "acceptedOffer": {"itemOffered": {"name": "Notebook"}}}
        """
        let draft = try #require(
            SchemaOrgExtractor.drafts(fromJSONLD: [json], fallbackCounterpart: "Paper & Pen").first
        )
        #expect(draft.counterpart == "Paper & Pen")
        #expect(draft.mergeKey == "order:paper-pen:x-9")
    }

    @Test func unrelatedOrBrokenMarkupProducesNothing() {
        let blocks = [
            #"{"@type": "Organization", "name": "Some Company"}"#,
            #"{"@type": "Order"}"#,
            "not json at all",
            ""
        ]
        #expect(SchemaOrgExtractor.drafts(fromJSONLD: blocks).isEmpty)
    }

    @Test func jsonLDIsFoundInsideHTML() {
        let html = """
        <html><head>
        <script>var tracking = 1;</script>
        <script type="application/ld+json">
        {"@type": "Order", "orderNumber": "H-1"}
        </script>
        <SCRIPT TYPE='application/ld+json'>{"@type": "ParcelDelivery"}</SCRIPT>
        </head><body><p>Thanks for your order.</p></body></html>
        """
        let blocks = SchemaOrgExtractor.jsonLDBlocks(inHTML: html)
        #expect(blocks.count == 2)
        #expect(blocks.first?.contains("H-1") == true)
        #expect(blocks.last == #"{"@type": "ParcelDelivery"}"#)
    }

    @Test func datesWithAndWithoutTimesAreParsed() throws {
        let withZone = try #require(SchemaOrgExtractor.parseDate("2026-11-19T15:30:00Z"))
        #expect(withZone.0 == Date(timeIntervalSince1970: 1_795_102_200))
        #expect(withZone.1)

        let fractional = try #require(SchemaOrgExtractor.parseDate("2026-11-19T15:30:00.000Z"))
        #expect(fractional.0 == withZone.0)

        let dateOnly = try #require(SchemaOrgExtractor.parseDate("2026-11-19"))
        #expect(dateOnly.1 == false)

        #expect(SchemaOrgExtractor.parseDate("next Thursday") == nil)
        #expect(SchemaOrgExtractor.parseDate("") == nil)
        #expect(SchemaOrgExtractor.parseDate(nil) == nil)
    }
}
