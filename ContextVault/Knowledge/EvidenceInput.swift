import Foundation

/// What an extractor is given: one piece of evidence, already reduced to
/// plain text, with the few hints that help identify what it is about.
struct EvidenceInput: Sendable {
    var id: UUID
    var title: String
    var body: String
    var sourceType: SourceType
    var sourceAccountID: UUID?
    /// "Amazon.com <ship-confirm@amazon.com>"
    var sender: String?
    var threadKey: String?
    /// schema.org JSON-LD blocks found in the original HTML.
    var structuredData: [String]
    /// When the evidence was produced (mail sent date, file modified date).
    var date: Date
    /// True while the evidence has not been classified for sensitivity.
    var needsSensitivityCheck: Bool = false

    /// The sender's display name without the address: "Amazon.com". When
    /// the header is a bare address, the name is taken from its domain.
    var senderName: String? {
        guard let sender = sender?.trimmingCharacters(in: .whitespacesAndNewlines), !sender.isEmpty else {
            return nil
        }
        let quotes = CharacterSet(charactersIn: " \"'")
        if let angle = sender.firstIndex(of: "<") {
            let name = sender[..<angle].trimmingCharacters(in: quotes)
            if !name.isEmpty { return name }
        } else if !sender.contains("@") {
            let name = sender.trimmingCharacters(in: quotes)
            return name.isEmpty ? nil : name
        }

        // Address only: use the domain's main label, "amazon" → "Amazon".
        let address = sender.trimmingCharacters(in: CharacterSet(charactersIn: "<> "))
        guard let domain = address.components(separatedBy: "@").last, !domain.isEmpty else { return nil }
        let labels = domain.components(separatedBy: ".")
        let label = labels.count >= 2 ? labels[labels.count - 2] : domain
        return label.isEmpty ? nil : label.prefix(1).uppercased() + label.dropFirst()
    }
}
