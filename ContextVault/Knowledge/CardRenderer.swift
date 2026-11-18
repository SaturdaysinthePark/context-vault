import Foundation

/// Turns structured facts into the text Siri reads.
///
/// Two rules matter more than style:
/// 1. Dates are absolute ("Thursday, November 19, 2026"). The text sits in
///    an index for days; "tomorrow" would be wrong by the time it is read.
/// 2. The statement stands alone. Siri may see nothing but this sentence,
///    so it names the thing, its state, its date and where it came from.
enum CardRenderer {

    struct Rendered: Equatable, Sendable {
        var title: String
        var statement: String
        var detail: String
        var attributes: [String: String]
    }

    static func render(
        _ draft: CardDraft,
        source: SourceType,
        asOf: Date,
        locale: Locale = .current,
        timeZone: TimeZone = .current
    ) -> Rendered {
        let subject = draft.subject.trimmingCharacters(in: .whitespacesAndNewlines)
        let counterpart = clean(draft.counterpart)

        // Title: short, shown as the entity's name.
        let title: String
        // Head: how the statement opens.
        let head: String
        if draft.kind == .order, let counterpart {
            title = "\(counterpart) order: \(subject)"
            head = "\(counterpart) order of \(subject)"
        } else if let counterpart, !subject.localizedCaseInsensitiveContains(counterpart) {
            title = subject
            head = "\(subject) (\(counterpart))"
        } else {
            title = subject
            head = subject
        }

        var clauses: [String] = []
        if let status = clean(draft.status) {
            clauses.append(lowercasingFirst(status))
        }
        let dateLabel = clean(draft.dateLabel) ?? defaultDateLabel(for: draft.kind)
        if let date = draft.date {
            let formatted = format(date, hasTime: draft.dateHasTime, locale: locale, timeZone: timeZone)
            clauses.append("\(dateLabel) \(formatted)")
        }
        if let endDate = draft.endDate {
            clauses.append("until \(format(endDate, hasTime: false, locale: locale, timeZone: timeZone))")
        }
        if let location = clean(draft.location) {
            clauses.append("at \(location)")
        }
        if let amount = clean(draft.amount) {
            clauses.append(amount)
        }

        var sentences: [String] = []
        sentences.append(clauses.isEmpty ? "\(head)." : "\(head): \(clauses.joined(separator: ", ")).")
        if let summary = clean(draft.summary) {
            sentences.append(endingWithPeriod(String(summary.prefix(400))))
        }
        let updated = format(asOf, hasTime: false, locale: locale, timeZone: timeZone)
        sentences.append("Source: \(source.displayName), updated \(updated).")
        let statement = sentences.joined(separator: " ")

        // Detail: one fact per line, for the index's full-text field and
        // for the card screen.
        var lines: [String] = []
        var attributes: [String: String] = [:]
        func add(_ label: String, _ value: String?) {
            guard let value = clean(value) else { return }
            lines.append("\(label): \(value)")
            attributes[label] = value
        }
        if draft.kind == .order { add(CardFact.items, subject) }
        add("Status", draft.status)
        if let date = draft.date {
            add(capitalizingFirst(dateLabel), format(date, hasTime: draft.dateHasTime, locale: locale, timeZone: timeZone))
            attributes[CardFact.dateLabel] = dateLabel
        }
        if let endDate = draft.endDate {
            add("Ends", format(endDate, hasTime: false, locale: locale, timeZone: timeZone))
        }
        add(CardFact.location, draft.location)
        add(CardFact.amount, draft.amount)
        add(CardFact.reference, draft.reference)
        add(CardFact.carrier, draft.carrier)
        add(CardFact.tracking, draft.tracking)
        add("From", counterpart)
        add("Source", source.displayName)
        if let summary = clean(draft.summary) {
            add(CardFact.summary, String(summary.prefix(1200)))
        }

        return Rendered(
            title: title,
            statement: statement,
            detail: lines.joined(separator: "\n"),
            attributes: attributes
        )
    }

    /// "Amazon, via Gmail" — or just "Gmail" when there is no counterpart.
    static func sourceLabel(counterpart: String?, source: SourceType) -> String {
        if let counterpart = clean(counterpart) {
            return "\(counterpart), via \(source.displayName)"
        }
        return source.displayName
    }

    /// An absolute, fully spelled-out date: "Thursday, November 19, 2026",
    /// with "at 3:30 PM" appended when the time of day matters.
    static func format(_ date: Date, hasTime: Bool, locale: Locale = .current, timeZone: TimeZone = .current) -> String {
        var style = Date.FormatStyle(date: .complete, time: hasTime ? .shortened : .omitted)
        style.locale = locale
        style.timeZone = timeZone
        return date.formatted(style)
    }

    static func defaultDateLabel(for kind: CardKind) -> String {
        switch kind {
        case .order: "expected"
        case .travel: "departs"
        case .reservation, .appointment: "on"
        case .bill: "due"
        case .document, .note, .other: "dated"
        }
    }

    // MARK: Helpers

    private static func clean(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty else { return nil }
        return trimmed
    }

    private static func lowercasingFirst(_ text: String) -> String {
        guard let first = text.first else { return text }
        // Keep acronyms and proper nouns ("UPS has it") intact.
        let second = text.dropFirst().first
        if let second, second.isUppercase { return text }
        return first.lowercased() + text.dropFirst()
    }

    private static func capitalizingFirst(_ text: String) -> String {
        guard let first = text.first else { return text }
        return first.uppercased() + text.dropFirst()
    }

    private static func endingWithPeriod(_ text: String) -> String {
        guard let last = text.last else { return text }
        return ".!?".contains(last) ? text : text + "."
    }
}

extension CardSnapshot {
    /// What a card made from this draft looks like, without a store. Used
    /// to rank and test drafts before they are saved.
    init(
        draft: CardDraft,
        source: SourceType,
        asOf: Date,
        id: UUID = UUID(),
        locale: Locale = .current,
        timeZone: TimeZone = .current
    ) {
        let rendered = CardRenderer.render(draft, source: source, asOf: asOf, locale: locale, timeZone: timeZone)
        self.init(
            id: id,
            kind: draft.kind,
            title: rendered.title,
            statement: rendered.statement,
            detail: rendered.detail,
            attributes: rendered.attributes,
            aliases: draft.aliases,
            primaryDate: draft.date,
            endDate: draft.endDate,
            status: draft.status,
            sourceType: source,
            counterpart: draft.counterpart,
            asOf: asOf,
            createdAt: asOf
        )
    }
}
