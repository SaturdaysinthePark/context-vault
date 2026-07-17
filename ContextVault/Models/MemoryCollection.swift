import Foundation
import SwiftData

/// A structured lens on a collection: people, projects, topics, timeframes.
/// Aspects become metadata in the Spotlight index and scope retrieval.
struct Aspect: Codable, Hashable, Sendable {
    enum Kind: String, Codable, CaseIterable, Sendable {
        case topic
        case person
        case project
        case timeframe
        case source
    }

    var kind: Kind
    var value: String
}

/// A user-curated grouping of memories.
@Model
final class MemoryCollection {
    @Attribute(.unique) var id: UUID
    var name: String
    var details: String
    var aspectsData: Data
    /// Per-collection control over whether the system AI (Siri / Apple
    /// Intelligence) may see this collection's memories. The core privacy
    /// differentiator: index entries are added/removed when this flips.
    var siriVisible: Bool
    var createdAt: Date
    @Relationship(inverse: \Memory.collections) var memories: [Memory]

    var aspects: [Aspect] {
        get { (try? JSONDecoder().decode([Aspect].self, from: aspectsData)) ?? [] }
        set { aspectsData = (try? JSONEncoder().encode(newValue)) ?? Data() }
    }

    init(
        id: UUID = UUID(),
        name: String,
        details: String = "",
        aspects: [Aspect] = [],
        siriVisible: Bool = true,
        createdAt: Date = .now,
        memories: [Memory] = []
    ) {
        self.id = id
        self.name = name
        self.details = details
        self.aspectsData = (try? JSONEncoder().encode(aspects)) ?? Data()
        self.siriVisible = siriVisible
        self.createdAt = createdAt
        self.memories = memories
    }
}
