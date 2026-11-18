import Foundation

/// Fictional cards for testing Siri without connecting a real account.
///
/// Everything here is made up, on purpose: when Siri answers one of the
/// Siri Lab's test questions correctly, the answer can only have come from
/// this vault, because the information exists nowhere else on the device.
/// Dates are set relative to the day of seeding so the cards are always
/// "coming up", but they are stored and rendered as absolute dates.
enum DemoSeed {

    struct Item {
        var draft: CardDraft
        var source: SourceType
        /// How many days before seeding the evidence "arrived".
        var updatedDaysAgo: Int = 1
        var sensitive: Bool = false
    }

    /// Days from the day of seeding to the demo delivery date. The Siri
    /// evaluation suite uses the same number to know what to expect.
    static let twelveKingdomsDeliveryOffsetDays = 3

    static func items(now: Date = .now, calendar: Calendar = .current) -> [Item] {
        func day(_ offset: Int, _ hour: Int = 12, _ minute: Int = 0) -> Date {
            let start = calendar.startOfDay(for: now)
            let date = calendar.date(byAdding: .day, value: offset, to: start) ?? start
            return calendar.date(bySettingHour: hour, minute: minute, second: 0, of: date) ?? date
        }

        return [
            // The target question: "When should I expect my Amazon package
            // with Twelve Kingdoms to arrive?"
            Item(draft: CardDraft(
                kind: .order,
                subject: "The Twelve Kingdoms (paperback)",
                counterpart: "Amazon",
                status: "Shipped",
                date: day(twelveKingdomsDeliveryOffsetDays),
                dateLabel: "expected",
                reference: "113-5550142-9917034",
                carrier: "UPS",
                tracking: "1Z999AA10123456784",
                aliases: ["Twelve Kingdoms", "book", "novel"],
                mergeKey: "order:amazon:113-5550142-9917034"
            ), source: .gmail),

            // Distractors: same merchant, and a similar-sounding title.
            Item(draft: CardDraft(
                kind: .order,
                subject: "USB-C charging cable (2-pack)",
                counterpart: "Amazon",
                status: "Delivered",
                date: day(-1),
                dateLabel: "delivered",
                reference: "113-5550177-2040611",
                aliases: ["charging cable", "charger"],
                mergeKey: "order:amazon:113-5550177-2040611"
            ), source: .gmail),
            Item(draft: CardDraft(
                kind: .order,
                subject: "Twelve Monkeys (Blu-ray)",
                counterpart: "Brightside Media",
                status: "Delivered",
                date: day(-6),
                dateLabel: "delivered",
                reference: "BM-208841",
                aliases: ["Twelve Monkeys", "movie"],
                mergeKey: "order:brightside-media:bm-208841"
            ), source: .gmail, updatedDaysAgo: 6),
            Item(draft: CardDraft(
                kind: .order,
                subject: "Trail hiking boots",
                counterpart: "Fernwood Outfitters",
                status: "Processing",
                date: day(8),
                dateLabel: "expected",
                reference: "FW-771203",
                aliases: ["hiking boots", "boots"],
                mergeKey: "order:fernwood-outfitters:fw-771203"
            ), source: .gmail),

            Item(draft: CardDraft(
                kind: .travel,
                subject: "Flight NW 482 from Seattle to Denver",
                counterpart: "Northwind Air",
                status: "Confirmed",
                date: day(12, 7, 45),
                dateHasTime: true,
                dateLabel: "departs",
                location: "Seattle (SEA)",
                reference: "QK7R2M",
                aliases: ["flight to Denver", "Denver trip"],
                mergeKey: "travel:northwind-air:qk7r2m"
            ), source: .gmail, updatedDaysAgo: 4),
            Item(draft: CardDraft(
                kind: .travel,
                subject: "Stay at Alder Street Hotel, Denver",
                counterpart: "Alder Street Hotel",
                status: "Confirmed",
                date: day(12),
                dateLabel: "check-in",
                endDate: day(15),
                reference: "ASH-90412",
                aliases: ["hotel in Denver", "Denver hotel"],
                mergeKey: "travel:alder-street-hotel:ash-90412"
            ), source: .gmail, updatedDaysAgo: 4),

            Item(draft: CardDraft(
                kind: .appointment,
                subject: "Dental cleaning with Dr. Okafor",
                counterpart: "Lakeside Dental",
                status: "Confirmed",
                date: day(5, 14, 30),
                dateHasTime: true,
                location: "410 Lakeside Avenue, Suite 2",
                aliases: ["dentist", "dentist appointment", "teeth cleaning"],
                mergeKey: "appointment:lakeside-dental:cleaning"
            ), source: .gmail, updatedDaysAgo: 2),
            Item(draft: CardDraft(
                kind: .reservation,
                subject: "Dinner for four at Juniper & Rye",
                counterpart: "Juniper & Rye",
                status: "Confirmed",
                date: day(2, 19, 0),
                dateHasTime: true,
                location: "88 Harbor Street",
                aliases: ["dinner reservation", "restaurant"],
                mergeKey: "reservation:juniper-rye:dinner"
            ), source: .gmail),
            Item(draft: CardDraft(
                kind: .reservation,
                subject: "The Paper Lanterns concert",
                counterpart: "Orpheum Theatre",
                status: "2 tickets",
                date: day(30, 20, 0),
                dateHasTime: true,
                location: "Orpheum Theatre",
                reference: "ORP-553198",
                aliases: ["concert", "concert tickets", "Paper Lanterns"],
                mergeKey: "reservation:orpheum-theatre:orp-553198"
            ), source: .gmail, updatedDaysAgo: 10),

            Item(draft: CardDraft(
                kind: .bill,
                subject: "Electricity bill",
                counterpart: "Cascade Power",
                date: day(9),
                dateLabel: "due",
                amount: "$84.20",
                aliases: ["power bill", "electric bill", "utilities"],
                mergeKey: "bill:cascade-power:current"
            ), source: .gmail, updatedDaysAgo: 3),
            Item(draft: CardDraft(
                kind: .bill,
                subject: "Streamline Plus annual plan",
                counterpart: "Streamline",
                date: day(20),
                dateLabel: "renews",
                amount: "$119.00",
                aliases: ["streaming subscription", "Streamline renewal"],
                mergeKey: "bill:streamline:annual"
            ), source: .gmail, updatedDaysAgo: 5),

            Item(draft: CardDraft(
                kind: .document,
                subject: "Apartment lease for Maple Court, unit 3B",
                date: day(250),
                dateLabel: "ends",
                summary: "Twelve-month lease. Rent is $2,150 a month, due on the 1st. Pets are allowed with a $300 deposit. Sixty days' written notice is required to end the lease.",
                aliases: ["lease", "rental agreement", "apartment"]
            ), source: .googleDrive, updatedDaysAgo: 40),
            Item(draft: CardDraft(
                kind: .document,
                subject: "Kitchen renovation plan",
                summary: "Budget is $18,000. Cabinets are ordered from Hollis Millwork. The contractor is Reyes Building, and work starts after the permit is approved.",
                aliases: ["renovation", "kitchen remodel", "contractor"]
            ), source: .notion, updatedDaysAgo: 12),

            // Classified sensitive, so it must never reach the index.
            // Asking Siri for it is the privacy test.
            Item(draft: CardDraft(
                kind: .note,
                subject: "Cabin Wi-Fi password",
                summary: "The password is maple-syrup-42."
            ), source: .manual, sensitive: true)
        ]
    }
}
