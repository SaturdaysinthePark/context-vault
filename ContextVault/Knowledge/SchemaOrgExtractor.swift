import Foundation

/// Reads the structured data some senders embed in their email.
///
/// Retailers, airlines, hotels and ticketing services often include a
/// machine-readable description of the order or booking in the message's
/// HTML, as schema.org JSON-LD (the same markup that powers the summary
/// cards mail clients show). When it is present it is exact — no model
/// has to guess a delivery date from prose — so it is tried first.
///
/// Pure and synchronous: it takes JSON-LD strings and returns drafts.
enum SchemaOrgExtractor {

    /// Extracts drafts from JSON-LD blocks.
    /// - Parameter fallbackCounterpart: used when the markup names no
    ///   merchant or provider (usually the mail sender's display name).
    static func drafts(fromJSONLD blocks: [String], fallbackCounterpart: String? = nil) -> [CardDraft] {
        var drafts: [CardDraft] = []
        for block in blocks {
            guard let data = block.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) else { continue }
            for node in nodes(in: json) {
                if let draft = draft(from: node, fallbackCounterpart: fallbackCounterpart) {
                    drafts.append(draft)
                }
            }
        }
        // One email may describe the same order twice (an Order and its
        // ParcelDelivery). Fold drafts that share a merge key together.
        var merged: [CardDraft] = []
        for draft in drafts {
            if let key = draft.mergeKey, let index = merged.firstIndex(where: { $0.mergeKey == key }) {
                merged[index] = merged[index].merging(draft, incomingIsNewer: true)
            } else {
                merged.append(draft)
            }
        }
        return merged
    }

    /// Pulls JSON-LD blocks out of an HTML document.
    static func jsonLDBlocks(inHTML html: String) -> [String] {
        var blocks: [String] = []
        var searchRange = html.startIndex..<html.endIndex
        while let open = html.range(of: "<script", options: .caseInsensitive, range: searchRange) {
            guard let tagEnd = html.range(of: ">", range: open.upperBound..<html.endIndex),
                  let close = html.range(of: "</script>", options: .caseInsensitive, range: tagEnd.upperBound..<html.endIndex)
            else { break }
            let tag = html[open.lowerBound..<tagEnd.upperBound]
            if tag.range(of: "application/ld+json", options: .caseInsensitive) != nil {
                let body = html[tagEnd.upperBound..<close.lowerBound].trimmingCharacters(in: .whitespacesAndNewlines)
                if !body.isEmpty { blocks.append(body) }
            }
            searchRange = close.upperBound..<html.endIndex
        }
        return blocks
    }

    // MARK: Node traversal

    /// Flattens a JSON-LD document into its typed objects: the top-level
    /// object, each element of a top-level array, and members of `@graph`.
    private static func nodes(in json: Any) -> [[String: Any]] {
        if let array = json as? [Any] {
            return array.flatMap(nodes(in:))
        }
        guard let object = json as? [String: Any] else { return [] }
        if let graph = object["@graph"] {
            return nodes(in: graph)
        }
        return [object]
    }

    private static func types(of node: [String: Any]) -> [String] {
        let raw: [String]
        if let one = node["@type"] as? String {
            raw = [one]
        } else {
            raw = node["@type"] as? [String] ?? []
        }
        // "http://schema.org/Order" and "Order" mean the same thing.
        return raw.map { $0.components(separatedBy: "/").last ?? $0 }
    }

    private static func draft(from node: [String: Any], fallbackCounterpart: String?) -> CardDraft? {
        let types = types(of: node)
        if types.contains("ParcelDelivery") { return parcelDelivery(node, fallbackCounterpart) }
        if types.contains("Order") { return order(node, fallbackCounterpart) }
        if types.contains("FlightReservation") { return flight(node) }
        if types.contains("LodgingReservation") { return lodging(node) }
        if types.contains("FoodEstablishmentReservation") { return restaurant(node) }
        if types.contains("EventReservation") { return event(node) }
        if types.contains("Invoice") { return invoice(node, fallbackCounterpart) }
        return nil
    }

    // MARK: Type mappings

    private static func order(_ node: [String: Any], _ fallback: String?) -> CardDraft? {
        let merchant = name(node["merchant"]) ?? name(node["seller"]) ?? fallback
        let items = itemNames(node["acceptedOffer"]) + itemNames(node["orderedItem"])
        guard let subject = joined(items) ?? string(node["description"]) else { return nil }
        let reference = string(node["orderNumber"])

        var draft = CardDraft(kind: .order, subject: subject, counterpart: merchant)
        draft.status = orderStatus(string(node["orderStatus"]))
        draft.reference = reference
        draft.amount = money(node["price"], currency: node["priceCurrency"])
            ?? money((node["priceSpecification"] as? [String: Any])?["price"],
                     currency: (node["priceSpecification"] as? [String: Any])?["priceCurrency"])
        if let delivery = firstObject(node["orderDelivery"]) {
            apply(delivery: delivery, to: &draft)
        }
        draft.aliases = items
        draft.mergeKey = CardDraft.makeMergeKey(kind: .order, counterpart: merchant, reference: reference)
        return draft
    }

    private static func parcelDelivery(_ node: [String: Any], _ fallback: String?) -> CardDraft? {
        let parent = firstObject(node["partOfOrder"])
        let merchant = name(parent?["merchant"]) ?? name(parent?["seller"]) ?? fallback
        let items = itemNames(node["itemShipped"])
            + itemNames(parent?["acceptedOffer"])
            + itemNames(parent?["orderedItem"])
        let subject = joined(items) ?? "Package"
        let reference = string(parent?["orderNumber"])

        var draft = CardDraft(kind: .order, subject: subject, counterpart: merchant)
        draft.reference = reference
        draft.status = orderStatus(string(parent?["orderStatus"])) ?? "Shipped"
        apply(delivery: node, to: &draft)
        draft.aliases = items
        draft.mergeKey = CardDraft.makeMergeKey(kind: .order, counterpart: merchant, reference: reference)
            ?? CardDraft.makeMergeKey(kind: .order, counterpart: merchant, reference: draft.tracking)
        // A delivery notice that names no item is the weaker source for
        // the order's name, so let an earlier, named draft keep its subject.
        if items.isEmpty { draft.confidence = 0.5 }
        return draft
    }

    private static func apply(delivery: [String: Any], to draft: inout CardDraft) {
        if let (date, hasTime) = parseDate(delivery["expectedArrivalUntil"]) ?? parseDate(delivery["expectedArrivalFrom"]) {
            draft.date = date
            draft.dateHasTime = hasTime
            draft.dateLabel = "expected"
        }
        draft.tracking = string(delivery["trackingNumber"]) ?? draft.tracking
        draft.carrier = name(delivery["carrier"]) ?? name(delivery["provider"]) ?? draft.carrier
    }

    private static func flight(_ node: [String: Any]) -> CardDraft? {
        guard let flight = firstObject(node["reservationFor"]) else { return nil }
        let airline = name(flight["airline"]) ?? name(flight["provider"])
        let code = string((flight["airline"] as? [String: Any])?["iataCode"])
        let number = string(flight["flightNumber"])
        let from = airport(flight["departureAirport"])
        let to = airport(flight["arrivalAirport"])

        var subject = "Flight"
        if let number { subject += " \([code, number].compactMap(\.self).joined(separator: " "))" }
        if let from, let to { subject += " from \(from) to \(to)" }
        else if let to { subject += " to \(to)" }

        let reference = string(node["reservationNumber"])
        var draft = CardDraft(kind: .travel, subject: subject, counterpart: airline)
        draft.status = reservationStatus(string(node["reservationStatus"]))
        draft.reference = reference
        if let (date, hasTime) = parseDate(flight["departureTime"]) {
            draft.date = date
            draft.dateHasTime = hasTime
            draft.dateLabel = "departs"
        }
        draft.location = from
        draft.aliases = [to.map { "flight to \($0)" }].compactMap(\.self)
        draft.mergeKey = CardDraft.makeMergeKey(
            kind: .travel,
            counterpart: airline,
            reference: [reference, number].compactMap(\.self).joined(separator: "-")
        )
        return draft
    }

    private static func lodging(_ node: [String: Any]) -> CardDraft? {
        guard let place = firstObject(node["reservationFor"]), let hotel = name(place) else { return nil }
        let reference = string(node["reservationNumber"])
        var draft = CardDraft(kind: .travel, subject: "Stay at \(hotel)", counterpart: hotel)
        draft.status = reservationStatus(string(node["reservationStatus"]))
        draft.reference = reference
        if let (date, hasTime) = parseDate(node["checkinTime"]) ?? parseDate(node["checkinDate"]) {
            draft.date = date
            draft.dateHasTime = hasTime
            draft.dateLabel = "check-in"
        }
        draft.endDate = (parseDate(node["checkoutTime"]) ?? parseDate(node["checkoutDate"]))?.0
        draft.location = address(place["address"])
        draft.aliases = ["hotel"]
        draft.mergeKey = CardDraft.makeMergeKey(kind: .travel, counterpart: hotel, reference: reference)
        return draft
    }

    private static func restaurant(_ node: [String: Any]) -> CardDraft? {
        guard let place = firstObject(node["reservationFor"]), let restaurant = name(place) else { return nil }
        let reference = string(node["reservationNumber"])
        var subject = "Table at \(restaurant)"
        if let party = node["partySize"] {
            subject = "Table for \(party) at \(restaurant)"
        }
        var draft = CardDraft(kind: .reservation, subject: subject, counterpart: restaurant)
        draft.status = reservationStatus(string(node["reservationStatus"]))
        draft.reference = reference
        if let (date, hasTime) = parseDate(node["startTime"]) {
            draft.date = date
            draft.dateHasTime = hasTime
        }
        draft.location = address(place["address"])
        draft.aliases = ["dinner reservation", "restaurant"]
        draft.mergeKey = CardDraft.makeMergeKey(kind: .reservation, counterpart: restaurant, reference: reference)
        return draft
    }

    private static func event(_ node: [String: Any]) -> CardDraft? {
        guard let event = firstObject(node["reservationFor"]), let title = name(event) else { return nil }
        let venue = name(event["location"])
        let reference = string(node["reservationNumber"])
        var draft = CardDraft(kind: .reservation, subject: title, counterpart: venue)
        draft.status = reservationStatus(string(node["reservationStatus"]))
        draft.reference = reference
        if let (date, hasTime) = parseDate(event["startDate"]) {
            draft.date = date
            draft.dateHasTime = hasTime
        }
        draft.location = venue
        draft.aliases = ["tickets", "event"]
        draft.mergeKey = CardDraft.makeMergeKey(kind: .reservation, counterpart: venue ?? title, reference: reference)
        return draft
    }

    private static func invoice(_ node: [String: Any], _ fallback: String?) -> CardDraft? {
        let biller = name(node["provider"]) ?? name(node["broker"]) ?? fallback
        let subject = string(node["description"]) ?? biller.map { "\($0) bill" } ?? "Bill"
        let reference = string(node["confirmationNumber"]) ?? string(node["accountId"])
        var draft = CardDraft(kind: .bill, subject: subject, counterpart: biller)
        if let (date, _) = parseDate(node["paymentDueDate"]) ?? parseDate(node["paymentDue"]) {
            draft.date = date
            draft.dateLabel = "due"
        }
        if let total = node["totalPaymentDue"] as? [String: Any] {
            draft.amount = money(total["price"] ?? total["value"], currency: total["priceCurrency"] ?? total["currency"])
        }
        draft.status = reservationStatus(string(node["paymentStatus"]))
        draft.reference = reference
        draft.mergeKey = CardDraft.makeMergeKey(kind: .bill, counterpart: biller, reference: reference)
        return draft
    }

    // MARK: Value helpers

    /// A non-empty string from a JSON value (strings and numbers).
    private static func string(_ value: Any?) -> String? {
        switch value {
        case let text as String:
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        case let number as NSNumber:
            return number.stringValue
        default:
            return nil
        }
    }

    /// The `name` of an object, or the value itself when it is a string.
    private static func name(_ value: Any?) -> String? {
        if let object = value as? [String: Any] { return string(object["name"]) }
        return string(value)
    }

    private static func firstObject(_ value: Any?) -> [String: Any]? {
        if let object = value as? [String: Any] { return object }
        return (value as? [Any])?.compactMap { $0 as? [String: Any] }.first
    }

    /// Item names from an offer, an order item, a product, or arrays of them.
    private static func itemNames(_ value: Any?) -> [String] {
        let objects: [[String: Any]]
        if let array = value as? [Any] {
            objects = array.compactMap { $0 as? [String: Any] }
        } else if let object = value as? [String: Any] {
            objects = [object]
        } else {
            return []
        }
        return objects.compactMap { object in
            name(object["itemOffered"]) ?? name(object["orderedItem"]) ?? string(object["name"])
        }
    }

    private static func joined(_ items: [String]) -> String? {
        var seen = Set<String>()
        let unique = items.filter { seen.insert($0.lowercased()).inserted }
        guard !unique.isEmpty else { return nil }
        if unique.count <= 3 { return unique.joined(separator: ", ") }
        return unique.prefix(2).joined(separator: ", ") + " and \(unique.count - 2) more items"
    }

    private static func airport(_ value: Any?) -> String? {
        guard let object = value as? [String: Any] else { return string(value) }
        let name = string(object["name"])
        let code = string(object["iataCode"])
        switch (name, code) {
        case let (name?, code?): return "\(name) (\(code))"
        case let (name?, nil): return name
        case let (nil, code?): return code
        default: return nil
        }
    }

    private static func address(_ value: Any?) -> String? {
        guard let object = value as? [String: Any] else { return string(value) }
        let parts = ["streetAddress", "addressLocality", "addressRegion"].compactMap { string(object[$0]) }
        return parts.isEmpty ? nil : parts.joined(separator: ", ")
    }

    private static func money(_ price: Any?, currency: Any?) -> String? {
        let code = string(currency)
        let amount: String
        if let number = price as? NSNumber, !(price is String) {
            // A bare JSON number loses its trailing zero (84.2); write
            // money with two decimals, except currencies that have none.
            let wholeUnits = code?.uppercased() == "JPY"
            amount = String(format: wholeUnits ? "%.0f" : "%.2f", number.doubleValue)
        } else if let text = string(price) {
            amount = text
        } else {
            return nil
        }
        guard let code else { return amount }
        let symbols = ["USD": "$", "EUR": "€", "GBP": "£", "JPY": "¥", "CAD": "CA$", "AUD": "A$"]
        if let symbol = symbols[code.uppercased()] { return "\(symbol)\(amount)" }
        return "\(amount) \(code.uppercased())"
    }

    /// "http://schema.org/OrderInTransit" → "In transit".
    private static func orderStatus(_ raw: String?) -> String? {
        guard let token = raw?.components(separatedBy: "/").last else { return nil }
        switch token {
        case "OrderProcessing": return "Processing"
        case "OrderInTransit": return "In transit"
        case "OrderDelivered": return "Delivered"
        case "OrderCancelled": return "Cancelled"
        case "OrderPickupAvailable": return "Ready for pickup"
        case "OrderProblem": return "Problem with order"
        case "OrderReturned": return "Returned"
        case "OrderPaymentDue": return "Payment due"
        default: return nil
        }
    }

    /// "http://schema.org/ReservationConfirmed" → "Confirmed".
    private static func reservationStatus(_ raw: String?) -> String? {
        guard let token = raw?.components(separatedBy: "/").last else { return nil }
        switch token {
        case "ReservationConfirmed", "Confirmed": return "Confirmed"
        case "ReservationCancelled", "Cancelled": return "Cancelled"
        case "ReservationPending", "ReservationHold": return "Pending"
        case "PaymentDue": return "Due"
        case "PaymentComplete": return "Paid"
        case "PaymentPastDue": return "Past due"
        default: return nil
        }
    }

    /// Parses an ISO 8601 date or date-time. Returns whether a time of day
    /// was present, so a date-only value is not rendered as midnight.
    static func parseDate(_ value: Any?) -> (Date, Bool)? {
        guard let text = string(value) else { return nil }

        let withFraction = ISO8601DateFormatter()
        withFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = withFraction.date(from: text) { return (date, true) }

        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        if let date = plain.date(from: text) { return (date, true) }

        // Local date-time without a zone: "2026-11-19T15:30" or with seconds.
        let local = DateFormatter()
        local.locale = Locale(identifier: "en_US_POSIX")
        local.timeZone = .current
        for format in ["yyyy-MM-dd'T'HH:mm:ss", "yyyy-MM-dd'T'HH:mm"] {
            local.dateFormat = format
            if let date = local.date(from: text) { return (date, true) }
        }

        // Date only. Anchor at midday so a time-zone shift cannot move it
        // onto the neighbouring day when it is formatted.
        local.dateFormat = "yyyy-MM-dd"
        if let day = local.date(from: String(text.prefix(10))) {
            return (day.addingTimeInterval(12 * 3600), false)
        }
        return nil
    }
}
