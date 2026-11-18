import AppIntents
import CoreTransferable
import SwiftUI
import UniformTypeIdentifiers

// How a context card looks and travels outside the app.

/// The card Siri shows for a context card, in place of the default title
/// and subtitle. The system renders it ahead of time and keeps a static
/// copy, so the view is built only from the entity's own properties —
/// nothing asynchronous, nothing fetched.
extension ContextCardEntity: SnippetRepresentableEntity {
    static var snippet: some Snippet {
        CardSnippet(supportedFamilies: [.compact, .standard]) { card, context in
            ContextCardSnippetView(card: card, isCompact: context.family == .compact)
        }
    }
}

private struct ContextCardSnippetView: View {
    let card: ContextCardEntity
    let isCompact: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: card.kind.systemImage)
                .font(.title3)
                .foregroundStyle(.tint)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 4) {
                Text(card.title)
                    .font(.headline)
                    .lineLimit(isCompact ? 1 : 2)

                if let date = card.date {
                    Text(date, format: .dateTime.weekday(.wide).month(.wide).day())
                        .font(.subheadline)
                }
                if let status = card.status {
                    Text(status)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                if !isCompact {
                    Text("\(card.source.localizedName) · updated \(card.lastUpdated.formatted(date: .abbreviated, time: .omitted))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
        }
    }
}

/// Lets a card be handed to another app ("send my flight details to
/// Sam"): as plain text, which every messaging and mail app accepts.
extension ContextCardEntity: Transferable {
    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .plainText) { card in
            Data("\(card.title)\n\(card.summary)".utf8)
        }
    }
}
