import Foundation

/// Renders vault content into a "Context Pack" — a single Markdown document
/// you can paste into ChatGPT, Claude, or any other AI. The cross-agent
/// "one vault, every AI" story, without a cloud or an MCP server.
///
/// Operates on plain values (not SwiftData models) so it's trivially
/// testable and callable from anywhere.
enum ContextPackExporter {

    struct MemoryInput {
        var title: String
        var body: String
    }

    struct CollectionInput {
        var name: String
        var details: String
        var aspects: [(kind: String, value: String)]
        var memories: [MemoryInput]
    }

    static let header = """
        # Context Pack — Context Vault
        > Personal context exported from Context Vault. Treat everything \
        below as background about the user; use it to personalize your \
        answers.
        """

    /// Render the About Me card alone.
    static func renderAboutMe(_ aboutMe: String) -> String {
        """
        \(header)

        ## About the user
        \(aboutMe)
        """
    }

    /// Render a full pack: optional About Me + selected collections.
    static func render(aboutMe: String?, collections: [CollectionInput]) -> String {
        var sections: [String] = [header]

        if let aboutMe, !aboutMe.isEmpty {
            sections.append("## About the user\n\(aboutMe)")
        }

        for collection in collections {
            var block = "## Collection: \(collection.name)"
            if !collection.details.isEmpty {
                block += "\n\(collection.details)"
            }
            if !collection.aspects.isEmpty {
                let aspectLine = collection.aspects
                    .map { "\($0.kind): \($0.value)" }
                    .joined(separator: " · ")
                block += "\n*Aspects — \(aspectLine)*"
            }
            for memory in collection.memories {
                block += "\n\n### \(memory.title)\n\(memory.body)"
            }
            sections.append(block)
        }

        return sections.joined(separator: "\n\n")
    }

    /// Convenience: build inputs from a live collection (main actor —
    /// touches SwiftData models).
    @MainActor
    static func input(from collection: MemoryCollection) -> CollectionInput {
        CollectionInput(
            name: collection.name,
            details: collection.details,
            aspects: collection.aspects.map { ($0.kind.rawValue, $0.value) },
            memories: collection.memories.map {
                MemoryInput(title: $0.title, body: $0.summary ?? String($0.body.prefix(2000)))
            }
        )
    }
}
